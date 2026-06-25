
CREATE OR ALTER PROCEDURE Meta.usp_CheckDqSingle
    @rule_id INT, @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rule_name VARCHAR(200), @target_schema VARCHAR(128), @target_table VARCHAR(256);
    DECLARE @check_type VARCHAR(30), @column_name VARCHAR(100), @severity VARCHAR(10);
    DECLARE @threshold DECIMAL(18,4), @params VARCHAR(1000), @layer VARCHAR(80);

    SELECT @rule_name=rule_name, @target_schema=target_schema, @target_table=target_table,
           @check_type=check_type, @column_name=column_name, @severity=severity,
           @threshold=TRY_CAST(NULLIF(threshold, '') AS DECIMAL(18,4)), @params=params, @layer=layer
    FROM Meta.DQRule WHERE rule_id=@rule_id AND is_active=1;
    IF @rule_name IS NULL RETURN;

    DECLARE @sql NVARCHAR(4000), @actual VARCHAR(500), @expected VARCHAR(500);
    DECLARE @result_val DECIMAL(18,4) = NULL, @status VARCHAR(10) = 'SKIP';
    DECLARE @full_table NVARCHAR(500);
    DECLARE @gate_id VARCHAR(128) = 'dqr::' + CAST(@rule_id AS VARCHAR(20));

    IF @layer = 'Bronze'
        SET @full_table = N'[Enterprise_Lakehouse].' + QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);
    ELSE IF @layer = 'Gold'
        SET @full_table = N'[SupplyChain_Gold_Warehouse].' + QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);
    ELSE
        SET @full_table = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    BEGIN TRY
        IF @check_type = 'completeness'
        BEGIN
            SET @sql = N'SELECT @v = CAST(SUM(CASE WHEN ' + QUOTENAME(@column_name) + N' IS NULL THEN 0 ELSE 1 END) * 100.0 / NULLIF(COUNT(*),0) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(@result_val AS VARCHAR(50));
            SET @expected = CASE WHEN @threshold IS NOT NULL THEN CAST(@threshold AS VARCHAR(50)) ELSE '100.0' END;
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 100.0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'row_count'
        BEGIN
            SET @sql = N'SELECT @v = CAST(COUNT_BIG(*) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected = CAST(@threshold AS VARCHAR(50));
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'uniqueness'
        BEGIN
            SET @sql = N'SELECT @v = CAST(COUNT_BIG(*) - COUNT(DISTINCT ' + QUOTENAME(@column_name) + N') AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected = '0';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'freshness'
        BEGIN
            SET @sql = N'SELECT @v = CAST(DATEDIFF(HOUR, MAX(' + QUOTENAME(@column_name) + N'), CAST(GETUTCDATE() AS DATETIME2(6))) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS INT) AS VARCHAR(50)) + ' hours';
            SET @expected = '<= ' + CAST(@threshold AS VARCHAR(50)) + ' hours';
            SET @status = CASE WHEN @result_val <= ISNULL(@threshold, 24) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'expected_zero'
        BEGIN
            SET @sql = N'SELECT @v = CAST(SUM(CASE WHEN TRY_CAST(' + QUOTENAME(@column_name) + N' AS DECIMAL(38,4)) <> 0 THEN 1 ELSE 0 END) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50)) + ' nonzero rows';
            SET @expected = '0 nonzero (deprecated)';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'expected_dup_ratio_max'
        BEGIN
            DECLARE @grain NVARCHAR(500) = JSON_VALUE(@params, '$.grain');
            IF @grain IS NULL SET @grain = ISNULL(@column_name, '');
            SET @sql = N'SELECT @v = CAST((COUNT_BIG(*) - COUNT(DISTINCT CONCAT(' + @grain + N'))) * 100.0 / NULLIF(COUNT_BIG(*),0) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUTPUT', @v = @result_val OUTPUT;
            SET @actual = CAST(@result_val AS VARCHAR(50)) + '%';
            SET @expected = '<= ' + CAST(@threshold AS VARCHAR(50)) + '%';
            SET @status = CASE WHEN @result_val <= ISNULL(@threshold, 1.0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE
        BEGIN
            SET @status = 'SKIP'; SET @actual = 'unsupported: ' + @check_type; SET @expected = 'N/A';
        END

        -- DELETE + INSERT via dynamic SQL (Fabric DW: avoid @var in DML predicates)
        DECLARE @del NVARCHAR(500) = N'DELETE FROM Meta.DQGateRun WHERE dq_gate_run_id = ''' + REPLACE(@gate_id, '''', '''''') + '''';
        EXEC sp_executesql @del;

        DECLARE @ins NVARCHAR(2000) = N'INSERT INTO Meta.DQGateRun (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message) VALUES ('
            + '''' + REPLACE(@gate_id, '''', '''''') + ''', '
            + '''' + REPLACE(@target_schema + '.' + @target_table, '''', '''''') + ''', '
            + CASE WHEN @pipeline_run_id IS NULL THEN 'NULL' ELSE '''' + REPLACE(@pipeline_run_id, '''', '''''') + '''' END + ', '
            + '''' + REPLACE(@check_type + ' on ' + @target_schema + '.' + @target_table + CASE WHEN @column_name IS NOT NULL THEN '.' + @column_name ELSE '' END + ': ' + @severity, '''', '''''') + ''', '
            + '''' + @status + ''', '
            + 'CAST(GETUTCDATE() AS DATETIME2(6)), '
            + CAST(CASE WHEN @status = 'FAIL' THEN 1 ELSE 0 END AS VARCHAR(2)) + ', '
            + '''' + REPLACE(ISNULL(@actual,'') + ' vs ' + ISNULL(@expected,'N/A'), '''', '''''') + '''' + ')';
        EXEC sp_executesql @ins;

        IF @status = 'FAIL' AND @severity = 'CRITICAL' THROW 50002, @rule_name, 1;
    END TRY
    BEGIN CATCH
        DECLARE @err VARCHAR(500) = LEFT(ERROR_MESSAGE(), 500);
        DECLARE @err_ins NVARCHAR(2000) = N'INSERT INTO Meta.DQGateRun (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message) VALUES ('
            + '''' + REPLACE(@gate_id, '''', '''''') + ''', '
            + '''' + REPLACE(@target_schema + '.' + @target_table, '''', '''''') + ''', '
            + 'NULL, '
            + '''' + REPLACE('ERROR: ' + @check_type, '''', '''''') + ''', '
            + '''ERROR'', '
            + 'CAST(GETUTCDATE() AS DATETIME2(6)), 1, '
            + '''' + REPLACE(@err, '''', '''''') + '''' + ')';
        BEGIN TRY EXEC sp_executesql @err_ins; END TRY BEGIN CATCH END CATCH
        IF @severity = 'CRITICAL' THROW;
    END CATCH
END
