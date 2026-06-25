-- ---- InventoryHistory_Enh.v_ForecastCurrent ---- [DROPPED 2026-05-22]
-- Reason: Tagged orphan in Option B inline refactor 2026-05-21. KPI #7 Forecast
-- Demand Qty served via ForecastSnapshotWeekly (history) + DAX aggregations; the
-- "current overlay" path via SupplyForecast/DemandForecast was scaffolded but never
-- wired into FactInventoryHealthSnapshot or DAX measures.
-- To restore for Phase 2 current overlay: see git history pre-2026-05-22 for full
-- CREATE VIEW sourcing Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.DemandForecast.

GO


-- ============================================================
-- §D. InventoryHistory_Enh — Tier 2 snapshot history (2 views, incremental)
-- ============================================================

CREATE OR ALTER VIEW InventoryHistory_Enh.v_InventorySnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-27:
--   DemandInventorySnapshotWeekly captures Monday snapshots, while Inventory Health needs Saturday snapshots.
--   Use DemandInventorySnapshotDaily and filter to Saturday captures.
--   SnapshotWeekEndingDate is now the actual Saturday capture date.
--   FiscalMonth/FiscalMonthDate describe the inventory forecast period.
--   Grain: (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth).
--   Do not use InventoryHistory_Enh.ItemBalanceHistorical as backup/backfill information.
WITH source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(dinSnapshot AS DATE) AS SnapshotWeekEndingDate,
        CAST(dinFiscalMonth AS INT) AS FiscalMonth,
        CAST(DATEFROMPARTS(CAST(dinFiscalMonth / 100 AS INT), CAST(dinFiscalMonth % 100 AS INT), 1) AS DATE) AS FiscalMonthDate,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(dinIOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
        CAST(dinOrderQuantity AS DECIMAL(18,4)) AS OrderQty,
        CAST(dinBuildQuantity AS DECIMAL(18,4)) AS BuildQty,
        CAST(TRIM(dinMakeBuyCode) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(TRIM(dinSource1) AS VARCHAR(50))  AS SourceWarehouseCode,
        CAST('DemandInventorySnapshotDaily' AS VARCHAR(50)) AS SourceLabel,
        CAST('SupplyChain_Enh_1' AS VARCHAR(64)) AS SourceSystem,
        CAST('DemandInventorySnapshotDaily (Sat dedupe)' AS VARCHAR(128)) AS SourceTable,
        dtec,
        dtea
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotDaily]
    WHERE dinItem IS NOT NULL AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> '' AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND CAST(dinFiscalMonth AS INT) BETWEEN 190001 AND 209912
      AND CAST(dinFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
      AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
), ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM source_rows
)
SELECT
    ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth, FiscalMonthDate, MakeBuyCode, SourceWarehouseCode,
    OnHandQty, SafetyStockTarget, IOSafetyStock, OrderQty, BuildQty,
    SourceLabel, SourceSystem, SourceTable
FROM ranked WHERE rn = 1

GO


CREATE OR ALTER VIEW InventoryHistory_Enh.v_ForecastSnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   SnapshotDate is the capture date; FiscalMonthDate is the forecast period.
--   Weekly reporting uses Saturday captures from the daily staging source.
--   Forecast demand is consumed downstream as next 3 fiscal months, not a single week.
--   Reference: Inventory Health Dataset.sql uses ResultantForecast + PromotionalLift for demand.
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotWeekEndingDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(ISNULL(CAST(dfcResultantForecast AS DECIMAL(18,4)), 0)
           + ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS PromoLiftQty,
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty, --Giang: hiện ko sử dụng
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS DependentForecastQty, --Giang: sai
    CAST('Staging_Wrk'                    AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily'    AS VARCHAR(128)) AS SourceTable
FROM Staging.DemandForecastSnapshotDaily
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND CAST(dfcFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
  AND dfcSnapshot IS NOT NULL
  -- Weekly reporting grain: keep Saturday captures only.
  AND DATEDIFF(day, CAST('19000106' AS DATE), CAST(dfcSnapshot AS DATE)) % 7 = 0
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth

GO


-- ============================================================
-- §E. InventoryHistory_Enh — Tier 3 helpers (4 views, overwrite daily)
--     Grain: (ItemSku, WarehouseCode, AsOfDate)
--     AsOfDate set = InventoryCurrent.SnapshotDate (last 7d) ∪ InventorySnapshotWeekly.SnapshotDate (last 104w)
-- ============================================================

-- ---------------------------------------------------------------------
-- AWD candidate:
--   - Preserves the 2026-05-26 FactBase path.
--   - Uses DA 3 fiscal month forecast horizon and dependent demand roll-up.
--   - Uses SalesHistory_Enh.v_InvoiceDetailLineLevel directly for historical fallback per DA Silver_Check.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_AwdHelper AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   Forecast demand = next 3 fiscal months, not one forecast week.
--   DailyFcstQty = ThreeMoForecastQty / HorizonDays.
--   Dependent demand rolls buy/source-dependent demand to source warehouse via InventorySnapshotWeekly.SourceWarehouseCode.
--   TotalDemandDailyQty = DailyFcstQty + DependentDemandDailyQty.
--   AwdQty is weekly-equivalent demand for existing Gold WeeksOfSupply.
--   AwdDailyQty is daily demand for DaysOfSupply = OnHandQty / AwdDailyQty.
--   If forecast demand is zero or missing, fallback to 13-week shipped demand.
-- 2026-05-20 FIX (Giang #4): three-month forecast uses FiscalMonthDate (forecast period)
-- 2026-05-21 PERF OPTIMIZATION: limit latest_snap lookback to 13 weeks of forecast snapshots.
-- Pre-fix: 153M ForecastSnapshotWeekly × 100+ AsOfDates → huge intermediate JOIN.
-- Post-fix: only join snapshots within 13W of each AsOfDate → ~13× weekly snapshots scanned per AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.InventoryCurrent (dropped entity)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K' -- FG
),
asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE)) -- Giang Historical weekly 3 years
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate,
        DATEDIFF(day,
            DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1),
            DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1))
        ) AS HorizonDays
    FROM asof_dates
),
item_wh AS (
    SELECT DISTINCT ItemSku, WarehouseCode FROM _InventoryCurrent
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
-- Pre-limit ForecastSnapshotWeekly to last 13 weeks of snapshots (weekly cadence → ~13 rows per Item×WH)
fcst_recent AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonthDate,
        ForecastQty
    FROM InventoryHistory_Enh.ForecastSnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
      AND FiscalMonthDate IS NOT NULL
),
latest_snap AS (
    SELECT
        f.ItemSku, f.WarehouseCode, a.AsOfDate,
        MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a
         ON f.SnapshotDate <= a.AsOfDate
        AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)   -- only look back 13W of weekly snapshots
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
inventory_source AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotWeekEndingDate) AS LatestInventorySnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate >= DATEADD(week, -13, a.AsOfDate)
    WHERE isw.MakeBuyCode IS NOT NULL
       OR isw.SourceWarehouseCode IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
source_map AS (
    -- Reference: Inventory Health Dataset.sql #DPD.
    -- Buy/source-dependent demand is identified by MBX='X' and rolled to dinSource1.
    -- Collapse fiscal-month inventory rows to one mapping row per ItemSku + WarehouseCode + AsOfDate.
    -- Assumption: MakeBuyCode and SourceWarehouseCode are stable across the 3 fiscal months in scope.
    SELECT
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate,
        CAST(MAX(NULLIF(TRIM(isw.MakeBuyCode), '')) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(MAX(NULLIF(TRIM(isw.SourceWarehouseCode), '')) AS VARCHAR(50)) AS SourceWarehouseCode
    FROM inventory_source src
    JOIN InventoryHistory_Enh.InventorySnapshotWeekly isw
         ON isw.ItemSku = src.ItemSku
        AND isw.WarehouseCode = src.WarehouseCode
        AND isw.SnapshotWeekEndingDate = src.LatestInventorySnapshotDate
    GROUP BY
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate
),
forecast_components AS (
    -- Direct forecast demand stays at the forecast warehouse.
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        SUM(f.ForecastQty) AS ThreeMoForecastQty,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
         ON f.ItemSku = ls.ItemSku
        AND f.WarehouseCode = ls.WarehouseCode
        AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
         ON a.AsOfDate = ls.AsOfDate
        AND f.FiscalMonthDate >= a.HorizonStartDate
        AND f.FiscalMonthDate <  a.HorizonEndDate
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate

    UNION ALL

    -- Dependent demand rolls from buy/source-dependent warehouse to source warehouse.
    SELECT
        ls.ItemSku,
        CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)) AS WarehouseCode,
        ls.AsOfDate,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoForecastQty,
        SUM(f.ForecastQty) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
         ON f.ItemSku = ls.ItemSku
        AND f.WarehouseCode = ls.WarehouseCode
        AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
         ON a.AsOfDate = ls.AsOfDate
        AND f.FiscalMonthDate >= a.HorizonStartDate
        AND f.FiscalMonthDate <  a.HorizonEndDate
    JOIN source_map sm
         ON sm.ItemSku = f.ItemSku
        AND sm.WarehouseCode = f.WarehouseCode
        AND sm.AsOfDate = ls.AsOfDate
    WHERE TRIM(sm.MakeBuyCode) = 'X'
      AND NULLIF(TRIM(sm.SourceWarehouseCode), '') IS NOT NULL
    GROUP BY ls.ItemSku, CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)), ls.AsOfDate
),
demand_3mo AS (
    SELECT
        ItemSku,
        WarehouseCode,
        AsOfDate,
        SUM(ThreeMoForecastQty) AS ThreeMoForecastQty,
        SUM(ThreeMoDependentDemandQty) AS ThreeMoDependentDemandQty,
        SUM(ThreeMoForecastQty + ThreeMoDependentDemandQty) AS ThreeMoTotalDemandQty
    FROM forecast_components
    WHERE WarehouseCode IS NOT NULL
    GROUP BY ItemSku, WarehouseCode, AsOfDate
),
hist13w AS (
    SELECT
        TRIM(s.ItemSKU)      AS ItemSku,
        TRIM(s.WarehouseCode) AS WarehouseCode,
        a.AsOfDate,
        SUM(CAST(s.QtyShipped AS DECIMAL(18,4))) AS Hist13WQty
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel s
    JOIN asof a
        ON s.InvoiceDate > DATEADD(WEEK, -13, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    WHERE s.ItemSKU IS NOT NULL
      AND s.WarehouseCode IS NOT NULL
      AND TRIM(s.ItemSKU) <> ''
      AND TRIM(s.WarehouseCode) <> ''
      AND s.InvoiceDate IS NOT NULL
    GROUP BY
        TRIM(s.ItemSKU),
        TRIM(s.WarehouseCode),
        a.AsOfDate
)
SELECT
    CAST(iw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(iw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate        AS DATE)          AS AsOfDate,
    CAST(a.HorizonStartDate AS DATE)         AS HorizonStartDate,
    CAST(a.HorizonEndDate   AS DATE)         AS HorizonEndDate,
    CAST(a.HorizonDays      AS INT)          AS HorizonDays,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) AS DECIMAL(18,4)) AS ThreeMoForecastQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoTotalDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS Fwd13WForecastQty,
    CAST(ISNULL(h.Hist13WQty, 0) AS DECIMAL(18,4)) AS Hist13WShippedQty,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DailyFcstQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DependentDemandDailyQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS TotalDemandDailyQty,
    CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4)) AS Hist13WShippedDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / 13.0 AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 13.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
             AND ISNULL(d.ThreeMoDependentDemandQty, 0) > 0 THEN 'Forecast+Dependent'
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN 'Forecast'
        ELSE 'HistoricalFallback'
    END AS VARCHAR(20))                       AS AwdSource
FROM item_wh iw
CROSS JOIN asof a
LEFT JOIN demand_3mo d
       ON d.ItemSku = iw.ItemSku
      AND d.WarehouseCode = iw.WarehouseCode
      AND d.AsOfDate = a.AsOfDate
LEFT JOIN hist13w h
       ON h.ItemSku = iw.ItemSku
      AND h.WarehouseCode = iw.WarehouseCode
      AND h.AsOfDate = a.AsOfDate
WHERE COALESCE(d.ThreeMoTotalDemandQty, h.Hist13WQty) IS NOT NULL

GO

-- ---------------------------------------------------------------------
-- Last invoice: DA as-of behavior + direct Mart A invoice source.
-- ---------------------------------------------------------------------
