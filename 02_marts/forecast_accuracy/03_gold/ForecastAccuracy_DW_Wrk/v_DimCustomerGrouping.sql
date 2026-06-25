-- Full _Wrk inline rewrite for SupplyChain_Gold_Warehouse
-- Generated from live base-schema view definitions plus final table column contracts.
-- Execute before dropping legacy base-schema v_* views.

-- SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_DimCustomerGrouping
CREATE   VIEW [ForecastAccuracy_DW_Wrk].[v_DimCustomerGrouping] AS
SELECT DISTINCT CustomerGroupCode, Customer,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.CustomerGrouping
WHERE CustomerGroupCode IS NOT NULL;
