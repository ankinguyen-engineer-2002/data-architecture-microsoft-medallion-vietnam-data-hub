-- ReferenceMaster_Enh_Wrk.v_CustomerAccountGroup
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_CustomerAccountGroup] AS
WITH __bob_source AS (
SELECT TRIM(CustomerNumber) AS Customer, UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode,
    TRIM(CustomerGroupLevel3) AS CustomerGroupLevel3Code, TRIM(BusinessTypeCode) AS BusinessTypeCode
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
)
SELECT
    [Customer] = src.[Customer],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [CustomerGroupLevel3Code] = src.[CustomerGroupLevel3Code],
    [BusinessTypeCode] = src.[BusinessTypeCode],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
