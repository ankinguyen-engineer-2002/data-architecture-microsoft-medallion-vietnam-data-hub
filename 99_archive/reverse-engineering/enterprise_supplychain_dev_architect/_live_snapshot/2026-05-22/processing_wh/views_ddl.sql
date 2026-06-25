-- Live VIEW dump from SupplyChain_Processing_Warehouse
-- Generated 2026-05-22 via OBJECT_DEFINITION
-- 42 views

-- ============================================================
-- ForecastHistory_Enh.v_ForecastDemandMonthly
-- ============================================================

CREATE   VIEW ForecastHistory_Enh.v_ForecastDemandMonthly AS
-- 2026-05-19 SWAP: was Staging_Wrk.DemandForecastSnapshotDailyEdw (SC_LH ver2 → DF2)
-- 2026-05-22 SWAP: was EL.SupplyChain_Enh_1.DemandForecastSnapshotDaily (dirty, row-dup x16 from Q1 2025)
-- Now reads Staging_Wrk.DemandForecastSnapshotDaily (cross-mart cleaned, deduped via ROW_NUMBER=1).
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
    FROM Staging_Wrk.DemandForecastSnapshotDaily AS f
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
)
SELECT CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSKU, CAST(TRIM(WarehouseCode) AS VARCHAR(10)) AS WarehouseCode,
    CAST(TRIM(CustomerGroupCode) AS VARCHAR(50)) AS CustomerGroupCode,
    CAST(FSCMonthFirst AS DATE) AS FSCMonthFirst, CAST(FSCMonthLast AS DATE) AS FSCMonthLast,
    CAST(Snapshot AS DATE) AS Snapshot, CAST(TRIM(HorizonCode) AS VARCHAR(10)) AS HorizonCode,
    CAST(QtyForecast AS FLOAT) AS QtyForecast, CAST(TRIM(VersionCode) AS VARCHAR(20)) AS VersionCode,
    CAST(TRIM(StatusCode) AS VARCHAR(20)) AS StatusCode
FROM Calc;

GO

-- ============================================================
-- ForecastHistory_Enh.v_NaiveForecastMonthly
-- ============================================================
-- ---- ForecastHistory_Enh.v_NaiveForecastMonthly ----
CREATE VIEW ForecastHistory_Enh.v_NaiveForecastMonthly AS
WITH
mw AS (SELECT FSCMonthFirst, COUNT(DISTINCT FSCWeekFirst) AS NumWeeks FROM ReferenceMaster_Enh.Calendar GROUP BY FSCMonthFirst),
am AS (SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast, SUM(QtyDemand) AS QtyActual FROM SalesHistory_Enh.ActualDemandMonthly GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast),
al AS (SELECT A.*, MW.NumWeeks,
    LAG(A.QtyActual) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS QtyActualPrior,
    LAG(MW.NumWeeks) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS NumWeeksPrior
    FROM am A INNER JOIN mw MW ON MW.FSCMonthFirst=A.FSCMonthFirst),
cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT L.ItemSKU, L.WarehouseCode, L.CustomerGroupCode, L.FSCMonthFirst, L.FSCMonthLast,
    CAST(L.QtyActualPrior/L.NumWeeksPrior*L.NumWeeks AS INT) AS QtyDemand,
    'Naive Forecast' AS StatusCode, 'Naive Forecast' AS VersionName
FROM al L INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=L.FSCMonthFirst CROSS JOIN cf
WHERE L.QtyActualPrior IS NOT NULL AND L.NumWeeksPrior>0 AND L.WarehouseCode NOT IN ('C','CNW','C35','55')
    AND CAL.FSCMonthYearNum>=(cf.FSCYearNum-3)*100 AND CAL.FSCMonthYearNum<=(cf.FSCYearNum+1)*100+1299
GO

-- ============================================================
-- InventoryHistory_Enh.v_AwdHelper
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_AwdHelper AS
-- 2026-05-20 FIX (Giang #4): forward13w uses FiscalMonthDate (forecast period)
-- 2026-05-21 PERF OPTIMIZATION: limit latest_snap lookback to 13 weeks of forecast snapshots.
-- 2026-05-22 SOURCE SWAP: ForecastSnapshotWeekly (Monday-source, DEAD upstream) → ForecastSnapshotWeeklySat (Saturday from Daily, cleaned via Staging dedupe).
-- Post-fix: only join snapshots within 13W of each AsOfDate → ~13× weekly snapshots scanned per AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH _InventoryCurrent AS (
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
asof AS (
    SELECT DISTINCT SnapshotDate AS AsOfDate FROM _InventoryCurrent
    WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
    UNION
    SELECT DISTINCT SnapshotDate FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
item_wh AS (
    SELECT DISTINCT ItemSku, WarehouseCode FROM _InventoryCurrent
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
fcst_recent AS (
    SELECT ItemSku, WarehouseCode, SnapshotDate, FiscalMonthDate, ForecastQty
    FROM InventoryHistory_Enh.ForecastSnapshotWeeklySat
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
),
latest_snap AS (
    SELECT f.ItemSku, f.WarehouseCode, a.AsOfDate, MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a ON f.SnapshotDate <= a.AsOfDate AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
forward13w AS (
    SELECT ls.ItemSku, ls.WarehouseCode, ls.AsOfDate, SUM(f.ForecastQty) AS Fwd13WQty
    FROM latest_snap ls
    JOIN fcst_recent f ON f.ItemSku = ls.ItemSku AND f.WarehouseCode = ls.WarehouseCode
        AND f.SnapshotDate = ls.LatestSnapshotDate
        AND f.FiscalMonthDate >= ls.AsOfDate AND f.FiscalMonthDate < DATEADD(week, 13, ls.AsOfDate)
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate
),
hist13w AS (
    SELECT s.ItemSku, s.WarehouseCode, a.AsOfDate, SUM(s.QuantityShipped) AS Hist13WQty
    FROM InventoryHistory_Enh.SalesShipment s
    JOIN asof a ON s.InvoiceDate > DATEADD(week, -13, a.AsOfDate) AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(iw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(iw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate        AS DATE)          AS AsOfDate,
    CAST(ISNULL(f.Fwd13WQty, 0) AS DECIMAL(18,4)) AS Fwd13WForecastQty,
    CAST(ISNULL(h.Hist13WQty, 0) AS DECIMAL(18,4)) AS Hist13WShippedQty,
    CAST(CASE WHEN ISNULL(f.Fwd13WQty, 0) > 0 THEN CAST(f.Fwd13WQty / 13.0 AS DECIMAL(18,4))
              ELSE CAST(ISNULL(h.Hist13WQty, 0) / 13.0 AS DECIMAL(18,4)) END AS DECIMAL(18,4)) AS AwdQty,
    CAST(CASE WHEN ISNULL(f.Fwd13WQty, 0) > 0 THEN 'Forecast' ELSE 'HistoricalFallback' END AS VARCHAR(20)) AS AwdSource
FROM item_wh iw
CROSS JOIN asof a
LEFT JOIN forward13w f ON f.ItemSku = iw.ItemSku AND f.WarehouseCode = iw.WarehouseCode AND f.AsOfDate = a.AsOfDate
LEFT JOIN hist13w h ON h.ItemSku = iw.ItemSku AND h.WarehouseCode = iw.WarehouseCode AND h.AsOfDate = a.AsOfDate
WHERE COALESCE(f.Fwd13WQty, h.Hist13WQty) IS NOT NULL;

GO

-- ============================================================
-- InventoryHistory_Enh.v_ForecastSnapshotWeekly
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_ForecastSnapshotWeekly AS
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(CAST(dfcResultantForecast AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty,
    CAST('SupplyChain_Enh_1'              AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotWeekly'   AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotWeekly]
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth

GO

-- ============================================================
-- InventoryHistory_Enh.v_ForecastSnapshotWeeklySat
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_ForecastSnapshotWeeklySat AS
-- 2026-05-22: NEW Weekly snapshot from Daily filtered Saturday only.
-- Drop-in replacement for v_ForecastSnapshotWeekly (Monday-source, DEAD upstream since 2024-03-25).
-- Source: Staging_Wrk.DemandForecastSnapshotDaily (cross-mart cleaned, deduped via ROW_NUMBER=1).
-- BRD requirement: 'week ending Saturday' — dfcSnapshot IS the Saturday date.
-- Schema mirrors live v_ForecastSnapshotWeekly (post-Giang fix 2026-05-20):
--   ItemSku, WarehouseCode, SnapshotDate, FiscalMonth, FiscalMonthDate, ForecastQty, PermComptQty, SourceSystem, SourceTable
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth) — same as Weekly.
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(CAST(dfcResultantForecast AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty,
    CAST('Staging_Wrk'                       AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily (Sat)' AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.DemandForecastSnapshotDaily
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND DATENAME(WEEKDAY, dfcSnapshot) = 'Saturday'
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth;

GO

-- ============================================================
-- InventoryHistory_Enh.v_HoldingTransferSnapshotDaily
-- ============================================================
-- ---- InventoryHistory_Enh.v_HoldingTransferSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_HoldingTransferSnapshotDaily AS
WITH _HoldingTransfer AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.HoldingTransfer
    SELECT TransferNumber, ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube, HeaderStatus, CancelFlag, ShipDateKey, DueDateKey
    FROM (
        SELECT
            TRIM(d.DTFRNO)                       AS TransferNumber,
            TRIM(d.DITNBR)                       AS ItemSku,
            TRIM(h.HFHOUS)                       AS WarehouseCode,
            CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
            CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
            TRIM(h.HSTATS)                       AS HeaderStatus,
            TRIM(h.HCANCL)                       AS CancelFlag,
            CAST(h.HSHDTE AS INT)                AS ShipDateKey,
            CAST(h.HDLDTE AS INT)                AS DueDateKey,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
                ORDER BY h.HDLDTE DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
          AND TRIM(h.HCANCL) = 'N'
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)        AS SnapshotDate,
    CAST(TransferNumber                  AS VARCHAR(50)) AS TransferNumber,
    CAST(ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS INT) AS TransferLine,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(TransferQty                     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty                      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TransferCube                    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus                    AS VARCHAR(10))  AS HeaderStatus,
    CAST('Manufacturing_Inventory_AFI'   AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                 AS VARCHAR(128)) AS SourceTable
FROM _HoldingTransfer
GO

-- ============================================================
-- InventoryHistory_Enh.v_InventorySnapshotWeekly
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_InventorySnapshotWeekly AS
-- 2026-05-20 FIX (Giang #1): added FiscalMonth dimension (was missing, could collapse multi-month snapshots)
-- 2026-05-19 REFACTOR: UNION 2 sources for full history coverage
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth) — FiscalMonth NULL for backup source
WITH combined AS (
    -- (A) PRIMARY source — rich schema with FiscalMonth
    SELECT
        TRIM(dinItem)                            AS ItemSku,
        TRIM(dinWarehouse)                       AS WarehouseCode,
        CAST(dinSnapshot AS DATE)                AS SnapshotDate,
        CAST(dinFiscalMonth AS INT)              AS FiscalMonth,
        CAST(DATEFROMPARTS(
            CAST(dinFiscalMonth/100 AS INT),
            CAST(dinFiscalMonth%100 AS INT),
            1) AS DATE)                          AS FiscalMonthDate,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4))    AS SafetyStockTarget,
        CAST(dinIOSafetyStock AS DECIMAL(18,4))  AS IOSafetyStock,
        CAST(dinOrderQuantity AS DECIMAL(18,4))  AS OrderQty,
        CAST(dinBuildQuantity AS DECIMAL(18,4))  AS BuildQty,
        CAST(NULL AS VARCHAR(10))                AS ItemStatus,
        0                                        AS source_rank,
        'DemandInventorySnapshotWeekly'          AS source_label
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotWeekly]
    WHERE dinItem IS NOT NULL AND dinWarehouse IS NOT NULL

    UNION ALL

    -- (B) HISTORICAL backup — NO FiscalMonth concept (NULL fill)
    SELECT
        ItemSku,
        WarehouseCode,
        WeekEndingDate                           AS SnapshotDate,
        CAST(NULL AS INT)                        AS FiscalMonth,
        CAST(NULL AS DATE)                       AS FiscalMonthDate,
        OnHandQty,
        CAST(NULL AS DECIMAL(18,4))              AS SafetyStockTarget,
        CAST(NULL AS DECIMAL(18,4))              AS IOSafetyStock,
        CAST(NULL AS DECIMAL(18,4))              AS OrderQty,
        CAST(NULL AS DECIMAL(18,4))              AS BuildQty,
        ItemStatus,
        1                                        AS source_rank,
        'ItemBalanceHistorical (DF2)'            AS source_label
    FROM InventoryHistory_Enh.ItemBalanceHistorical
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotDate, FiscalMonth
            ORDER BY source_rank ASC
        ) AS rn
    FROM combined
)
SELECT
    CAST(ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(SnapshotDate       AS DATE)          AS SnapshotDate,
    CAST(FiscalMonth        AS INT)           AS FiscalMonth,
    CAST(FiscalMonthDate    AS DATE)          AS FiscalMonthDate,
    CAST(OnHandQty          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockTarget  AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(IOSafetyStock      AS DECIMAL(18,4)) AS IOSafetyStock,
    CAST(OrderQty           AS DECIMAL(18,4)) AS OrderQty,
    CAST(BuildQty           AS DECIMAL(18,4)) AS BuildQty,
    CAST(ItemStatus         AS VARCHAR(10))   AS ItemStatus,
    CAST(source_label       AS VARCHAR(50))   AS SourceLabel,
    CAST('UnionAll'                       AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandInventorySnapshotWeekly + ItemBalanceHistorical' AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO

-- ============================================================
-- InventoryHistory_Enh.v_ItemBalanceHistorical
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_ItemBalanceHistorical AS
-- Source: SC_LH.dbo.itembalance loaded via df_brz_ItemBalance (DF2 workaround pending EL.Inventory_Enh_History.ItemBalance promote)
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate); 107 dups detected → ROW_NUMBER dedupe by latest OnHandQty
-- History: 2021-03-06 → 2026-05-16 (5 years; replaces stale EL.DemandInventorySnapshotWeekly for historical)
-- Future: when Dhivya promotes Enterprise.Inventory_Enh_History.ItemBalance, swap source_objects in registry
WITH ranked AS (
    SELECT
        TRIM(ItemNumber)                  AS ItemSku,
        TRIM(Warehouse)                   AS WarehouseCode,
        CAST(DateWeekEnding AS DATE)      AS WeekEndingDate,
        CAST(OnHandQty AS DECIMAL(18,4))  AS OnHandQty,
        TRIM(ItemStatus)                  AS ItemStatus,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(ItemNumber), TRIM(Warehouse), CAST(DateWeekEnding AS DATE)
            ORDER BY OnHandQty DESC, ItemStatus
        ) AS rn
    FROM [SupplyChain_Lakehouse].[dbo].[itembalance]
    WHERE ItemNumber IS NOT NULL AND Warehouse IS NOT NULL
      AND TRIM(ItemNumber) <> '' AND TRIM(Warehouse) <> ''
)
SELECT
    CAST(ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(WeekEndingDate     AS DATE)          AS WeekEndingDate,
    CAST(OnHandQty          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ItemStatus         AS VARCHAR(10))   AS ItemStatus,
    CAST('SupplyChain_Lakehouse'    AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.itembalance (DF2)'    AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO

-- ============================================================
-- InventoryHistory_Enh.v_LastInvoiceHelper
-- ============================================================
-- ---- InventoryHistory_Enh.v_LastInvoiceHelper ----
-- MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
CREATE   VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.InventoryCurrent (dropped entity)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
asof AS (
    SELECT DISTINCT SnapshotDate AS AsOfDate
    FROM _InventoryCurrent
    WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(s.WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate          AS DATE)          AS AsOfDate,
    CAST(MAX(s.InvoiceDate)  AS DATE)          AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM InventoryHistory_Enh.SalesShipment s
JOIN asof a ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
GO

-- ============================================================
-- InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly
-- ============================================================
-- ---- InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly ----
-- WEEKLY — Saturday only (cron '0 6 * * 6' in registry).
-- Captures latest WeekEndingDate snapshot per (ItemSku, WarehouseCode).
CREATE   VIEW InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly AS
WITH _LogilityItemStatus AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.LogilityItemStatus
    SELECT ItemSku, WarehouseCode, WeekEndingDate, ItemStatus, FutureStatus, StatusChangeDate,
           OnHandQty, SafetyStockQty, ShippableInvQty, MonthsOfSupply, Price,
           ItemClass, Vendor, HoldBuyCode, IsCertified
    FROM (
        SELECT
            TRIM(Item)                            AS ItemSku,
            TRIM(Whse)                            AS WarehouseCode,
            CAST(WeekEnding AS DATE)              AS WeekEndingDate,
            TRIM(ItemStatus)                      AS ItemStatus,
            TRIM(FutureStatus)                    AS FutureStatus,
            CAST(StatusChngDate AS DATE)          AS StatusChangeDate,
            CAST(OnHandQty AS DECIMAL(18,4))      AS OnHandQty,
            CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
            CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
            CAST(MosofSupply AS DECIMAL(18,4))    AS MonthsOfSupply,
            CAST(Price AS DECIMAL(18,4))          AS Price,
            TRIM(ItemClass)                       AS ItemClass,
            TRIM(Vendor)                          AS Vendor,
            TRIM(HoldBuy)                         AS HoldBuyCode,
            CAST(1 AS BIT)                        AS IsCertified,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
                ORDER BY
                    CASE WHEN COALESCE(ShippableInvQty,0) = 0
                          AND COALESCE(FirmDemand,0) = 0 THEN 1 ELSE 0 END ASC,
                    StatusChngDate DESC,
                    COALESCE(OnHandAmt,0) DESC,
                    CAST(FileDate AS DATETIME2) DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandFulfillmentCommonContainer_Logility]
        WHERE Item IS NOT NULL AND Whse IS NOT NULL
          AND TRIM(Item) <> '' AND TRIM(Whse) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(DATEADD(day, (7 - DATEPART(weekday, SYSUTCDATETIME())) % 7,
                 CAST(SYSUTCDATETIME() AS DATE))  AS DATE)         AS WeekEndingDate,
    CAST(ItemSku                                  AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                            AS VARCHAR(50))  AS WarehouseCode,
    CAST(ItemStatus                               AS VARCHAR(20))  AS ItemStatus,
    CAST(FutureStatus                             AS VARCHAR(20))  AS FutureStatus,
    CAST(StatusChangeDate                         AS DATE)         AS StatusChangeDate,
    CAST(IsCertified                              AS BIT)          AS IsCertified,
    CAST('Enterprise_Lakehouse'                   AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility' AS VARCHAR(128)) AS SourceTable
FROM _LogilityItemStatus
WHERE WeekEndingDate = (
    SELECT MAX(WeekEndingDate) FROM _LogilityItemStatus
)
GO

-- ============================================================
-- InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily
-- ============================================================
-- ---- InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily AS
WITH _ManufacturingOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ManufacturingOrder
    SELECT
        CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END              AS DECIMAL(18,4))  AS MOOnOrderQty,
        CAST(ODUDT                        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(MoNumber                        AS VARCHAR(50))  AS MoNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(OrderQty                        AS DECIMAL(18,4)) AS OrderQty,
    CAST(ReceivedQty                     AS DECIMAL(18,4)) AS ReceivedQty,
    CAST(MOOnOrderQty                    AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM _ManufacturingOrder
GO

-- ============================================================
-- InventoryHistory_Enh.v_MovementFlagHelper
-- ============================================================
-- ---- InventoryHistory_Enh.v_MovementFlagHelper ----
-- HasMovementLast17W: SalesShipment as movement signal per BRD §6 (only sales count for SLOB).
CREATE   VIEW InventoryHistory_Enh.v_MovementFlagHelper AS
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
asof AS (
    SELECT DISTINCT SnapshotDate AS AsOfDate
    FROM _InventoryCurrent
    WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
moves AS (
    SELECT
        s.ItemSku, s.WarehouseCode, a.AsOfDate,
        MAX(CASE WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                  AND s.InvoiceDate <= a.AsOfDate
                 THEN 1 ELSE 0 END) AS HasMovementLast17W,
        COUNT(*)                    AS MovementCountLast17W
    FROM InventoryHistory_Enh.SalesShipment s
    JOIN asof a
         ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(ItemSku                AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode          AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate               AS DATE)        AS AsOfDate,
    CAST(HasMovementLast17W     AS BIT)         AS HasMovementLast17W,
    CAST(MovementCountLast17W   AS INT)         AS MovementCountLast17W
FROM moves
GO

-- ============================================================
-- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily
-- ============================================================
-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ---- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily AS
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
          AND TRIM(podwarehouse) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
          AND TRIM(h.pomvendornum) = r.VendorNumber
    WHERE r.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(PoNumber                        AS VARCHAR(50))  AS PoNumber,
    CAST(PoLine                          AS INT)          AS PoLine,
    CAST(VendorNumber                    AS VARCHAR(50))  AS VendorNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(StockQty                        AS DECIMAL(18,4)) AS StockQty,
    CAST(OrderedQty                      AS DECIMAL(18,4)) AS OrderedQty,
    CAST(InTransitQtySource              AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(POOnOrderQty                    AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(POInTransitQty                  AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(TotalOpenPOQty                  AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(EstimatedArrivalDate            AS DATE)         AS EstimatedArrivalDate,
    CAST(EstimatedDepartureDate          AS DATE)         AS EstimatedDepartureDate,
    CAST(SourceSystem                    AS VARCHAR(64))  AS SourceSystem,
    CAST(SourceTable                     AS VARCHAR(128)) AS SourceTable
FROM _PurchaseOrder
GO

-- ============================================================
-- InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical AS
-- Source: SC_LH.dbo.purchaseordersnapshot loaded via df_brz_PurchaseOrderSnapshot (DF2 workaround, 2B rows ⚠️)
-- Grain: (SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode)
-- Phase 2 PO-as-of feature: capture historical PO state by SnapshotDate
-- posDueDt is AS/400 CYYMMDD decimal (e.g., 1230130 = 2023-01-30)
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
          AND TRIM(podwarehouse) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
          AND TRIM(h.pomvendornum) = r.VendorNumber
    WHERE r.rn = 1
)
SELECT
    CAST(posSnapshot AS DATE)                                 AS SnapshotDate,
    CAST(TRIM(posItNbr)             AS VARCHAR(50))           AS ItemSku,
    CAST(TRIM(posWhse)              AS VARCHAR(50))           AS WarehouseCode,
    CAST(TRIM(posVndnr)             AS VARCHAR(50))           AS VendorNumber,
    CAST(posQtyOr                   AS DECIMAL(18,4))         AS OrderedQty,
    CAST(TRIM(posPstts)             AS VARCHAR(10))           AS StatusCode,
    CAST(
        TRY_CAST(
            DATEFROMPARTS(
                1900 + 100 * (TRY_CAST(posDueDt AS INT) / 1000000) + ((TRY_CAST(posDueDt AS INT) % 1000000) / 10000),
                (TRY_CAST(posDueDt AS INT) % 10000) / 100,
                TRY_CAST(posDueDt AS INT) % 100
            ) AS DATE)                                        AS DATE)              AS DueDate,
    CAST(posUUD1PM                  AS DECIMAL(18,4))         AS UnitCost,
    CAST('SupplyChain_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.purchaseordersnapshot (DF2)'        AS VARCHAR(128)) AS SourceTable
FROM [SupplyChain_Lakehouse].[dbo].[purchaseordersnapshot]
WHERE posItNbr IS NOT NULL AND posWhse IS NOT NULL
  AND TRIM(posItNbr) <> '' AND TRIM(posWhse) <> ''

GO

-- ============================================================
-- InventoryHistory_Enh.v_SafetyStockHelper
-- ============================================================

CREATE   VIEW InventoryHistory_Enh.v_SafetyStockHelper AS
-- 2026-05-20 FIX (Giang #6): BRD says '13-week AVERAGE safety stock target', not latest.
-- Replaced ROW_NUMBER picking latest snapshot → AVG() across 13 weekly snapshots prior to AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
asof AS (
    SELECT DISTINCT SnapshotDate AS AsOfDate FROM _InventoryCurrent
    UNION
    SELECT DISTINCT SnapshotDate FROM InventoryHistory_Enh.InventorySnapshotWeekly
)
SELECT
    CAST(isw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(isw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate         AS DATE)          AS AsOfDate,
    CAST(AVG(isw.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COUNT(*)           AS INT)           AS SnapshotCount   -- QA: should be ≤ 13
FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
JOIN asof a
     ON isw.SnapshotDate <= a.AsOfDate
    AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
WHERE isw.SafetyStockTarget IS NOT NULL
GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate

GO

-- ============================================================
-- InventoryHistory_Enh.v_SalesShipment
-- ============================================================
-- ---- InventoryHistory_Enh.v_SalesShipment ----
-- v10 incremental on InvoiceDate (watermark managed by Meta.usp_GenericLoad).
-- View body does NOT filter watermark — GenericLoad appends WHERE InvoiceDate > last_wm at runtime.
CREATE   VIEW InventoryHistory_Enh.v_SalesShipment AS
-- 2026-05-21 (Giang #8): GRAIN = InvoiceNumber + ItemSequence. Different from helpers' Item-WH grain. Helpers use SUM/MAX aggregation downstream which correctly handles the cross-grain.
SELECT
    CAST(InvoiceNumber              AS DECIMAL(18,0)) AS InvoiceNumber,
    CAST(ItemSequence               AS DECIMAL(18,0)) AS ItemSequence,
    CAST(TRIM(ItemSKU)              AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(Warehouse)            AS VARCHAR(50))   AS WarehouseCode,
    CAST(InvoiceDate                AS DATE)          AS InvoiceDate,
    CAST(OrderDate                  AS DATE)          AS OrderDate,
    CAST(QuantityShipped            AS DECIMAL(18,4)) AS QuantityShipped,
    CAST(QuantityOrdered            AS DECIMAL(18,4)) AS QuantityOrdered,
    CAST(Price                      AS DECIMAL(18,4)) AS Price,
    CAST('SalesHistory_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('InvoiceDetail'     AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail]
WHERE ItemSKU IS NOT NULL AND Warehouse IS NOT NULL
  AND TRIM(ItemSKU) <> '' AND TRIM(Warehouse) <> ''
GO

-- ============================================================
-- Meta.v_AccessDecision
-- ============================================================
CREATE VIEW [Meta].[v_AccessDecision] AS

SELECT
    asset_id,
    canonical_layer,
    access_mode,
    physical_item,
    physical_schema,
    physical_object,
    source_contract_status,
    approval_status,
    edw_exit_status,
    CASE
        WHEN access_mode = 'EDWSupplement' THEN 'Use Staging until exit validation and Bob/Rakesh approval pass'
        WHEN access_mode = 'DirectShortcut' THEN 'Read Enterprise_Lakehouse shortcut directly after source contract validation'
        WHEN access_mode = 'WarehouseTransform' THEN 'Run Warehouse-native Domain Silver transform'
        WHEN access_mode = 'GoldPublish' THEN 'Publish physical Gold table for Direct Lake serving'
        ELSE 'Review access policy'
    END AS access_decision
FROM Meta.AssetRegistry
WHERE is_active = 1

GO

-- ============================================================
-- Meta.v_RegistryCompat
-- ============================================================
CREATE VIEW [Meta].[v_RegistryCompat] AS

SELECT
    legacy_sp_name AS sp_name,
    legacy_view_name AS view_name,
    legacy_target_schema AS target_schema,
    legacy_target_table AS target_table,
    legacy_layer AS layer,
    load_type,
    frequency,
    scheduled_hour,
    CAST(NULL AS INT) AS execution_order,
    CAST(NULL AS VARCHAR(128)) AS parallel_group,
    depends_on,
    source_objects,
    watermark_column,
    primary_key,
    is_active,
    last_load_date,
    last_watermark_value,
    next_run_time,
    rows_loaded,
    project,
    date_key,
    date_range_days,
    cron_expression,
    canonical_layer,
    access_mode,
    physical_item,
    physical_schema,
    physical_object,
    approval_status,
    edw_exit_status
FROM Meta.AssetRegistry

GO

-- ============================================================
-- Meta.v_SilverWaveRuntime
-- ============================================================

CREATE VIEW Meta.v_SilverWaveRuntime AS
SELECT
    r.project,
    r.wave_number,
    r.asset_id,
    r.physical_schema AS target_schema,
    r.physical_object AS target_object,
    a.depends_on AS depends_on_asset_ids,
    CASE
        WHEN a.is_active = 1
         AND (a.next_run_time IS NULL OR a.next_run_time <= SYSUTCDATETIME()) THEN 1
        ELSE 0
    END AS is_due,
    CAST('Pending' AS VARCHAR(80)) AS execution_status,
    r.computed_at_utc
FROM Meta.SilverDagWaveRuntime r
JOIN Meta.AssetRegistry a
    ON a.asset_id = r.asset_id;

GO

-- ============================================================
-- Meta.v_sp_registry
-- ============================================================

CREATE VIEW Meta.v_sp_registry AS
SELECT
    r.asset_id AS sp_name,
    r.legacy_view_name AS view_name,
    r.physical_schema AS target_schema,
    r.physical_object AS target_table,
    r.canonical_layer AS layer,
    r.load_type, r.frequency, r.scheduled_hour,
    COALESCE(w.wave_number, CASE WHEN r.canonical_layer='Gold' THEN 5 ELSE 1 END) AS execution_order,
    r.depends_on, r.source_objects, r.watermark_column, r.primary_key,
    r.is_active, r.last_load_date, r.last_watermark_value, r.next_run_time,
    r.rows_loaded, r.project, r.date_key, r.date_range_days, r.cron_expression, r.access_mode
FROM Meta.AssetRegistry r
LEFT JOIN Meta.SilverDagWaveRuntime w ON w.asset_id = r.asset_id

GO

-- ============================================================
-- OpenOrderHistory_Enh.v_OpenOrderLineLevel
-- ============================================================
-- ---- OpenOrderHistory_Enh.v_OpenOrderLineLevel ----
CREATE VIEW OpenOrderHistory_Enh.v_OpenOrderLineLevel AS
SELECT T1.OrderID, T1.ItemSequenceNum, T1.Customer, T1.ShipToCode,
    UPPER(RTRIM(CASE WHEN T1.ShipToCode IS NULL OR TRIM(T1.ShipToCode)='' THEN TRIM(T1.Customer) ELSE CONCAT(TRIM(T1.Customer),'-',TRIM(T1.ShipToCode)) END)) AS AccountShipTo,
    T1.ItemSKU, T1.WarehouseCode,
    CAST(T1.QtyOrdered-T1.QtyShipped AS INT) AS QtyOpenOrder,
    CAST(T1.QtyBackordered AS INT) AS QtyBackorder,
    CAST((T1.AmtExtendedSelling/CASE WHEN T1.QtyBackordered>0 THEN T1.QtyBackordered WHEN T1.QtyOrdered>0 THEN T1.QtyOrdered ELSE 1 END - COALESCE(T2.AmtFreight,0))
        *CASE WHEN T1.QtyBackordered>0 THEN T1.QtyBackordered WHEN T1.QtyOrdered>0 THEN T1.QtyOrdered ELSE 1 END AS DECIMAL(13,2)) AS AmtOpenOrder,
    CAST(CASE WHEN T1.QtyBackordered>0 THEN (T1.AmtExtendedSelling/T1.QtyBackordered-COALESCE(T2.AmtFreight,0))*T1.QtyBackordered ELSE 0 END AS DECIMAL(13,2)) AS AmtBackorder,
    T3.OrderDate AS OrderTaken, T2.PromiseDate AS OriginalPromise, T1.RequestedDate AS CurrentPromise,
    T4.FreezeDate AS OriginalRequest, T4.RequestedShipDate AS CurrentRequest, T1.ManufacturedDate AS CurrentLoad,
    T4.OrderArrangementCode AS OrderArrivalCode, T1.AllocationFlagCode, T1.LoadDateChanges AS LoadDateChangesNum,
    T3.LeadTimeDays AS LeadTimeDaysNum, T3.ShippingInstructionsName,
    CASE WHEN T1.ItemDescriptionShortName=T1.ItemDescriptionName THEN '' ELSE T1.ItemDescriptionShortName END AS CustomerSKUName,
    COALESCE(T2.AmtFreight,0) AS AmtOrderFreight,
    CASE WHEN DATEADD(DAY,7,T4.RequestedShipDate)<CAST(GETDATE() AS DATE) THEN 'Past Due' ELSE 'Future Ord' END AS PastDueFlagCode
FROM Staging_Wrk.v_Codatan AS T1
LEFT JOIN Staging_Wrk.v_Extorit AS T2 ON T1.OrderID=T2.OrderID AND T1.ItemSequenceNum=T2.ItemSequenceNum
INNER JOIN Staging_Wrk.v_Comast AS T3 ON T1.OrderID=T3.OrderID
INNER JOIN Staging_Wrk.v_Extord AS T4 ON T1.OrderID=T4.OrderID
WHERE (T1.QtyBackordered<>0 OR T1.QtyOrdered<>0) AND T1.AmtSellingPrice<>0 AND T3.RecordTypeCode<>'X' AND T1.QtyOrdered>=0
GO

-- ============================================================
-- OpenOrderHistory_Enh.v_OpenOrderMonthly
-- ============================================================
-- ---- OpenOrderHistory_Enh.v_OpenOrderMonthly ----

CREATE VIEW OpenOrderHistory_Enh.v_OpenOrderMonthly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode) AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder) AS QtyOpenOrder, SUM(OO.QtyBackorder) AS QtyBackorder,
    SUM(OO.AmtOpenOrder) AS AmtOpenOrder, SUM(OO.AmtBackorder) AS AmtBackorder,
    COUNT(*) AS OrderLines, COUNT(DISTINCT OO.OrderID) AS DistinctOrders,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.QtyOpenOrder ELSE 0 END) AS QtyPastDue,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.AmtOpenOrder ELSE 0 END) AS AmtPastDue
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=OO.CurrentRequest
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode), CAL.FSCMonthFirst, CAL.FSCMonthLast
GO

-- ============================================================
-- ReferenceMaster_Enh.v_Calendar
-- ============================================================
-- ---- ReferenceMaster_Enh.v_Calendar ----
CREATE   VIEW ReferenceMaster_Enh.v_Calendar AS
SELECT
    -- Keys (existing)
    CAST(DateKey AS INT)                          AS SKDate,
    CAST(MapicsDate AS INT)                       AS MapicsDate,
    CAST(DateID AS DATE)                          AS Date,
    CAST(DateTimeID AS DATE)                      AS Datetime,
    CAST(CalendarDate AS DATE)                    AS Calendar,

    -- Calendar Day (existing + 1 NEW)
    TRIM(CalendarDateName)                        AS CalendarDateName,
    CAST(CalendarDateIndicator AS INT)            AS CalDateIndicatorNum,        -- NEW
    CAST(CalendarDayOfWeek AS INT)                AS CalDayOfWeekNum,
    TRIM(CalendarDayOfWeekName)                   AS CalDayOfWeekName,
    CAST(CalendarDayOfMonth AS INT)               AS CalDayOfMonthNum,
    CAST(CalendarDayOfYear AS INT)                AS CalDayOfYearNum,

    -- Calendar Week (existing + 2 NEW)
    CAST(CalendarWeek AS INT)                     AS CalWeekNum,
    CAST(CalendarWeekIndicator AS INT)            AS CalWeekIndicatorNum,        -- NEW
    CAST(CalendarWeekYear AS INT)                 AS CalWeekYearNum,
    TRIM(CalendarWeekYearName)                    AS CalWeekYearName,
    CAST(CalendarWeekFirstDate AS DATE)           AS CalWeekFirst,
    CAST(CalendarWeekLastDate AS DATE)            AS CalWeekLast,
    CAST(CalendarWeekOfMonth AS INT)              AS CalWeekOfMonthNum,          -- NEW

    -- Calendar Month (existing + 1 NEW)
    CAST(CalendarMonth AS INT)                    AS CalMonthNum,
    CAST(CalendarMonthIndicator AS INT)           AS CalMonthIndicatorNum,       -- NEW
    CAST(CalendarMonthYear AS INT)                AS CalMonthYearNum,
    TRIM(CalendarMonthName)                       AS CalMonthName,
    TRIM(CalendarMonthYearName)                   AS CalMonthYearName,
    CAST(CalendarMonthFirstDate AS DATE)          AS CalMonthFirst,
    CAST(CalendarMonthLastDate AS DATE)           AS CalMonthLast,

    -- Calendar Quarter (existing + 3 NEW)
    CAST(CalendarQuarter AS INT)                  AS CalQuarterNum,
    TRIM(CalendarQuarterName)                     AS CalQuarterName,
    CAST(CalendarQuarterIndicator AS INT)         AS CalQuarterIndicatorNum,     -- NEW
    CAST(CalendarQuarterYear AS INT)              AS CalQuarterYearNum,          -- NEW
    TRIM(CalendarQuarterYearName)                 AS CalQuarterYearName,         -- NEW

    -- Calendar Semester + Year (3 NEW)
    CAST(CalendarSemester AS INT)                 AS CalSemesterNum,             -- NEW
    CAST(CalendarSemesterYear AS INT)             AS CalSemesterYearNum,         -- NEW
    CAST(CalendarYear AS INT)                     AS CalYearNum,
    TRIM(CalendarYearName)                        AS CalYearName,
    CAST(CalendarYearIndicator AS INT)            AS CalYearIndicatorNum,        -- NEW

    -- Fiscal Day (7 NEW)
    CAST(FiscalDate AS DATE)                      AS FiscalDate,                 -- NEW
    TRIM(FiscalDateName)                          AS FiscalDateName,             -- NEW
    CAST(FiscalDateIndicator AS INT)              AS FSCDateIndicatorNum,        -- NEW
    CAST(FiscalDayOfWeek AS INT)                  AS FSCDayOfWeekNum,            -- NEW
    TRIM(FiscalDayOfWeekName)                     AS FSCDayOfWeekName,           -- NEW
    CAST(FiscalDayOfMonth AS INT)                 AS FSCDayOfMonthNum,           -- NEW
    CAST(FiscalDayOfYear AS INT)                  AS FSCDayOfYearNum,            -- NEW

    -- Fiscal Week (existing + 3 NEW)
    CAST(FiscalWeek AS INT)                       AS FSCWeekNum,
    CAST(FiscalWeekIndicator AS INT)              AS FSCWeekIndicatorNum,        -- NEW
    CAST(FiscalWeekYear AS INT)                   AS FSCWeekYearNum,
    TRIM(FiscalWeekYearName)                      AS FSCWeekYearName,            -- NEW
    CAST(FiscalWeekFirstDate AS DATE)             AS FSCWeekFirst,
    CAST(FiscalWeekLastDate AS DATE)              AS FSCWeekLast,
    CAST(FiscalWeekOfMonth AS INT)                AS FSCWeekOfMonthNum,          -- NEW

    -- Fiscal Month (existing + 1 NEW)
    CAST(FiscalMonth AS INT)                      AS FSCMonthNum,
    CAST(FiscalMonthIndicator AS INT)             AS FSCMonthIndicatorNum,       -- NEW
    CAST(FiscalMonthYear AS INT)                  AS FSCMonthYearNum,
    TRIM(FiscalMonthName)                         AS FSCMonthName,
    TRIM(FiscalMonthYearName)                     AS FSCMonthYearName,
    CAST(FiscalMonthFirstDate AS DATE)            AS FSCMonthFirst,
    CAST(FiscalMonthLastDate AS DATE)             AS FSCMonthLast,

    -- Fiscal Quarter (existing + 3 NEW: indicator + first/last via window function)
    CAST(FiscalQuarter AS INT)                    AS FSCQuarterNum,
    TRIM(FiscalQuarterName)                       AS FSCQuarterName,
    CAST(FiscalQuarterIndicator AS INT)           AS FSCQuarterIndicatorNum,     -- NEW
    CAST(FiscalQuarterYear AS INT)                AS FSCQuarterYearNum,
    TRIM(FiscalQuarterYearName)                   AS FSCQuarterYearName,
    MIN(CAST(FiscalMonthFirstDate AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterFirst,            -- NEW
    MAX(CAST(FiscalMonthLastDate  AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterLast,             -- NEW

    -- Fiscal Semester + Year (5 NEW)
    CAST(FiscalSemester AS INT)                   AS FSCSemesterNum,             -- NEW
    CAST(FiscalSemesterYear AS INT)               AS FSCSemesterYearNum,         -- NEW
    CAST(FiscalYear AS INT)                       AS FSCYearNum,
    TRIM(FiscalYearName)                          AS FSCYearName,
    CAST(FiscalYearIndicator AS INT)              AS FSCYearIndicatorNum,        -- NEW
    CAST(FiscalYearFirstDate AS DATE)             AS FSCYearFirst,               -- NEW
    CAST(FiscalYearLastDate AS DATE)              AS FSCYearLast,                -- NEW

    -- Holiday + Working Day (existing)
    TRIM(HolidayIndicator)                        AS HolidayIndicatorCode,
    TRIM(HolidayName)                             AS HolidayName,
    TRIM(WorkingDayIndicator)                     AS WorkingDayCode,
    TRIM(WeekdayWeekend)                          AS WeekdayWeekendCode

FROM Enterprise_Lakehouse.MasterData_DW.DimDate
WHERE DateKey IS NOT NULL;
GO

-- ============================================================
-- ReferenceMaster_Enh.v_CustomerAccount
-- ============================================================
-- ---- ReferenceMaster_Enh.v_CustomerAccount ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerAccount AS SELECT * FROM Enterprise_Lakehouse.Customers.AccountMaster
GO

-- ============================================================
-- ReferenceMaster_Enh.v_CustomerAccountGroup
-- ============================================================
-- ---- ReferenceMaster_Enh.v_CustomerAccountGroup ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerAccountGroup AS
SELECT TRIM(CustomerNumber) AS Customer, UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode,
    TRIM(CustomerGroupLevel3) AS CustomerGroupLevel3Code, TRIM(BusinessTypeCode) AS BusinessTypeCode
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
GO

-- ============================================================
-- ReferenceMaster_Enh.v_CustomerGrouping
-- ============================================================
-- ---- ReferenceMaster_Enh.v_CustomerGrouping ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerGrouping AS
SELECT DISTINCT UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode, TRIM(CustomerNumber) AS Customer
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping WHERE CustomerGroup IS NOT NULL
GO

-- ============================================================
-- ReferenceMaster_Enh.v_CustomerShippingLocation
-- ============================================================
-- ---- ReferenceMaster_Enh.v_CustomerShippingLocation ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerShippingLocation AS SELECT * FROM Enterprise_Lakehouse.Customers.ShippingLocations
GO

-- ============================================================
-- ReferenceMaster_Enh.v_ForecastCycle
-- ============================================================
-- ---- ReferenceMaster_Enh.v_ForecastCycle ----
CREATE VIEW ReferenceMaster_Enh.v_ForecastCycle AS SELECT * FROM SupplyChain_Lakehouse.dbo.ref_forecast_cycle
GO

-- ============================================================
-- ReferenceMaster_Enh.v_ForecastHorizon
-- ============================================================
-- ---- ReferenceMaster_Enh.v_ForecastHorizon ----

CREATE   VIEW ReferenceMaster_Enh.v_ForecastHorizon AS
SELECT 'Lag-0'          AS HorizonCode, 1 AS [Rank] UNION ALL
SELECT 'Lag-1',          2 UNION ALL
SELECT 'Lag-2',          3 UNION ALL
SELECT 'Lag-3',          4 UNION ALL
SELECT 'Lag-4',          5 UNION ALL
SELECT '>Lag-4',         6 UNION ALL
SELECT 'Actual demand',  7 UNION ALL
SELECT 'Naive forecast', 8
GO

-- ============================================================
-- ReferenceMaster_Enh.v_ItemMaster
-- ============================================================
-- ---- ReferenceMaster_Enh.v_ItemMaster ----
CREATE VIEW ReferenceMaster_Enh.v_ItemMaster AS SELECT * FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster
GO

-- ============================================================
-- ReferenceMaster_Enh.v_OrderType
-- ============================================================
-- ---- ReferenceMaster_Enh.v_OrderType ----
CREATE VIEW ReferenceMaster_Enh.v_OrderType AS SELECT * FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP
GO

-- ============================================================
-- ReferenceMaster_Enh.v_Vendor
-- ============================================================
-- ============================================================
-- Silver Views — InventoryHealth Project (project='inventory_health')
-- ============================================================
-- Layer: Silver. Pattern: 1 generic SP (Meta.usp_GenericLoad) + N views.
--   Each view encapsulates business logic from the deliverable v1 procs.
--   Meta.usp_GenericLoad reads Meta.AssetRegistry to know:
--     - load_type (overwrite | incremental | datekey | upsert | ...)
--     - watermark_column / primary_key / date_key (incremental/datekey/upsert)
--     - last_watermark_value (for incremental)
--   At CTAS time: SELECT * FROM <view> + auto-inject LoadDT column.
-- Source (target WH): SupplyChain_Processing_Warehouse (c0262cef-...)
-- Target schemas: InventoryHistory_Enh (NEW) + ReferenceMaster_Enh (extend with Vendor only)
-- Reuse (do NOT recreate): ReferenceMaster_Enh.ItemMaster, ReferenceMaster_Enh.Warehouse, ReferenceMaster_Enh.Calendar
-- ============================================================
-- Track A fixes preserved (deliverable v1, 2026-05-17):
--   H1 ItemAllocationFlag=2 (Robert sign-off pending)
--   H2 ATPSUM UNPIVOT APAT01-43 only (data-shape fix)
--   H3 FG-only + WH exclusion (matches sếp's PurchaseOrderSnapshot)
--   H4 ORDER BY FiscalMonthYear (math fix, applied in gold_views)
--   H5 WeekFourFlag exact week (applied in gold_views, Robert sign-off pending)
--   M1 Saturday detection via DATENAME — N/A (handled by Meta.usp_GenericLoad cron)
--   M3 Cogs52W → Cogs52M rename (applied in gold_views, Robert sign-off pending)
--   M4 SLOB NULL guard (applied in gold_views)
--   M5 AWD COUNTROWS SUMMARIZE (applied in DAX)
--   B1 PoDetail source switched Enterprise.PoDetail (preserved below)
--   B2 ForecastCurrent reads DemandForecast (preserved below)
--   B3 Warehouse exclusion flag columns (preserved in v_WarehouseExt + v_InventoryCurrent + v_PurchaseOrder)
-- ============================================================


-- ============================================================
-- §A. ReferenceMaster_Enh — NEW Vendor view (1 NEW)
--     ItemMaster + Warehouse already exist; only Vendor is NEW.
-- ============================================================

-- ---- ReferenceMaster_Enh.v_Vendor (NEW for inventory_health) ----
-- Source: Enterprise_Lakehouse.Purchasing_AFI.VendorMaster (51 cols, 86,598 rows)
CREATE VIEW ReferenceMaster_Enh.v_Vendor AS
SELECT
    CAST(TRIM(v.VendorNumber) AS VARCHAR(50))           AS VendorNumber,
    CAST(v.VendorName         AS VARCHAR(200))          AS VendorName,
    CAST('Purchasing_AFI'     AS VARCHAR(64))           AS SourceSystem,
    CAST('VendorMaster'       AS VARCHAR(128))          AS SourceTable
FROM [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
WHERE v.VendorNumber IS NOT NULL AND TRIM(v.VendorNumber) <> ''
GO

-- ============================================================
-- ReferenceMaster_Enh.v_Warehouse
-- ============================================================

CREATE   VIEW ReferenceMaster_Enh.v_Warehouse AS 
SELECT 
    AFIWarehousesKey,
    RTRIM(WarehouseCode) AS WarehouseCode,
    IntransitWarehouse,
    ContainerDirectWarehouse,
    ControlledWarehouse,
    WarehouseLocation,
    WarehouseOrderGroup,
    FinanceInventoryReportFlag
FROM Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses;

GO

-- ============================================================
-- SalesHistory_Enh.v_ActualDemandMonthly
-- ============================================================
-- ---- SalesHistory_Enh.v_ActualDemandMonthly ----
CREATE VIEW SalesHistory_Enh.v_ActualDemandMonthly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCMonthFirst, CAL.FSCMonthLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCMonthFirst, CAL.FSCMonthLast
GO

-- ============================================================
-- SalesHistory_Enh.v_ActualDemandWeekly
-- ============================================================
-- ---- SalesHistory_Enh.v_ActualDemandWeekly ----
CREATE VIEW SalesHistory_Enh.v_ActualDemandWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
GO

-- ============================================================
-- SalesHistory_Enh.v_InvoiceDetailLineLevel
-- ============================================================

CREATE   VIEW SalesHistory_Enh.v_InvoiceDetailLineLevel AS
-- 2026-05-19 SWAP: was Staging_Wrk.InvoiceDetailEdw + InvoiceHeaderEdw (SC_LH ver2 → DF2)
-- Now reads EL.SalesHistory_AFI.InvoiceDetail + InvoiceHeader directly (ADR-002 EDW Exit)
-- Column rename: Edw aliases → EL native (InvoiceID→InvoiceNumber, etc.)
SELECT 
    INV.InvoiceNumber                                AS InvoiceID,
    INV.ExtendedInvoiceNumber                        AS InvoiceExtended,
    INV.OrderNumber                                  AS OrderID,
    INV.ItemSequence                                 AS ItemSequenceNum,
    INV.CustomerNumber                               AS Customer,
    INV.ShiptoNumber                                 AS ShipToCode,
    UPPER(RTRIM(CASE WHEN INV.ShiptoNumber IS NULL OR TRIM(INV.ShiptoNumber)='' THEN TRIM(INV.CustomerNumber) ELSE CONCAT(TRIM(INV.CustomerNumber),'-',TRIM(INV.ShiptoNumber)) END)) AS AccountShipTo,
    INV.ItemSKU,
    INV.Warehouse                                    AS WarehouseCode,
    UPPER(CG.CustomerGroupCode)                      AS CustomerGroupCode,
    IH.LeadTime                                      AS LeadTimeDaysNum,
    INV.QuantityShipped                              AS QtyShipped,
    INV.QuantityOrdered                              AS QtyOrdered,
    INV.QuantityBackOrdered                          AS QtyBackordered,
    INV.InvoiceAmount                                AS AmtInvoice,
    INV.NetSales                                     AS AmtNetSales,
    INV.Price                                        AS AmtPrice,
    INV.StandardPrice                                AS AmtStandardPrice,
    INV.ContractPrice                                AS AmtContractPrice,
    INV.Discount                                     AS AmtDiscount,
    INV.PriceAdjustment                              AS AmtPriceAdjustment,
    INV.Freight                                      AS AmtFreight,
    INV.InvoiceDate,
    INV.OrderDate,
    INV.RequestDate                                  AS Request,
    INV.CurrentRequestDate                           AS CurrentRequest,
    INV.CurrentPromiseDate                           AS CurrentPromise,
    INV.OriginalRequestDate                          AS OriginalRequest,
    INV.OriginalPromiseDate                          AS OriginalPromise,
    INV.PromisedDelivery,
    INV.DeliveryDate                                 AS Delivery,
    INV.ActualDelivery,
    INV.OrderType                                    AS OrderTypeCode,
    INV.OrderType3                                   AS OrderType3Code,
    INV.CreditCode,
    INV.ItemClass                                    AS ItemClassCode,
    INV.OrderItemStatus                              AS OrderItemStatusCode
FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail] AS INV
LEFT JOIN [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceHeader] AS IH
       ON INV.InvoiceNumber=IH.InvoiceNumber AND INV.InvoiceDate=IH.InvoiceDate AND INV.OrderDate=IH.OrderDate AND INV.OrderNumber=IH.OrderNumber
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup AS CG ON CG.Customer=INV.CustomerNumber

GO

-- ============================================================
-- SalesHistory_Enh.v_InvoiceWeekly
-- ============================================================
-- ---- SalesHistory_Enh.v_InvoiceWeekly ----
CREATE VIEW SalesHistory_Enh.v_InvoiceWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyShipped, SUM(INV.AmtNetSales) AS AmtNetSales,
    SUM(INV.AmtInvoice) AS AmtInvoice, SUM(INV.AmtFreight) AS AmtFreight,
    COUNT(*) AS InvoiceLines, COUNT(DISTINCT INV.InvoiceID) AS DistinctInvoices
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=INV.InvoiceDate
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum>=cf.FSCYearNum-3
GROUP BY INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode, CAL.FSCWeekFirst, CAL.FSCWeekLast
GO

-- ============================================================
-- Staging_Wrk.v_Codatan
-- ============================================================
-- 04_create_renamed_views_processing.sql
-- 28 Processing views recreated with new schema (_Enh/_Wrk) and v_ prefix.
-- Source: etl/staging_ddl.sql + etl/silver_views.sql, transformed.

-- ============== Staging views ==============
-- ============================================================
-- Staging_Wrk Views — Raw EDW Projection
-- ============================================================
-- Layer: Staging. Pattern: TRIM strings, TRY_CONVERT dates, PascalCase aliases. No JOIN.
-- Source: SupplyChain_Processing_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- Staging_Wrk.v_Codatan ----
CREATE VIEW Staging_Wrk.v_Codatan AS
SELECT
    TRIM(ORDNO) AS OrderID, TRIM(ITNBR) AS ItemSKU, TRIM(HOUSE) AS WarehouseCode,
    CAST(ITMSQ AS INT) AS ItemSequenceNum,
    CAST(COQTY AS DECIMAL(12,3)) AS QtyOrdered, CAST(QTYSH AS DECIMAL(12,3)) AS QtyShipped,
    CAST(QTYBO AS DECIMAL(12,3)) AS QtyBackordered,
    CAST(INSAM AS DECIMAL(12,2)) AS AmtExtendedSelling,
    CAST(PRICE AS DECIMAL(12,4)) AS AmtSellingPrice,
    TRY_CONVERT(DATE, CAST(CAST(RQIDT AS BIGINT) AS VARCHAR(20))) AS RequestedDate,
    TRY_CONVERT(DATE, CAST(CAST(MFIDT AS BIGINT) AS VARCHAR(20))) AS ManufacturedDate,
    TRIM(CCUSNO) AS Customer, TRIM(CSHPNO) AS ShipToCode,
    TRIM(ITDSC) AS ItemDescriptionName, TRIM(ITDSI) AS ItemDescriptionShortName,
    CAST(IAFLG AS VARCHAR(200)) AS AllocationFlagCode,
    CAST(NUMLDDTCHG AS INT) AS LoadDateChanges
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan WHERE ORDNO IS NOT NULL
GO

-- ============================================================
-- Staging_Wrk.v_Comast
-- ============================================================
-- ---- Staging_Wrk.v_Comast ----
CREATE VIEW Staging_Wrk.v_Comast AS
SELECT TRIM(ORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(ORDTE AS BIGINT) AS VARCHAR(20))) AS OrderDate,
    CAST(SHLTC AS INT) AS LeadTimeDays, TRIM(SHINS) AS ShippingInstructionsName,
    TRIM(ACREC) AS RecordTypeCode
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST
GO

-- ============================================================
-- Staging_Wrk.v_DemandForecastSnapshotDaily
-- ============================================================

CREATE VIEW Staging_Wrk.v_DemandForecastSnapshotDaily AS
-- ============================================================
-- Cross-mart cleaned Bronze materialization (2026-05-22).
-- Source: EL.SupplyChain_Enh_1.DemandForecastSnapshotDaily (5.9B rows, dirty with row-dup x16 from Q1 2025)
-- Transform: ROW_NUMBER() OVER (full grain) = 1 dedupe.
-- Consumers: Mart A (ForecastHistory_Enh.v_ForecastDemandMonthly) + Mart B (InventoryHistory_Enh.v_ForecastSnapshotWeeklySat NEW)
-- Idempotent: if DE US fixes upstream dup, this dedupe becomes no-op (no harm).
-- ============================================================
WITH dedupe AS (
  SELECT 
    dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
    dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
    dfcValidDemandMonths, dfcSnapshot,
    dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
    dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
    dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups,
    ROW_NUMBER() OVER (
      PARTITION BY dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot,
                   DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode
      ORDER BY (SELECT NULL)
    ) AS _rn
  FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotDaily]
)
SELECT 
  dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
  dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
  dfcValidDemandMonths, dfcSnapshot,
  dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
  dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
  dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups,
  CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM dedupe
WHERE _rn = 1;

GO

-- ============================================================
-- Staging_Wrk.v_Extord
-- ============================================================
-- ---- Staging_Wrk.v_Extord ----
CREATE VIEW Staging_Wrk.v_Extord AS
SELECT TRIM(XORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(FRZDAT AS BIGINT) AS VARCHAR(20))) AS FreezeDate,
    TRY_CONVERT(DATE, CAST(CAST(RQSDAT AS BIGINT) AS VARCHAR(20))) AS RequestedShipDate,
    TRIM(ORDARR) AS OrderArrangementCode,
    TRIM(OTTYP1) AS OrderType1Code, TRIM(OTTYP2) AS OrderType2Code,
    TRIM(OTTYP3) AS OrderType3Code, TRIM(OTTYP4) AS OrderType4Code
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD
GO

-- ============================================================
-- Staging_Wrk.v_Extorit
-- ============================================================
-- ---- Staging_Wrk.v_Extorit ----
CREATE VIEW Staging_Wrk.v_Extorit AS
SELECT TRIM(IORD) AS OrderID, CAST(ISEQ AS INT) AS ItemSequenceNum,
    CAST(IFRGHT AS DECIMAL(12,2)) AS AmtFreight,
    TRY_CONVERT(DATE, CAST(CAST(IPRMDT AS BIGINT) AS VARCHAR(20))) AS PromiseDate
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT
GO

