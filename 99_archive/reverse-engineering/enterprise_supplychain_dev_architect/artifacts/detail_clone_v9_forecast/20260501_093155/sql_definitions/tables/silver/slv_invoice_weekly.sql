-- Source: SupplyChain_Warehouse.silver.slv_invoice_weekly
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [silver].[slv_invoice_weekly] (
    [id_account_ship_to] varchar(8000) NULL,
    [id_item_sku] varchar(8000) NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_customer_group] varchar(8000) NULL,
    [dt_fsc_week_first] date NULL,
    [dt_fsc_week_last] date NULL,
    [qty_shipped] decimal(38,6) NULL,
    [amt_net_sales] decimal(38,6) NULL,
    [amt_invoice] decimal(38,6) NULL,
    [amt_freight] decimal(38,6) NULL,
    [num_invoice_lines] int NULL,
    [num_distinct_invoices] int NULL,
    [_load_dt] datetime2(6) NULL
);
