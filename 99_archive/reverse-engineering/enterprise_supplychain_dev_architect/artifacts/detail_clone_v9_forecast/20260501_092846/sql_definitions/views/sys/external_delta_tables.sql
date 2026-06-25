-- Source: SupplyChain_Warehouse.sys.external_delta_tables
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW sys.external_delta_tables
AS
SELECT t.table_id, t.is_blocked, t.relative_path, IIF(t.latest_manifest_version > -1, t.latest_manifest_version, NULL ) AS latest_manifest_version, IIF(t.latest_checkpoint_version > -1, t.latest_checkpoint_version, NULL ) AS latest_checkpoint_version, IIF(t.latest_checksum_version > -1, t.latest_checksum_version, NULL ) AS latest_checksum_version, t.latest_etag, t.last_update_time 
FROM sys.externaldeltatables t
JOIN sys.manageddeltatables f
ON t.table_id = f.table_id and f.drop_commit_time <= '1900-01-01T00:00:00'
