-- Source: SupplyChain_Warehouse.bronze.vw_brz_saleshistory_afi__invoiceheader
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


    CREATE   VIEW bronze.vw_brz_saleshistory_afi__invoiceheader AS
    SELECT * FROM bronze.brz_saleshistory_afi__invoiceheader_edw
