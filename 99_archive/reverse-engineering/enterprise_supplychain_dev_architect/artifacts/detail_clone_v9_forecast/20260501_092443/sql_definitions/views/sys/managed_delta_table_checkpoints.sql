-- Source: SupplyChain_Warehouse.sys.managed_delta_table_checkpoints
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW sys.managed_delta_table_checkpoints
AS
SELECT f.delta_log_commit_sequence_id, f.part, f.file_guid, f.version, f.source_table_guid, p.source_database_guid, t.table_guid, p.checkpoint_file_name, p.manifest_root 
FROM sys.manageddeltatables t
JOIN sys.manageddeltatablecheckpoints f
ON t.table_id = f.table_id and t.drop_commit_time <= '1900-01-01T00:00:00'
OUTER APPLY OpenRowSet(TABLE DW_PHYSICAL_CHECKPOINT_FILES, t.sql_object_id, f.delta_log_commit_sequence_id, f.part, f.source_table_guid, f.source_database_guid) p
