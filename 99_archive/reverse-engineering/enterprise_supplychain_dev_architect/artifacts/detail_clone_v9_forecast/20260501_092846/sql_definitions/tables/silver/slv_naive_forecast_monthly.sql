-- Source: SupplyChain_Warehouse.silver.slv_naive_forecast_monthly
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [silver].[slv_naive_forecast_monthly] (
    [id_item_sku] varchar(8000) NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_customer_group] varchar(8000) NULL,
    [dt_fsc_month_first] date NULL,
    [dt_fsc_month_last] date NULL,
    [qty_demand] int NULL,
    [code_status] varchar(14) NOT NULL,
    [name_version] varchar(14) NOT NULL,
    [_load_dt] datetime2(6) NULL
);
