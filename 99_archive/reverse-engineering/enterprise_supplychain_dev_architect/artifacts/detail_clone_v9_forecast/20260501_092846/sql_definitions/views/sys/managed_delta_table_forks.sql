-- Source: SupplyChain_Warehouse.sys.managed_delta_table_forks
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW sys.managed_delta_table_forks
AS
SELECT f.commit_sequence_id, f.fork_guid, f.source_table_guid, f.source_database_guid, f.xdes_ts, f.commit_time, t.table_guid, UPPER(CAST(f.fork_guid AS NVARCHAR(40))) as folder_name
FROM sys.manageddeltatables t
JOIN sys.manageddeltatableforks f
ON t.table_id = f.table_id and t.drop_commit_time <= '1900-01-01T00:00:00'
