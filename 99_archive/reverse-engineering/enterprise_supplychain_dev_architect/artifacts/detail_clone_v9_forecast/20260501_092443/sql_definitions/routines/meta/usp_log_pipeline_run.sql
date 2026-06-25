-- Source: SupplyChain_Warehouse.meta.usp_log_pipeline_run
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE PROCEDURE meta.usp_log_pipeline_run
    @pipeline_run_id    VARCHAR(36),
    @pipeline_name      VARCHAR(100),
    @status             VARCHAR(20),
    @tables_succeeded   INT = NULL,
    @tables_failed      INT = NULL,
    @notes              VARCHAR(2000) = NULL
AS
BEGIN
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = meta.ufn_utc_to_cst(@now);

    IF @status = 'running'
    BEGIN
        INSERT INTO meta.pipeline_run_log
            (pipeline_run_id, pipeline_name, status, start_time, start_cst,
             tables_succeeded, tables_failed, dq_failures_critical, notes)
        VALUES
            (@pipeline_run_id, @pipeline_name, 'running',
             @now, @now_cst, 0, 0, 0, NULL);
    END
    ELSE
    BEGIN
        UPDATE meta.pipeline_run_log
        SET status = @status,
            end_time = @now,
            end_cst = @now_cst,
            tables_succeeded = @tables_succeeded,
            tables_failed = @tables_failed,
            notes = @notes
        WHERE pipeline_run_id = @pipeline_run_id;
    END
END
