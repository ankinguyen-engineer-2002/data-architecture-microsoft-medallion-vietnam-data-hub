-- Source: SupplyChain_Warehouse.bronze.vw_brz_supplychain_enh_1__demandforecastsnapshotdaily
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


    CREATE   VIEW bronze.vw_brz_supplychain_enh_1__demandforecastsnapshotdaily AS
    SELECT * FROM bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw
