-- Source: SupplyChain_Warehouse.sys.dm_db_external_tables_log_status
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[dm_db_external_tables_log_status] (
    [object_id] int NOT NULL,
    [latest_log_version] bigint NULL,
    [latest_checkpoint_version] bigint NULL,
    [last_update_time_utc] datetime NOT NULL,
    [is_blocked] bit NOT NULL
);
