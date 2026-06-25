-- Source: SupplyChain_Warehouse.meta.usp_validate_schema_contracts
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_validate_schema_contracts
    @pipeline_run_id VARCHAR(36) = NULL
AS
BEGIN
    DECLARE @drift_count INT = 0, @checked INT = 0;
    DECLARE @cur_target VARCHAR(200), @cur_source VARCHAR(500);
    DECLARE @source_db VARCHAR(100), @source_schema VARCHAR(100), @source_table VARCHAR(100);
    DECLARE @contracted_cols INT, @actual_cols INT;
    DECLARE @count_sql NVARCHAR(1000);
    DECLARE @prev_target VARCHAR(200) = '';

    -- Iterate distinct target_table from schema_contracts
    SELECT @cur_target = MIN(target_table) FROM meta.schema_contracts WHERE is_active = 1;
    
    WHILE @cur_target IS NOT NULL
    BEGIN
        SELECT TOP 1 @cur_source = source_object FROM meta.schema_contracts 
        WHERE target_table = @cur_target AND is_active = 1;
        
        SET @source_db = PARSENAME(@cur_source, 3);
        SET @source_schema = PARSENAME(@cur_source, 2);
        SET @source_table = PARSENAME(@cur_source, 1);
        
        SELECT @contracted_cols = COUNT(*) FROM meta.schema_contracts 
        WHERE target_table = @cur_target AND is_active = 1;
        
        SET @count_sql = N'SELECT @ac = COUNT(*) FROM ' + QUOTENAME(@source_db) + 
            '.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @sch AND TABLE_NAME = @tbl';
        
        SET @actual_cols = -1;
        BEGIN TRY
            EXEC sp_executesql @count_sql, 
                N'@sch VARCHAR(100), @tbl VARCHAR(100), @ac INT OUTPUT',
                @sch = @source_schema, @tbl = @source_table, @ac = @actual_cols OUTPUT;
            SET @checked = @checked + 1;
            
            IF @actual_cols = @contracted_cols
                UPDATE meta.schema_contracts 
                SET last_validated = CAST(GETUTCDATE() AS DATETIME2(6)), validation_status = 'valid'
                WHERE target_table = @cur_target AND is_active = 1;
            ELSE
            BEGIN
                SET @drift_count = @drift_count + 1;
                UPDATE meta.schema_contracts 
                SET last_validated = CAST(GETUTCDATE() AS DATETIME2(6)), validation_status = 'drift'
                WHERE target_table = @cur_target AND is_active = 1;
            END
        END TRY
        BEGIN CATCH
            UPDATE meta.schema_contracts 
            SET last_validated = CAST(GETUTCDATE() AS DATETIME2(6)), validation_status = 'error'
            WHERE target_table = @cur_target AND is_active = 1;
        END CATCH
        
        SELECT @cur_target = MIN(target_table) FROM meta.schema_contracts 
        WHERE is_active = 1 AND target_table > @cur_target;
    END
    
    IF @drift_count > 0 AND @pipeline_run_id IS NOT NULL
    BEGIN
        DECLARE @next_rid INT;
        SELECT @next_rid = ISNULL(MAX(result_id),0)+1 FROM meta.dq_results;
        
        BEGIN TRY
            INSERT INTO meta.dq_results (result_id, pipeline_run_id, rule_id, check_time, status, actual_value, expected_value, error_detail)
            VALUES (@next_rid, @pipeline_run_id, 0, CAST(GETUTCDATE() AS DATETIME2(6)), 'WARNING', 
                CAST(@drift_count AS VARCHAR) + ' source(s) schema drift', '0 drift', 
                'Check meta.schema_contracts WHERE validation_status = drift');
        END TRY
        BEGIN CATCH
            DECLARE @err VARCHAR(200) = ERROR_MESSAGE();
        END CATCH
    END
END
