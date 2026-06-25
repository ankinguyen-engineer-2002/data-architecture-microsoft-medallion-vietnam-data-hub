-- SupplyChain_Processing_Warehouse.ReferenceMaster_Enh_Wrk.v_CustomerAccountGroup
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_CustomerAccountGroup] AS
SELECT TRIM(CustomerNumber) AS Customer, UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode,
    TRIM(CustomerGroupLevel3) AS CustomerGroupLevel3Code, TRIM(BusinessTypeCode) AS BusinessTypeCode,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping;
