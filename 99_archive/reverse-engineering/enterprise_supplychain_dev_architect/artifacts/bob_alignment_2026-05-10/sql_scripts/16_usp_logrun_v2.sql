-- 16_usp_logrun_v2.sql
-- usp_LogRun v2 — calls usp_UpdateTableDictionary_ModifiedDate after each load.
-- Builds on Step 12 enhancement (AuditLog write); now also writes to TableDictionary + UpdateLog.
-- Pattern matches Bob's: every loader proc must end with TableDictionary refresh.

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
    DECLARE @db VARCHAR(150), @schema VARCHAR(150), @object VARCHAR(150), @sp_name VARCHAR(500);

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

                -- AuditLog (Bob pattern)
                INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command,
                                            Description, ErrorMessage, AssetID, RunID,
                                            Severity, LoadDT)
                SELECT @audit_id, @now_cst, @user,
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
                       @now_cst
                FROM Meta.AssetRegistry WHERE asset_id = @asset_id;

                -- NEW (Mức 2): TableDictionary update via Bob's pattern proc
                IF @status IN ('success', 'skipped')
                BEGIN
                    SELECT @db = physical_item, @schema = physical_schema,
                           @object = physical_object, @sp_name = legacy_sp_name
                    FROM Meta.AssetRegistry WHERE asset_id = @asset_id;

                    EXEC Meta.usp_UpdateTableDictionary_ModifiedDate
                         @DestinationDatabase = @db,
                         @DestinationSchema = @schema,
                         @DestinationTable = @object,
                         @UpdateQuery = @sp_name,
                         @DateValue = @now_cst,
                         @RowsLoaded = @rows_loaded,
                         @AssetID = @asset_id,
                         @RunID = @run_id;
                END
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
