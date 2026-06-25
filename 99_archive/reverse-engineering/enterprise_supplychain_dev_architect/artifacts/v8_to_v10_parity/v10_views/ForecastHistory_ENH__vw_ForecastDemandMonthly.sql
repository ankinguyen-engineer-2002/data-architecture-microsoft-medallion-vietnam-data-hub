CREATE VIEW ForecastHistory_ENH.vw_ForecastDemandMonthly AS
WITH Raw AS (
    SELECT f.ItemSKU, f.WarehouseCode, UPPER(f.CustomerGroupCode) AS CustomerGroupCode,
        DATEFROMPARTS(CAST(f.FiscalMonth/100 AS INT), CAST(f.FiscalMonth%100 AS INT), 1) AS FiscalMonth,
        CAST(f.SnapshotTS AS DATE) AS Snapshot, f.QtyResultantForecast, f.QtyPromotionalLift
    FROM Staging_WRK.DemandForecastSnapshotDailyEdw AS f
    INNER JOIN ReferenceMaster_ENH.ForecastCycle AS c ON CAST(f.SnapshotTS AS DATE)=c.ForecastSnapshot
),
Calc AS (
    SELECT FC.ItemSKU, FC.WarehouseCode, FC.CustomerGroupCode,
        CAL.FSCMonthFirst, CAL.FSCMonthLast, FC.Snapshot,
        CASE WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=0 THEN 'Lag-0'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=1 THEN 'Lag-1'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=2 THEN 'Lag-2'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=3 THEN 'Lag-3'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=4 THEN 'Lag-4'
             ELSE '>Lag-4' END AS HorizonCode,
        CAST(SUM(FC.QtyResultantForecast+FC.QtyPromotionalLift) AS FLOAT) AS QtyForecast,
        CAST(CONCAT('V ',FORMAT(FC.Snapshot,'yyyy.MM')) AS VARCHAR(20)) AS VersionCode, 'Forecast' AS StatusCode
    FROM Raw AS FC
    INNER JOIN ReferenceMaster_ENH.Calendar AS CAL ON CAL.Date=FC.FiscalMonth
    WHERE FC.FiscalMonth>=DATEADD(MONTH,-36,DATETRUNC(YEAR,DATEADD(MONTH,-6,CAST(GETDATE() AS DATE))))
      AND FC.FiscalMonth<=DATEADD(MONTH,12,DATETRUNC(YEAR,DATEADD(MONTH,6,CAST(GETDATE() AS DATE))))
    GROUP BY FC.ItemSKU, FC.WarehouseCode, FC.CustomerGroupCode, CAL.FSCMonthFirst, CAL.FSCMonthLast, FC.Snapshot, FC.FiscalMonth
)
SELECT CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSKU, CAST(TRIM(WarehouseCode) AS VARCHAR(10)) AS WarehouseCode,
    CAST(TRIM(CustomerGroupCode) AS VARCHAR(50)) AS CustomerGroupCode,
    CAST(FSCMonthFirst AS DATE) AS FSCMonthFirst, CAST(FSCMonthLast AS DATE) AS FSCMonthLast,
    CAST(Snapshot AS DATE) AS Snapshot, CAST(TRIM(HorizonCode) AS VARCHAR(10)) AS HorizonCode,
    CAST(QtyForecast AS FLOAT) AS QtyForecast, CAST(TRIM(VersionCode) AS VARCHAR(20)) AS VersionCode,
    CAST(TRIM(StatusCode) AS VARCHAR(20)) AS StatusCode
FROM Calc