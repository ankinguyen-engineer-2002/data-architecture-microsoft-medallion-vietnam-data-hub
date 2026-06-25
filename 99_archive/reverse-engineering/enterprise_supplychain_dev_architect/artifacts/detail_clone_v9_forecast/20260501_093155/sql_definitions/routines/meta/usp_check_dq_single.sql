-- Source: SupplyChain_Warehouse.meta.usp_check_dq_single
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_check_dq_single
    @rule_id INT,
    @pipeline_run_id VARCHAR(36) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rule_name VARCHAR(200), @target_schema VARCHAR(50), @target_table VARCHAR(200);
    DECLARE @check_type VARCHAR(30), @column_name VARCHAR(100), @severity VARCHAR(10);
    DECLARE @threshold DECIMAL(18,2), @params VARCHAR(1000), @layer VARCHAR(10);

    SELECT @rule_name = rule_name, @target_schema = target_schema, @target_table = target_table,
           @check_type = check_type, @column_name = column_name, @severity = severity,
           @threshold = threshold, @params = params, @layer = layer
    FROM meta.dq_rules
    WHERE rule_id = @rule_id AND is_active = 1;

    IF @rule_name IS NULL RETURN;

    DECLARE @sql NVARCHAR(4000), @actual_value VARCHAR(500), @expected_value VARCHAR(500);
    DECLARE @result_val DECIMAL(18,4), @status VARCHAR(10);
    DECLARE @full_table NVARCHAR(500) = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    BEGIN TRY
        IF @check_type = 'completeness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(SUM(CASE WHEN ' + QUOTENAME(@column_name) + N' IS NULL THEN 0 ELSE 1 END) * 100.0 / NULLIF(COUNT(*),0) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual_value = CAST(@result_val AS VARCHAR(50));
            SET @expected_value = CASE WHEN @threshold IS NOT NULL THEN CAST(@threshold AS VARCHAR(50)) ELSE '100.0' END;
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 100.0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'row_count'
        BEGIN
            SET @sql = N'SELECT @val = CAST(COUNT(*) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual_value = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected_value = CAST(@threshold AS VARCHAR(50));
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'uniqueness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(COUNT(*) - COUNT(DISTINCT ' + QUOTENAME(@column_name) + N') AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual_value = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected_value = '0';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'freshness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(DATEDIFF(HOUR, MAX(_load_dt), CAST(GETUTCDATE() AS DATETIME2(6))) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual_value = CAST(CAST(@result_val AS INT) AS VARCHAR(50)) + ' hours';
            SET @expected_value = '<= ' + CAST(@threshold AS VARCHAR(50)) + ' hours';
            SET @status = CASE WHEN @result_val <= ISNULL(@threshold, 24) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type IN ('custom_sql', 'referential_integrity', 'validity')
        BEGIN
            SET @sql = CAST(@params AS NVARCHAR(4000));
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual_value = CAST(@result_val AS VARCHAR(50));
            SET @expected_value = '0';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END

        -- Write result with retry (snapshot conflict protection)
        DECLARE @write_attempt INT = 0, @write_done INT = 0;
        WHILE @write_attempt < 3 AND @write_done = 0
        BEGIN
            BEGIN TRY
                DELETE FROM meta.dq_results WHERE rule_id = @rule_id;
                INSERT INTO meta.dq_results (result_id, pipeline_run_id, rule_id, check_time, status, actual_value, expected_value, error_detail)
                VALUES (
                    @rule_id, @pipeline_run_id, @rule_id,
                    CAST(GETUTCDATE() AS DATETIME2(6)), @status, @actual_value, @expected_value,
                    @check_type + ' on ' + @target_schema + '.' + @target_table
                        + CASE WHEN @column_name IS NOT NULL THEN '.' + @column_name ELSE '' END
                        + ': ' + @severity
                );
                SET @write_done = 1;
            END TRY
            BEGIN CATCH
                SET @write_attempt = @write_attempt + 1;
                IF @write_attempt < 3
                    WAITFOR DELAY '00:00:02';
            END CATCH
        END

        IF @status = 'FAIL' AND @severity = 'CRITICAL'
        BEGIN
            DECLARE @err_msg NVARCHAR(500) = N'DQ CRITICAL FAIL: ' + CAST(@rule_name AS NVARCHAR(200))
                + N' | actual=' + ISNULL(CAST(@actual_value AS NVARCHAR(100)), N'NULL')
                + N' | expected=' + ISNULL(CAST(@expected_value AS NVARCHAR(100)), N'NULL');
            THROW 50001, @err_msg, 1;
        END

    END TRY
    BEGIN CATCH
        -- Write error result with retry
        DECLARE @err_write INT = 0, @err_done INT = 0;
        WHILE @err_write < 3 AND @err_done = 0
        BEGIN
            BEGIN TRY
                IF NOT EXISTS (SELECT 1 FROM meta.dq_results WHERE rule_id = @rule_id AND check_time >= DATEADD(SECOND, -10, CAST(GETUTCDATE() AS DATETIME2(6))) AND status IN ('PASS','FAIL'))
                BEGIN
                    DELETE FROM meta.dq_results WHERE rule_id = @rule_id;
                    INSERT INTO meta.dq_results (result_id, pipeline_run_id, rule_id, check_time, status, actual_value, expected_value, error_detail)
                    VALUES (@rule_id, @pipeline_run_id, @rule_id, CAST(GETUTCDATE() AS DATETIME2(6)), 'ERROR', NULL, NULL, ERROR_MESSAGE());
                END
                SET @err_done = 1;
            END TRY
            BEGIN CATCH
                SET @err_write = @err_write + 1;
                IF @err_write < 3
                    WAITFOR DELAY '00:00:02';
            END CATCH
        END

        IF @severity = 'CRITICAL'
            THROW;
    END CATCH
END
