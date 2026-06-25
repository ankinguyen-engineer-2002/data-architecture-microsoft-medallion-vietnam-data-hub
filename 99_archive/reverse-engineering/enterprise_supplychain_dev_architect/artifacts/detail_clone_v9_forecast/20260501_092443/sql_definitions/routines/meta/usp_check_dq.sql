-- Source: SupplyChain_Warehouse.meta.usp_check_dq
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_check_dq
    @layer              VARCHAR(10),
    @pipeline_run_id    VARCHAR(36) = NULL
AS
BEGIN
    DECLARE @rule_id        INT;
    DECLARE @target_schema  NVARCHAR(200);
    DECLARE @target_table   NVARCHAR(200);
    DECLARE @check_type     VARCHAR(30);
    DECLARE @column_name    NVARCHAR(200);
    DECLARE @severity       VARCHAR(10);
    DECLARE @threshold      DECIMAL(18,2);
    DECLARE @sql            NVARCHAR(4000);
    DECLARE @result         INT;
    DECLARE @actual_val     VARCHAR(500);
    DECLARE @expected_val   VARCHAR(500);
    DECLARE @status         VARCHAR(10);
    DECLARE @has_critical   INT = 0;
    DECLARE @next_result_id INT;
    DECLARE @tgt            NVARCHAR(500);

    SELECT @next_result_id = ISNULL(MAX(result_id), 0) FROM meta.dq_results;
    SELECT @rule_id = MIN(rule_id) FROM meta.dq_rules WHERE layer = @layer AND is_active = 1;

    WHILE @rule_id IS NOT NULL
    BEGIN
        SET @result = 0;
        SET @actual_val = NULL;
        SET @expected_val = NULL;
        SET @status = 'PASS';

        SELECT @target_schema = CAST(target_schema AS NVARCHAR(200)),
               @target_table  = CAST(target_table AS NVARCHAR(200)),
               @check_type    = check_type,
               @column_name   = CAST(column_name AS NVARCHAR(200)),
               @severity      = severity,
               @threshold     = threshold
        FROM meta.dq_rules
        WHERE rule_id = @rule_id;

        SET @tgt = @target_schema + N'.' + @target_table;

        BEGIN TRY
            IF @check_type = 'completeness'
            BEGIN
                SET @sql = N'SELECT @r = COUNT(*) FROM ' + @tgt + N' WHERE ' + @column_name + N' IS NULL';
                EXEC sp_executesql @sql, N'@r INT OUTPUT', @r = @result OUTPUT;
                SET @actual_val = CAST(@result AS VARCHAR) + ' nulls';
                SET @expected_val = '0 nulls';
                IF @result > 0 SET @status = 'FAIL';
            END
            ELSE IF @check_type = 'row_count'
            BEGIN
                SET @sql = N'SELECT @r = COUNT(*) FROM ' + @tgt;
                EXEC sp_executesql @sql, N'@r INT OUTPUT', @r = @result OUTPUT;
                SET @actual_val = CAST(@result AS VARCHAR) + ' rows';
                SET @expected_val = '>=' + CAST(CAST(@threshold AS INT) AS VARCHAR);
                IF @result < CAST(@threshold AS INT) SET @status = 'FAIL';
            END
            ELSE IF @check_type = 'uniqueness'
            BEGIN
                SET @sql = N'SELECT @r = COUNT(*) FROM (SELECT ' + @column_name
                         + N', COUNT(*) AS cnt FROM ' + @tgt
                         + N' GROUP BY ' + @column_name + N' HAVING COUNT(*) > 1) t';
                EXEC sp_executesql @sql, N'@r INT OUTPUT', @r = @result OUTPUT;
                SET @actual_val = CAST(@result AS VARCHAR) + ' duplicates';
                SET @expected_val = '0 duplicates';
                IF @result > 0 SET @status = 'FAIL';
            END
            ELSE IF @check_type = 'freshness'
            BEGIN
                SET @sql = N'SELECT @r = CASE WHEN MAX(' + @column_name
                         + N') >= DATEADD(HOUR, -24, GETUTCDATE()) THEN 0 ELSE 1 END FROM ' + @tgt;
                EXEC sp_executesql @sql, N'@r INT OUTPUT', @r = @result OUTPUT;
                SET @actual_val = CASE WHEN @result = 0 THEN 'fresh' ELSE 'stale' END;
                SET @expected_val = 'within 24h';
                IF @result > 0 SET @status = 'FAIL';
            END

            IF @status = 'FAIL' AND @severity = 'CRITICAL'
                SET @has_critical = @has_critical + 1;
        END TRY
        BEGIN CATCH
            SET @status = 'FAIL';
            SET @actual_val = LEFT(ERROR_MESSAGE(), 500);
            SET @expected_val = '';
            IF @severity = 'CRITICAL' SET @has_critical = @has_critical + 1;
        END CATCH

        SET @next_result_id = @next_result_id + 1;
        INSERT INTO meta.dq_results (result_id, pipeline_run_id, rule_id, check_time, status, actual_value, expected_value, error_detail)
        VALUES (@next_result_id, @pipeline_run_id, @rule_id, CAST(GETUTCDATE() AS DATETIME2(6)),
                @status, @actual_val, @expected_val,
                CASE WHEN @status = 'FAIL' THEN @actual_val ELSE NULL END);

        SELECT @rule_id = MIN(rule_id) FROM meta.dq_rules
        WHERE rule_id > @rule_id AND layer = @layer AND is_active = 1;
    END

    IF @has_critical > 0
    BEGIN
        DECLARE @msg NVARCHAR(500) = N'DQ CRITICAL: ' + CAST(@has_critical AS NVARCHAR(10)) + N' failures in layer ' + CAST(@layer AS NVARCHAR(10));
        THROW 50001, @msg, 1;
    END
END
