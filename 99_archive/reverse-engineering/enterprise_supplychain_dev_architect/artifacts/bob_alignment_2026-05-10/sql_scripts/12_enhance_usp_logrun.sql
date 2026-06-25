-- 12_enhance_usp_logrun.sql
-- Enhanced Meta.usp_LogRun:
--   * On 'running' status -> still writes RunLog (unchanged)
--   * On final status (success/failed/skipped):
--       - UPDATE RunLog (unchanged)
--       - UPDATE AssetRegistry last_load_date + rows_loaded + next_run_time (unchanged)
--       - INSERT into Meta.AuditLog (NEW — local clone of Bob's AuditLog pattern)
--   * On 'failed' status: also INSERT detailed error record into AuditLog
-- Phase 2: after Bob grants ETL_Framework write, also INSERT into
--          EnterpriseData-Dev.ETL_Framework.DW_Developer.AuditLog (cross-DB).

DROP PROCEDURE IF EXISTS Meta.usp_LogRun;
GO

CREATE PROCEDURE Meta.usp_LogRun
    @run_id VARCHAR(128),
    @asset_id VARCHAR(128),
    @status VARCHAR(80),
    @rows_loaded BIGINT = NULL,
    @error_message VARCHAR(4000) = NULL,
    @pipeline_run_id VARCHAR(128) = NULL,
    @load_type VARCHAR(80) = NULL
AS
BEGIN
    DECLARE @retry INT = 0, @done INT = 0;
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);
    DECLARE @user VARCHAR(200) = SYSTEM_USER;
    DECLARE @audit_id BIGINT = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', @now) AS BIGINT);

    WHILE @retry < 3 AND @done = 0
    BEGIN
        BEGIN TRY
            IF @status = 'running'
            BEGIN
                INSERT INTO Meta.RunLog (run_id, asset_id, object_name, layer_name,
                                          status, start_time_utc, start_time_cst, load_type)
                SELECT @run_id, @asset_id,
                       CONCAT(physical_schema, '.', physical_object),
                       canonical_layer, 'running', @now, @now_cst,
                       COALESCE(@load_type, load_type)
                FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
            END
            ELSE
            BEGIN
                UPDATE Meta.RunLog
                SET end_time_utc = @now,
                    end_time_cst = @now_cst,
                    rows_loaded = @rows_loaded,
                    status = @status,
                    error_message = @error_message
                WHERE run_id = @run_id;

                UPDATE Meta.AssetRegistry
                SET last_load_date = @now,
                    rows_loaded = @rows_loaded,
                    next_run_time = CASE
                        WHEN frequency = 'daily'   THEN DATEADD(DAY, 1, CAST(@now AS DATE))
                        WHEN frequency = 'hourly'  THEN DATEADD(HOUR, 1, @now)
                        WHEN frequency = 'weekly'  THEN DATEADD(WEEK, 1, CAST(@now AS DATE))
                        WHEN frequency = 'monthly' THEN DATEADD(MONTH, 1, CAST(@now AS DATE))
                        ELSE DATEADD(DAY, 1, CAST(@now AS DATE))
                    END
                WHERE asset_id = @asset_id;

                -- NEW: Audit log entry (local Meta.AuditLog clone of Bob's pattern)
                INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command,
                                            Description, ErrorMessage, AssetID, RunID,
                                            Severity, LoadDT)
                SELECT @audit_id, @now, @user,
                       CONCAT('LoadAsset:', physical_schema, '.', physical_object),
                       CASE
                           WHEN @status = 'failed'
                               THEN CONCAT('FAILED loading ', physical_schema, '.', physical_object)
                           ELSE CONCAT('Loaded ', physical_schema, '.', physical_object,
                                       ' rows=', COALESCE(CAST(@rows_loaded AS VARCHAR(20)), 'NULL'))
                       END,
                       @error_message,
                       @asset_id, @run_id,
                       CASE WHEN @status = 'failed' THEN 'ERROR' ELSE 'INFO' END,
                       @now
                FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
            END
            SET @done = 1;
        END TRY
        BEGIN CATCH
            SET @retry = @retry + 1;
            IF @retry >= 3
            BEGIN
                DECLARE @err_msg VARCHAR(4000) = ERROR_MESSAGE();
                RAISERROR('usp_LogRun failed after 3 retries: %s', 10, 1, @err_msg);
            END
            WAITFOR DELAY '00:00:02';
        END CATCH
    END
END
GO
