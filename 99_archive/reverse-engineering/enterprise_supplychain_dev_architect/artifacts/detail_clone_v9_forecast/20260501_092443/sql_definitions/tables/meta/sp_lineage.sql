-- Source: SupplyChain_Warehouse.meta.sp_lineage
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[sp_lineage] (
    [lineage_id] int NOT NULL,
    [source_schema] varchar(100) NOT NULL,
    [source_table] varchar(200) NOT NULL,
    [target_schema] varchar(100) NOT NULL,
    [target_table] varchar(200) NOT NULL,
    [relationship_type] varchar(20) NULL,
    [sp_name] varchar(200) NULL
);
