
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
    SELECT DISTINCT SnapshotDate FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
)
SELECT
    CAST(isw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(isw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate         AS DATE)          AS AsOfDate,
    CAST(AVG(isw.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COUNT(*)           AS INT)           AS SnapshotCount   -- QA: should be ≤ 13
FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
JOIN asof a
     ON isw.SnapshotDate <= a.AsOfDate
    AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
WHERE isw.SafetyStockTarget IS NOT NULL
GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
