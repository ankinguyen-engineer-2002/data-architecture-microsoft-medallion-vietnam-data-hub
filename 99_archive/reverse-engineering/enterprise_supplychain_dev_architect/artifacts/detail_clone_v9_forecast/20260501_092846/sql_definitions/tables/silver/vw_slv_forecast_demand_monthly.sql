-- Source: SupplyChain_Warehouse.silver.vw_slv_forecast_demand_monthly
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [silver].[vw_slv_forecast_demand_monthly] (
    [id_item_sku] varchar(50) NULL,
    [code_warehouse] varchar(10) NULL,
    [code_customer_group] varchar(50) NULL,
    [dt_fsc_month_first] date NULL,
    [dt_fsc_month_last] date NULL,
    [dt_snapshot] date NULL,
    [code_horizon] varchar(10) NULL,
    [qty_forecast] float NULL,
    [code_version] varchar(20) NULL,
    [code_status] varchar(20) NULL
);
