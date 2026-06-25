-- Source: SupplyChain_Warehouse.bronze.vw_ref_product
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


    CREATE   VIEW bronze.vw_ref_product AS
    SELECT * FROM bronze.ref_product_edw
