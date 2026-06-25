-- Source: SupplyChain_Warehouse.bronze.vw_ref_customer_account_group
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_ref_customer_account_group AS
SELECT
    TRIM(CAST(CustomerNumber AS VARCHAR(200)))            AS id_customer,
    UPPER(TRIM(CustomerGroup))                           AS code_customer_group,
    TRIM(CustomerGroupLevel3)                            AS name_customer_group_level3,
    TRIM(BusinessTypeCode)                               AS name_business_type,
    TRIM(usra)                                           AS name_created_by,
    TRY_CAST(dtea AS DATETIME2(6))                       AS ts_created,
    TRIM(usrc)                                           AS name_modified_by,
    TRY_CAST(dtec AS DATETIME2(6))                       AS ts_modified
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
WHERE CustomerNumber IS NOT NULL
