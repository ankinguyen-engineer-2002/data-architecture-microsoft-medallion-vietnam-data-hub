
CREATE VIEW Meta.vw_SilverWaveRuntime AS
SELECT
    r.project,
    r.wave_number,
    r.asset_id,
    r.physical_schema AS target_schema,
    r.physical_object AS target_object,
    a.depends_on AS depends_on_asset_ids,
    CASE
        WHEN a.is_active = 1
         AND (a.next_run_time IS NULL OR a.next_run_time <= SYSUTCDATETIME()) THEN 1
        ELSE 0
    END AS is_due,
    CAST('Pending' AS VARCHAR(80)) AS execution_status,
    r.computed_at_utc
FROM Meta.SilverDagWaveRuntime r
JOIN Meta.AssetRegistry a
    ON a.asset_id = r.asset_id;
