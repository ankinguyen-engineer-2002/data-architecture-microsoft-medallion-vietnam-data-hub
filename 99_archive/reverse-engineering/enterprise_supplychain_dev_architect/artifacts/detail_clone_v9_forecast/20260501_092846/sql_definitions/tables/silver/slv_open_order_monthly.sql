-- Source: SupplyChain_Warehouse.silver.slv_open_order_monthly
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [silver].[slv_open_order_monthly] (
    [id_item_sku] varchar(8000) NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_customer_group] varchar(8000) NULL,
    [dt_fsc_month_first] date NULL,
    [dt_fsc_month_last] date NULL,
    [qty_open_order] int NULL,
    [qty_backorder] int NULL,
    [amt_open_order] decimal(38,2) NULL,
    [amt_backorder] decimal(38,2) NULL,
    [num_order_lines] int NULL,
    [num_distinct_orders] int NULL,
    [qty_past_due] int NULL,
    [amt_past_due] decimal(38,2) NULL,
    [_load_dt] datetime2(6) NULL
);
