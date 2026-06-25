CREATE VIEW ForecastAccuracy_DW.vw_FactForecastActual AS
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Actual demand' AS VARCHAR(20)) AS HorizonCode, StatusCode, VersionName, CAST(QtyDemand AS FLOAT) AS Qty,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.SalesHistory_ENH.ActualDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    HorizonCode, StatusCode, VersionCode, CAST(QtyForecast AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.ForecastDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Naive forecast' AS VARCHAR(20)), StatusCode, VersionName, CAST(QtyDemand AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.NaiveForecastMonthly