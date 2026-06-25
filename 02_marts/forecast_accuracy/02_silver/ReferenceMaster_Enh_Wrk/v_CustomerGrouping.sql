-- SupplyChain_Processing_Warehouse.ReferenceMaster_Enh_Wrk.v_CustomerGrouping
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_CustomerGrouping] AS
SELECT DISTINCT UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode, TRIM(CustomerNumber) AS Customer,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping WHERE CustomerGroup IS NOT NULL;
