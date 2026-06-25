-- Source: SupplyChain_Warehouse.meta.usp_log_run
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE PROCEDURE meta.usp_log_run
    @run_id         VARCHAR(36),
    @sp_name        VARCHAR(200),
    @status         VARCHAR(20),
    @rows_affected  BIGINT          = NULL,
    @error_message  VARCHAR(4000)   = NULL,
    @pipeline_run_id VARCHAR(36)    = NULL,
    @load_type      VARCHAR(20)     = NULL
AS
BEGIN
    DECLARE @retry INT = 0;
    DECLARE @done INT = 0;
    DECLARE @now DATETIME2(6) = GETUTCDATE();
    DECLARE @now_cst DATETIME2(6) = meta.ufn_utc_to_cst(@now);

    WHILE @retry < 3 AND @done = 0
    BEGIN
        BEGIN TRY
            IF @status = 'running'
            BEGIN
                INSERT INTO meta.sp_run_history
                    (run_id, pipeline_run_id, sp_name, start_time, start_cst, status, load_type)
                VALUES
                    (@run_id, @pipeline_run_id, @sp_name, @now, @now_cst, 'running', @load_type);
            END
            ELSE
            BEGIN
                UPDATE meta.sp_run_history
                SET end_time         = @now,
                    end_cst          = @now_cst,
                    duration_seconds = DATEDIFF(SECOND, start_time, @now),
                    rows_affected    = @rows_affected,
                    status           = @status,
                    error_message    = @error_message
                WHERE run_id = @run_id;

                UPDATE meta.sp_registry
                SET last_load_date = @now,
                    rows_loaded    = @rows_affected,
                    next_run_time  = CASE
                        WHEN frequency = 'daily'   THEN DATEADD(DAY, 1, CAST(@now AS DATE))
                        WHEN frequency = 'hourly'  THEN DATEADD(HOUR, 1, @now)
                        WHEN frequency = 'weekly'  THEN DATEADD(WEEK, 1, CAST(@now AS DATE))
                        WHEN frequency = 'monthly' THEN DATEADD(MONTH, 1, CAST(@now AS DATE))
                        ELSE DATEADD(DAY, 1, CAST(@now AS DATE))
                    END
                WHERE sp_name = @sp_name;
            END

            SET @done = 1;
        END TRY
        BEGIN CATCH
            SET @retry = @retry + 1;
            IF @retry >= 3
            BEGIN
                DECLARE @err_msg VARCHAR(4000) = ERROR_MESSAGE();
                RAISERROR('usp_log_run failed after 3 retries: %s', 10, 1, @err_msg);
            END
            WAITFOR DELAY '00:00:02';
        END CATCH
    END
END
