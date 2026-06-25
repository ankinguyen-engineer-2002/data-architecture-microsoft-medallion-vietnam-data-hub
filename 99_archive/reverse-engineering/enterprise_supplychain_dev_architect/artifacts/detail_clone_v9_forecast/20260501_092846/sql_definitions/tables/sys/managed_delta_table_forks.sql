-- Source: SupplyChain_Warehouse.sys.managed_delta_table_forks
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[managed_delta_table_forks] (
    [commit_sequence_id] bigint NOT NULL,
    [fork_guid] uniqueidentifier NOT NULL,
    [source_table_guid] uniqueidentifier NOT NULL,
    [source_database_guid] uniqueidentifier NOT NULL,
    [xdes_ts] bigint NOT NULL,
    [commit_time] datetime NOT NULL,
    [table_guid] uniqueidentifier NOT NULL,
    [folder_name] nvarchar(40) NULL
);
