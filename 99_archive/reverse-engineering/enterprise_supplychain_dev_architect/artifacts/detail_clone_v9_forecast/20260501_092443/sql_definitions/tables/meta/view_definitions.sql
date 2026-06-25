-- Source: SupplyChain_Warehouse.meta.view_definitions
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[view_definitions] (
    [schema] varchar(50) NOT NULL,
    [view_name] varchar(200) NOT NULL,
    [definition] varchar(4000) NULL,
    [_load_dt] datetime2(6) NOT NULL
);
