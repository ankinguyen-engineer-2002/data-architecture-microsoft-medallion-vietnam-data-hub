-- Source: SupplyChain_Warehouse.dbo.fact_flat_forecast_actual
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [dbo].[fact_flat_forecast_actual] (
    [id_item_sku] varchar(8000) NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_customer_group] varchar(8000) NULL,
    [dt_fsc_month_first] date NULL,
    [dt_fsc_month_last] date NULL,
    [code_horizon] varchar(8000) NULL,
    [code_status] varchar(8000) NULL,
    [name_version] varchar(8000) NULL,
    [qty] float NULL
);
