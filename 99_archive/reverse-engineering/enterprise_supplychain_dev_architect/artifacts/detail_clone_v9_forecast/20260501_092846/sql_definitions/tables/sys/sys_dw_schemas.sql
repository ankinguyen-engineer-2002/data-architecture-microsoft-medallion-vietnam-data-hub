-- Source: SupplyChain_Warehouse.sys.sys_dw_schemas
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [sys].[sys_dw_schemas] (
    [name] nvarchar(128) NOT NULL,
    [schema_id] int NOT NULL,
    [principal_id] int NULL,
    [is_internal] bit NULL
);
