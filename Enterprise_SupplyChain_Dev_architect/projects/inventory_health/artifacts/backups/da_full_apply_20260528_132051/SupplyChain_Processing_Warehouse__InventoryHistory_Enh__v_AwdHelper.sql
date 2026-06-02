-- ---------------------------------------------------------------------
-- AWD candidate:
--   - Preserves the 2026-05-26 FactBase path.
--   - Uses DA 3 fiscal month forecast horizon and dependent demand roll-up.
--   - Uses SalesHistory_Enh.v_InvoiceDetailLineLevel directly for historical fallback per DA Silver_Check.
-- ---------------------------------------------------------------------
CREATE   VIEW InventoryHistory_Enh.v_AwdHelper AS
WITH current_inventory AS (
    SELECT
        CAST(TRIM(b.ITNBR) AS VARCHAR(50))      AS ItemSku,
        CAST(TRIM(b.HOUSE) AS VARCHAR(50))      AS WarehouseCode,
        CAST(b.MOHTQ AS DECIMAL(18,4))          AS OnHandQty,
        CAST(TRIM(b.ITCLS) AS VARCHAR(50))      AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE) AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
),
asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
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
    SELECT DISTINCT ItemSku, WarehouseCode FROM current_inventory
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
),
fcst_recent AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonthDate,
        ForecastQty
    FROM InventoryHistory_Enh.v_ForecastSnapshotWeeklySat
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
      AND FiscalMonthDate IS NOT NULL
),
latest_snap AS (
    SELECT
        f.ItemSku,
        f.WarehouseCode,
        a.AsOfDate,
        MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a
      ON f.SnapshotDate <= a.AsOfDate
     AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
inventory_source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(NULLIF(TRIM(dinMakeBuyCode), '') AS VARCHAR(10)) AS MakeBuyCode,
        CAST(NULLIF(TRIM(dinSource1), '') AS VARCHAR(50)) AS SourceWarehouseCode,
        ROW_NUMBER() OVER (
            PARTITION BY
                CAST(TRIM(dinItem) AS VARCHAR(50)),
                CAST(TRIM(dinWarehouse) AS VARCHAR(50)),
                CAST(dinSnapshot AS DATE),
                CAST(dinFiscalMonth AS INT)
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotDaily]
    WHERE dinItem IS NOT NULL
      AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> ''
      AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND CAST(dinFiscalMonth AS INT) BETWEEN 190001 AND 209912
      AND CAST(dinFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
      AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
),
inventory_source AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotDate) AS LatestInventorySnapshotDate
    FROM inventory_source_rows isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)
    WHERE (isw.MakeBuyCode IS NOT NULL
       OR isw.SourceWarehouseCode IS NOT NULL)
      AND isw.rn = 1
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
source_map AS (
    SELECT
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate,
        CAST(MAX(NULLIF(TRIM(isw.MakeBuyCode), '')) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(MAX(NULLIF(TRIM(isw.SourceWarehouseCode), '')) AS VARCHAR(50)) AS SourceWarehouseCode
    FROM inventory_source src
    JOIN inventory_source_rows isw
      ON isw.ItemSku = src.ItemSku
     AND isw.WarehouseCode = src.WarehouseCode
     AND isw.SnapshotDate = src.LatestInventorySnapshotDate
     AND isw.rn = 1
    GROUP BY src.ItemSku, src.WarehouseCode, src.AsOfDate
),
forecast_components AS (
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
     AND f.FiscalMonthDate < a.HorizonEndDate
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate

    UNION ALL

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
     AND f.FiscalMonthDate < a.HorizonEndDate
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
        CAST(TRIM(s.ItemSKU) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(s.WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        a.AsOfDate,
        SUM(CAST(s.QtyShipped AS DECIMAL(18,4))) AS Hist13WQty
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel s
    JOIN asof a
      ON s.InvoiceDate > DATEADD(week, -13, a.AsOfDate)
     AND s.InvoiceDate <= a.AsOfDate
    WHERE s.ItemSKU IS NOT NULL
      AND s.WarehouseCode IS NOT NULL
      AND TRIM(s.ItemSKU) <> ''
      AND TRIM(s.WarehouseCode) <> ''
      AND s.InvoiceDate IS NOT NULL
    GROUP BY CAST(TRIM(s.ItemSKU) AS VARCHAR(50)), CAST(TRIM(s.WarehouseCode) AS VARCHAR(50)), a.AsOfDate
)
SELECT
    CAST(iw.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(iw.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(a.AsOfDate AS DATE) AS AsOfDate,
    CAST(a.HorizonStartDate AS DATE) AS HorizonStartDate,
    CAST(a.HorizonEndDate AS DATE) AS HorizonEndDate,
    CAST(a.HorizonDays AS INT) AS HorizonDays,
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
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN d.ThreeMoTotalDemandQty / 13.0
        ELSE ISNULL(h.Hist13WQty, 0) / 13.0
    END AS DECIMAL(18,4)) AS AwdQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN d.ThreeMoTotalDemandQty / NULLIF(a.HorizonDays, 0)
        ELSE ISNULL(h.Hist13WQty, 0) / 91.0
    END AS DECIMAL(18,4)) AS AwdDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
             AND ISNULL(d.ThreeMoDependentDemandQty, 0) > 0 THEN 'Forecast+Dependent'
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN 'Forecast'
        ELSE 'HistoricalFallback'
    END AS VARCHAR(20)) AS AwdSource
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