-- Source: SupplyChain_Warehouse.bronze.ref_customer_account_group
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[ref_customer_account_group] (
    [id_customer] varchar(200) NULL,
    [code_customer_group] varchar(8000) NULL,
    [name_customer_group_level3] varchar(8000) NULL,
    [name_business_type] varchar(8000) NULL,
    [name_created_by] varchar(8000) NULL,
    [ts_created] datetime2(6) NULL,
    [name_modified_by] varchar(8000) NULL,
    [ts_modified] datetime2(6) NULL,
    [_load_dt] datetime2(6) NULL
);
