-- Source: SupplyChain_Warehouse.meta.vw_run_history_tz
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW meta.vw_run_history_tz AS
SELECT
    run_id, pipeline_run_id, sp_name, status, rows_affected,
    load_type, duration_seconds, error_message,
    -- UTC (source of truth)
    start_time          AS start_utc,
    end_time            AS end_utc,
    -- CST (Enterprise/US team)
    start_cst,
    end_cst,
    -- VN (UTC+7)
    DATEADD(HOUR, 7, start_time) AS start_vn,
    DATEADD(HOUR, 7, end_time)   AS end_vn
FROM meta.sp_run_history
