-- Source: SupplyChain_Warehouse.bronze.vw_brz_saleshistory_afi__invoicedetail
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


    CREATE   VIEW bronze.vw_brz_saleshistory_afi__invoicedetail AS
    SELECT * FROM bronze.brz_saleshistory_afi__invoicedetail_edw
