-- SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_AwdHelper
CREATE       VIEW [InventoryHistory_Enh_Wrk].[v_AwdHelper] AS
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
     AND RIGHT(TRIM(b.ITCLS), 1) <> 'K' -- FG
),
asof_dates AS (
--    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
--    UNION
   SELECT DISTINCT
       CAST(SnapshotWeekEndingDate AS DATE) AS AsOfDate
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
-- forecast demand
   SELECT
       CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
       CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
       CAST(SnapshotDate AS DATE) AS SnapshotDate,
       CAST(SnapshotDate AS DATE) AS SnapshotDateOrg,
       CAST(FiscalMonthDate AS DATE) AS FiscalMonthDate,
       CAST(ForecastQty AS DECIMAL(18,4)) AS ForecastQty
   FROM InventoryHistory_Enh.ForecastSnapshotWeekly
   WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE)) and SnapshotDate <= '2025-08-04'
     AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
     AND FiscalMonthDate IS NOT NULL

   UNION ALL

   SELECT
       CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
       CAST(Warehouse AS VARCHAR(50)) AS WarehouseCode,
       CAST(CASE
            WHEN DATEDIFF(day, '19000101', CAST(SnapshotDate AS DATE)) % 7 = 0
                THEN DATEADD(day, -2, CAST(SnapshotDate AS DATE))
            ELSE CAST(SnapshotDate AS DATE)
       END AS DATE) AS SnapshotDate,
       CAST(SnapshotDate AS DATE) AS SnapshotDateOrg,
       CAST(FiscalMonthLastDate AS DATE) AS FiscalMonthDate,
       CAST(SUM(TotalForecast) AS DECIMAL(18,4)) AS ForecastQty
   FROM Enterprise_Lakehouse.SupplyChain_Enh.CurFcstSnapshotWeekly
   WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE)) and SnapshotDate > '2025-08-04'
     AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
     AND FiscalMonthLastDate IS NOT NULL
   GROUP BY
    ItemSku,
    Warehouse,
    CASE
        WHEN DATEDIFF(day, '19000101', CAST(SnapshotDate AS DATE)) % 7 = 0
            THEN DATEADD(day, -2, CAST(SnapshotDate AS DATE))
        ELSE CAST(SnapshotDate AS DATE)
    END,
    CAST(SnapshotDate AS DATE),
    FiscalMonthLastDate
),
latest_snap AS (
   SELECT
       f.ItemSku, f.WarehouseCode, a.AsOfDate,
       MAX(f.SnapshotDate) AS LatestSnapshotDate,
       MAX(f.SnapshotDateOrg) AS LatestSnapshotDateOrg
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
       MAX(ls.LatestSnapshotDateOrg) AS ForecastSnapshotDateOrg,
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
       MAX(ls.LatestSnapshotDateOrg) AS ForecastSnapshotDateOrg,
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
       MAX(ForecastSnapshotDateOrg) AS ForecastSnapshotDateOrg,
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
   FROM [SalesHistory_Enh].[InvoiceDetailLineLevel] s
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
   CAST(d.ForecastSnapshotDateOrg AS DATE) AS ForecastSnapshotDateOrg,
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
WHERE COALESCE(d.ThreeMoTotalDemandQty, h.Hist13WQty) IS NOT NULL;

GO
