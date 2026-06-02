
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
    SELECT DISTINCT SnapshotDate FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
item_wh AS (
    SELECT DISTINCT ItemSku, WarehouseCode FROM _InventoryCurrent
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
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
