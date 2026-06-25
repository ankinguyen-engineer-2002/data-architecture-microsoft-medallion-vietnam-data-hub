-- DA feedback compatibility adapter for Gold fact grain.
-- Source of truth for weekly inventory is now InventoryHistory_Enh.InventorySnapshotWeekly
-- generated from Giang's DA SQL export:
--   SnapshotDate := SnapshotWeekEndingDate
--   ItemStatus   := NULL (not provided by DA InventorySnapshotWeekly)

CREATE OR ALTER VIEW InventoryHistory_Enh.v_InventorySnapshotWeeklyFactBase AS
WITH ranked AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotWeekEndingDate,
        FiscalMonth,
        FiscalMonthDate,
        OnHandQty,
        SafetyStockTarget,
        IOSafetyStock,
        OrderQty,
        BuildQty,
        SourceLabel,
        SourceSystem,
        SourceTable,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
            ORDER BY
                CASE
                    WHEN FiscalMonthDate IS NULL THEN 2
                    WHEN FiscalMonthDate >= DATEFROMPARTS(YEAR(SnapshotWeekEndingDate), MONTH(SnapshotWeekEndingDate), 1) THEN 0
                    ELSE 1
                END,
                CASE
                    WHEN FiscalMonthDate >= DATEFROMPARTS(YEAR(SnapshotWeekEndingDate), MONTH(SnapshotWeekEndingDate), 1)
                    THEN FiscalMonthDate
                END ASC,
                FiscalMonthDate DESC
        ) AS rn
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
)
SELECT
    CAST(ItemSku AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS WarehouseCode,
    CAST(SnapshotWeekEndingDate AS DATE) AS SnapshotDate,
    CAST(FiscalMonth AS INT) AS FiscalMonth,
    CAST(FiscalMonthDate AS DATE) AS FiscalMonthDate,
    CAST(OnHandQty AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(IOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
    CAST(OrderQty AS DECIMAL(18,4)) AS OrderQty,
    CAST(BuildQty AS DECIMAL(18,4)) AS BuildQty,
    CAST(NULL AS VARCHAR(10)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemStatus,
    CAST(SourceLabel AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceLabel,
    CAST(SourceSystem AS VARCHAR(64)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceSystem,
    CAST(SourceTable AS VARCHAR(128)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceTable
FROM ranked
WHERE rn = 1;

GO
