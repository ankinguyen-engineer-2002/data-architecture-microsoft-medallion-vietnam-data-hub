-- Source: SupplyChain_Warehouse.sys.managed_delta_table_checkpoints
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[managed_delta_table_checkpoints] (
    [delta_log_commit_sequence_id] bigint NOT NULL,
    [part] int NOT NULL,
    [file_guid] uniqueidentifier NOT NULL,
    [version] bigint NOT NULL,
    [source_table_guid] uniqueidentifier NOT NULL,
    [source_database_guid] uniqueidentifier NULL,
    [table_guid] uniqueidentifier NOT NULL,
    [checkpoint_file_name] nvarchar(256) NULL,
    [manifest_root] nvarchar(256) NULL
);
