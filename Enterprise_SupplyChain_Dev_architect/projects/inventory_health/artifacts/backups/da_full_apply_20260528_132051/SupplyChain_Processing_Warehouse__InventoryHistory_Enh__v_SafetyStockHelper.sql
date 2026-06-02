-- ---------------------------------------------------------------------
-- Safety stock candidate: next 3 fiscal months, fallback prior 13 weeks.
-- ---------------------------------------------------------------------
CREATE   VIEW InventoryHistory_Enh.v_SafetyStockHelper AS
WITH asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate
    FROM asof_dates
),
latest_snap AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotDate) AS LatestSnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
fiscal_ss AS (
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM latest_snap ls
    JOIN asof a
      ON a.AsOfDate = ls.AsOfDate
    JOIN InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
      ON isw.ItemSku = ls.ItemSku
     AND isw.WarehouseCode = ls.WarehouseCode
     AND isw.SnapshotDate = ls.LatestSnapshotDate
     AND isw.FiscalMonthDate >= a.HorizonStartDate
     AND isw.FiscalMonthDate < a.HorizonEndDate
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate
),
fallback_ss AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
keys AS (
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fiscal_ss
    UNION
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fallback_ss
)
SELECT
    CAST(k.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(k.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(k.AsOfDate AS DATE) AS AsOfDate,
    CAST(COALESCE(f.SafetyStockTarget, fb.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COALESCE(f.SnapshotCount, fb.SnapshotCount) AS INT) AS SnapshotCount,
    CAST(CASE
        WHEN f.SafetyStockTarget IS NOT NULL THEN 'Next3FiscalMonths'
        ELSE 'Historical13W'
    END AS VARCHAR(30)) AS SafetyStockSource
FROM keys k
LEFT JOIN fiscal_ss f
  ON f.ItemSku = k.ItemSku
 AND f.WarehouseCode = k.WarehouseCode
 AND f.AsOfDate = k.AsOfDate
LEFT JOIN fallback_ss fb
  ON fb.ItemSku = k.ItemSku
 AND fb.WarehouseCode = k.WarehouseCode
 AND fb.AsOfDate = k.AsOfDate;