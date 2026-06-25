-- Source: SupplyChain_Warehouse.bronze.vw_brz_supplychain_enh_1__demandforecastsnapshotdaily
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[vw_brz_supplychain_enh_1__demandforecastsnapshotdaily] (
    [id_item_sku] varchar(8000) NULL,
    [code_warehouse] varchar(8000) NULL,
    [num_fiscal_month] bigint NULL,
    [code_customer_group] varchar(8000) NULL,
    [qty_resultant_forecast] float NULL,
    [qty_promotional_lift] float NULL,
    [qty_forced_forecast] float NULL,
    [qty_order_future] bigint NULL,
    [qty_perm_component] float NULL,
    [ts_snapshot] datetime2(6) NULL,
    [code_main_piece] varchar(8000) NULL,
    [name_collective_class] varchar(8000) NULL,
    [name_product_category] varchar(8000) NULL,
    [code_forecast_type] varchar(8000) NULL,
    [code_management] varchar(8000) NULL,
    [id_derived_forecast] varchar(8000) NULL,
    [val_derived_forecast_factor] float NULL,
    [num_valid_demand_months] bigint NULL,
    [name_usr25] varchar(8000) NULL,
    [name_created_by] varchar(8000) NULL,
    [ts_created] datetime2(6) NULL,
    [name_modified_by] varchar(8000) NULL,
    [ts_modified] datetime2(6) NULL
);
