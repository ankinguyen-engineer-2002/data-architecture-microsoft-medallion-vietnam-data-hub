-- ReferenceMaster_Enh_Wrk.v_CustomerGrouping
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_CustomerGrouping] AS
WITH __bob_source AS (
SELECT DISTINCT UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode, TRIM(CustomerNumber) AS Customer
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping WHERE CustomerGroup IS NOT NULL
)
SELECT
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [Customer] = src.[Customer],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
