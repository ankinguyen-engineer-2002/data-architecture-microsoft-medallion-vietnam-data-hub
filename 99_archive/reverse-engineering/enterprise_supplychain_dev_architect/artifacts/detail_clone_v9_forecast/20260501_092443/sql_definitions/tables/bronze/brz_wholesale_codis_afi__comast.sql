-- Source: SupplyChain_Warehouse.bronze.brz_wholesale_codis_afi__comast
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[brz_wholesale_codis_afi__comast] (
    [code_record_type] varchar(8000) NULL,
    [id_order] varchar(8000) NULL,
    [id_customer] varchar(8000) NULL,
    [id_customer_po] varchar(8000) NULL,
    [dt_order] date NULL,
    [amt_order_value] decimal(14,2) NULL,
    [code_warehouse] varchar(8000) NULL,
    [code_salesperson] varchar(200) NULL,
    [code_ship_to] varchar(8000) NULL,
    [dt_requested] date NULL,
    [num_lead_time_days] int NULL,
    [name_shipping_instructions] varchar(8000) NULL,
    [dt_customer_paid] date NULL,
    [code_priority] varchar(8000) NULL,
    [code_memo] varchar(8000) NULL,
    [_load_dt] datetime2(6) NULL
);
