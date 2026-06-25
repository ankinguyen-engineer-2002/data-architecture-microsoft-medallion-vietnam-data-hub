-- Source: SupplyChain_Warehouse.bronze.vw_ref_customer_grouping
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_ref_customer_grouping AS
SELECT DISTINCT
    UPPER(TRIM(CAST(CustomerGroup AS VARCHAR(50)))) AS code_customer_group
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
WHERE CustomerGroup IS NOT NULL
