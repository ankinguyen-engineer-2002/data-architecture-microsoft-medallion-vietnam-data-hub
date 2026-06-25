-- Source: SupplyChain_Warehouse.sys.managed_delta_tables
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[managed_delta_tables] (
    [table_id] bigint NOT NULL,
    [object_id] int NOT NULL,
    [table_guid] uniqueidentifier NOT NULL,
    [fork_guid] uniqueidentifier NOT NULL,
    [delta_log_feature_status] int NOT NULL,
    [manifest_root] nvarchar(256) NULL,
    [system_task_consideration_bitmask] int NULL,
    [drop_commit_time] datetime NULL
);
