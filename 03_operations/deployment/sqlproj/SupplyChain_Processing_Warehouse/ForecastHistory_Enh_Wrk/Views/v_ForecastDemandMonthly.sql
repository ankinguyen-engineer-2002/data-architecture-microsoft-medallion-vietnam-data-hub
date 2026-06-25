-- Full _Wrk inline rewrite for SupplyChain_Processing_Warehouse
-- Generated from live base-schema view definitions plus final table column contracts.
-- Execute before dropping legacy base-schema v_* views.

-- ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
CREATE   VIEW [ForecastHistory_Enh_Wrk].[v_ForecastDemandMonthly] AS
-- 2026-05-19 SWAP: was legacy EDW supplement (SC_LH ver2 to DF2).
-- 2026-05-22 SWAP: was EL.SupplyChain_Enh_1.DemandForecastSnapshotDaily (dirty, row-dup x16 from Q1 2025)
-- Now reads Staging.DemandForecastSnapshotDaily (canonical BOB target; cleaned/deduped via Staging_Wrk.v_DemandForecastSnapshotDaily).
-- Schema mapping: ts_snapshot → dfcSnapshot, code_customer_group → DfcCustomerGroups, etc.
-- Logic unchanged: ForecastCycle JOIN, Lag-N HorizonCode, GROUP BY summed forecast.
WITH Raw AS (
    SELECT 
        f.dfcItem                                            AS ItemSKU,
        f.dfcWarehouse                                       AS WarehouseCode,
        UPPER(f.DfcCustomerGroups)                           AS CustomerGroupCode,
        DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS INT), CAST(f.dfcFiscalMonth%100 AS INT), 1) AS FiscalMonth,
        CAST(f.dfcSnapshot AS DATE)                          AS Snapshot,
        f.dfcResultantForecast                               AS QtyResultantForecast,
        f.dfcPromotionalLift                                 AS QtyPromotionalLift
    FROM Staging.DemandForecastSnapshotDaily AS f
    INNER JOIN ReferenceMaster_Enh.ForecastCycle AS c ON CAST(f.dfcSnapshot AS DATE)=c.ForecastSnapshot
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
    INNER JOIN ReferenceMaster_Enh.Calendar AS CAL ON CAL.Date=FC.FiscalMonth
    WHERE FC.FiscalMonth>=DATEADD(MONTH,-36,DATETRUNC(YEAR,DATEADD(MONTH,-6,CAST(GETDATE() AS DATE))))
      AND FC.FiscalMonth<=DATEADD(MONTH,12,DATETRUNC(YEAR,DATEADD(MONTH,6,CAST(GETDATE() AS DATE))))
    GROUP BY FC.ItemSKU, FC.WarehouseCode, FC.CustomerGroupCode, CAL.FSCMonthFirst, CAL.FSCMonthLast, FC.Snapshot, FC.FiscalMonth
),
__bob_source AS (
SELECT CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSKU, CAST(TRIM(WarehouseCode) AS VARCHAR(10)) AS WarehouseCode,
    CAST(TRIM(CustomerGroupCode) AS VARCHAR(50)) AS CustomerGroupCode,
    CAST(FSCMonthFirst AS DATE) AS FSCMonthFirst, CAST(FSCMonthLast AS DATE) AS FSCMonthLast,
    CAST(Snapshot AS DATE) AS Snapshot, CAST(TRIM(HorizonCode) AS VARCHAR(10)) AS HorizonCode,
    CAST(QtyForecast AS FLOAT) AS QtyForecast, CAST(TRIM(VersionCode) AS VARCHAR(20)) AS VersionCode,
    CAST(TRIM(StatusCode) AS VARCHAR(20)) AS StatusCode
FROM Calc
)
SELECT
    [ItemSKU] = src.[ItemSKU],
    [WarehouseCode] = src.[WarehouseCode],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [FSCMonthFirst] = src.[FSCMonthFirst],
    [FSCMonthLast] = src.[FSCMonthLast],
    [Snapshot] = src.[Snapshot],
    [HorizonCode] = src.[HorizonCode],
    [QtyForecast] = src.[QtyForecast],
    [VersionCode] = src.[VersionCode],
    [StatusCode] = src.[StatusCode],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
