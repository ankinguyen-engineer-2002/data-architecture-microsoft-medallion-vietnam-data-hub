-- Source: SupplyChain_Warehouse.sys.managed_delta_table_log_files
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[managed_delta_table_log_files] (
    [commit_sequence_id] bigint NOT NULL,
    [file_guid] uniqueidentifier NOT NULL,
    [xdes_ts] bigint NOT NULL,
    [append_only] bit NOT NULL,
    [rows_inserted] bigint NOT NULL,
    [commit_time] datetime NOT NULL,
    [source_table_guid] uniqueidentifier NOT NULL,
    [source_database_guid] uniqueidentifier NULL,
    [manifest_file_name] nvarchar(256) NULL,
    [manifest_root] nvarchar(256) NULL,
    [table_guid] uniqueidentifier NOT NULL
);
