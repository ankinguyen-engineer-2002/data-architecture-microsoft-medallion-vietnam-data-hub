-- Source: SupplyChain_Warehouse.bronze.vw_ref_warehouse
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[vw_ref_warehouse] (
    [sk_warehouse] int NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_intransit_warehouse] varchar(8000) NULL,
    [code_container_direct] varchar(8000) NULL,
    [is_controlled_warehouse] int NULL,
    [name_warehouse_location] varchar(8000) NULL,
    [name_warehouse_order_group] varchar(8000) NULL,
    [is_finance_inventory_report] int NULL
);
