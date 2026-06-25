-- SupplyChain_Processing_Warehouse.ForecastHistory_Enh_Wrk.v_NaiveForecastMonthly
CREATE   VIEW [ForecastHistory_Enh_Wrk].[v_NaiveForecastMonthly] AS
WITH
mw AS (SELECT FSCMonthFirst, COUNT(DISTINCT FSCWeekFirst) AS NumWeeks FROM ReferenceMaster_Enh.Calendar GROUP BY FSCMonthFirst),
am AS (SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast, SUM(QtyDemand) AS QtyActual FROM SalesHistory_Enh.ActualDemandMonthly GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast),
al AS (SELECT A.*, MW.NumWeeks,
    LAG(A.QtyActual) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS QtyActualPrior,
    LAG(MW.NumWeeks) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS NumWeeksPrior
    FROM am A INNER JOIN mw MW ON MW.FSCMonthFirst=A.FSCMonthFirst),
cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE)),
__bob_source AS (
SELECT L.ItemSKU, L.WarehouseCode, L.CustomerGroupCode, L.FSCMonthFirst, L.FSCMonthLast,
    CAST(L.QtyActualPrior/L.NumWeeksPrior*L.NumWeeks AS INT) AS QtyDemand,
    'Naive Forecast' AS StatusCode, 'Naive Forecast' AS VersionName
FROM al L INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=L.FSCMonthFirst CROSS JOIN cf
WHERE L.QtyActualPrior IS NOT NULL AND L.NumWeeksPrior>0 AND L.WarehouseCode NOT IN ('C','CNW','C35','55')
    AND CAL.FSCMonthYearNum>=(cf.FSCYearNum-3)*100 AND CAL.FSCMonthYearNum<=(cf.FSCYearNum+1)*100+1299
)
SELECT
    [ItemSKU] = src.[ItemSKU],
    [WarehouseCode] = src.[WarehouseCode],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [FSCMonthFirst] = src.[FSCMonthFirst],
    [FSCMonthLast] = src.[FSCMonthLast],
    [QtyDemand] = src.[QtyDemand],
    [StatusCode] = src.[StatusCode],
    [VersionName] = src.[VersionName],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
