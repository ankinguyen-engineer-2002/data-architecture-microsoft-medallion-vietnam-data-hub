-- Source: SupplyChain_Warehouse.sys.external_delta_tables
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[external_delta_tables] (
    [table_id] bigint NOT NULL,
    [is_blocked] bit NOT NULL,
    [relative_path] nvarchar(2000) NOT NULL,
    [latest_manifest_version] bigint NULL,
    [latest_checkpoint_version] bigint NULL,
    [latest_checksum_version] bigint NULL,
    [latest_etag] nvarchar(128) NOT NULL,
    [last_update_time] datetime NOT NULL
);
