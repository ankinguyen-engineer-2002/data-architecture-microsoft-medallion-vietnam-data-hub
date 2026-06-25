-- Source: SupplyChain_Warehouse.meta.usp_finalize_pipeline
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_finalize_pipeline
    @pipeline_run_id VARCHAR(36) = NULL
AS
BEGIN
    -- 1. Build lineage (auto-refresh from source_objects)
    EXEC meta.usp_build_lineage;

    -- 2. Count success/failed from sp_run_history for this pipeline run
    DECLARE @succeeded INT = 0;
    DECLARE @failed INT = 0;

    SELECT @succeeded = COUNT(*) FROM meta.sp_run_history WHERE status = 'success' AND start_time >= DATEADD(MINUTE, -30, GETUTCDATE());
    SELECT @failed = COUNT(*) FROM meta.sp_run_history WHERE status = 'failed' AND start_time >= DATEADD(MINUTE, -30, GETUTCDATE());

    -- 3. Update pipeline_run_log
    IF @pipeline_run_id IS NOT NULL
    BEGIN
        DECLARE @notes VARCHAR(2000);
        SET @notes = CAST(@succeeded AS VARCHAR) + ' succeeded, ' + CAST(@failed AS VARCHAR) + ' failed';
        
        UPDATE meta.pipeline_run_log
        SET status = CASE WHEN @failed > 0 THEN 'partial' ELSE 'success' END,
            end_time = CAST(GETUTCDATE() AS DATETIME2(6)),
            tables_succeeded = @succeeded,
            tables_failed = @failed,
            notes = @notes
        WHERE pipeline_run_id = @pipeline_run_id;
    END
END
