
CREATE VIEW Meta.vw_sp_registry AS
SELECT
    r.asset_id AS sp_name,
    r.legacy_view_name AS view_name,
    r.physical_schema AS target_schema,
    r.physical_object AS target_table,
    r.canonical_layer AS layer,
    r.load_type, r.frequency, r.scheduled_hour,
    COALESCE(w.wave_number, CASE WHEN r.canonical_layer='Gold' THEN 5 ELSE 1 END) AS execution_order,
    r.depends_on, r.source_objects, r.watermark_column, r.primary_key,
    r.is_active, r.last_load_date, r.last_watermark_value, r.next_run_time,
    r.rows_loaded, r.project, r.date_key, r.date_range_days, r.cron_expression, r.access_mode
FROM Meta.AssetRegistry r
LEFT JOIN Meta.SilverDagWaveRuntime w ON w.asset_id = r.asset_id
