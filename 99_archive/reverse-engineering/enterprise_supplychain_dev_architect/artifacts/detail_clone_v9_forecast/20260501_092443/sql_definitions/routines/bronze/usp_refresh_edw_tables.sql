-- Source: SupplyChain_Warehouse.bronze.usp_refresh_edw_tables
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE bronze.usp_refresh_edw_tables AS
BEGIN
    -- Refresh 4 _edw tables from Lakehouse _ver2 (EDW source)
    -- Chay TRUOC pl_sc_master (1:30 AM, truoc pipeline 2:00 AM)
    -- TAM THOI: xoa khi Enterprise_Lakehouse day du data

    -- 1. ref_product (379K rows, ~15s)
    DROP TABLE IF EXISTS bronze.ref_product_edw;
    CREATE TABLE bronze.ref_product_edw AS
    SELECT * FROM SupplyChain_Lakehouse.dbo.ref_product_ver2;

    -- 2. invoiceheader (24M rows, ~70s)
    DROP TABLE IF EXISTS bronze.brz_saleshistory_afi__invoiceheader_edw;
    CREATE TABLE bronze.brz_saleshistory_afi__invoiceheader_edw AS
    SELECT * FROM SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2;

    -- 3. invoicedetail (87M rows, ~200s)
    DROP TABLE IF EXISTS bronze.brz_saleshistory_afi__invoicedetail_edw;
    CREATE TABLE bronze.brz_saleshistory_afi__invoicedetail_edw AS
    SELECT * FROM SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2;

    -- 4. demandforecast (42M rows, ~80s) - EXCLUDE fiscal_month_last_date
    DROP TABLE IF EXISTS bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw;
    CREATE TABLE bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw AS
    SELECT 
        id_item_sku, code_warehouse, num_fiscal_month, code_customer_group,
        qty_resultant_forecast, qty_promotional_lift, qty_forced_forecast,
        qty_order_future, qty_perm_component, ts_snapshot,
        code_main_piece, name_collective_class, name_product_category,
        code_forecast_type, code_management, id_derived_forecast,
        val_derived_forecast_factor, num_valid_demand_months, name_usr25,
        name_created_by, ts_created, name_modified_by, ts_modified
    FROM SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2;
END
