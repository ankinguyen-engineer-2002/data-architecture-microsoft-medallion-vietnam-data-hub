CREATE VIEW ForecastAccuracy_DW.vw_DimCustomerGrouping AS
SELECT DISTINCT CustomerGroupCode, Customer,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.CustomerGrouping
WHERE CustomerGroupCode IS NOT NULL