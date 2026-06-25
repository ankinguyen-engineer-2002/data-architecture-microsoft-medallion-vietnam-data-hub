-- ForecastAccuracy_DW_Wrk.v_FactForecastActual
CREATE   VIEW [ForecastAccuracy_DW_Wrk].[v_FactForecastActual] AS
WITH __bob_source AS (
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Actual demand' AS VARCHAR(20)) AS HorizonCode, StatusCode, VersionName, CAST(QtyDemand AS FLOAT) AS Qty,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    HorizonCode, StatusCode, VersionCode, CAST(QtyForecast AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Naive forecast' AS VARCHAR(20)), StatusCode, VersionName, CAST(QtyDemand AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly
)
SELECT
    [ItemSKU] = src.[ItemSKU],
    [WarehouseCode] = src.[WarehouseCode],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [FSCMonthFirst] = src.[FSCMonthFirst],
    [FSCMonthLast] = src.[FSCMonthLast],
    [HorizonCode] = src.[HorizonCode],
    [StatusCode] = src.[StatusCode],
    [VersionName] = src.[VersionName],
    [Qty] = src.[Qty],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
