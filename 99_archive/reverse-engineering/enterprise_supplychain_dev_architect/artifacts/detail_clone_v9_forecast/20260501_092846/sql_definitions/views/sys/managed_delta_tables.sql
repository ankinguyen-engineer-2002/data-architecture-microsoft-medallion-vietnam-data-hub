-- Source: SupplyChain_Warehouse.sys.managed_delta_tables
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW sys.managed_delta_tables
AS
SELECT t.table_id, t.sql_object_id AS object_id, t.table_guid, t.fork_guid, t.delta_log_feature_status, p.manifest_root, s.system_task_consideration_bitmask, IIF(t.drop_commit_time > '1900-01-01T00:00:00', t.drop_commit_time, NULL ) AS drop_commit_time
FROM sys.manageddeltatables t
OUTER APPLY OpenRowSet(TABLE DW_PHYSICAL_TABLE_VALUES, t.sql_object_id, t.drop_commit_time) p
OUTER APPLY OpenRowSet(TABLE DW_SYSTEM_TASK_CONSIDERATION_BITMASK, t.sql_object_id) s
