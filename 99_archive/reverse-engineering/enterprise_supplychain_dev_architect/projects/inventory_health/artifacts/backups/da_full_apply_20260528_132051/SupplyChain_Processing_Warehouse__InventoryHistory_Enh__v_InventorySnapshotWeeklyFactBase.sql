
CREATE   VIEW InventoryHistory_Enh.v_InventorySnapshotWeeklyFactBase AS
-- 2026-05-26: Fact-grain weekly inventory base for Mart B.
-- Grain: (ItemSku, WarehouseCode, SnapshotDate). Text columns use explicit Warehouse collation for Lakehouse/Warehouse UNION stability.
-- Note: no LoadDT in view; Meta.usp_GenericLoad appends LoadDT when materializing.
WITH sat_boundary AS (
    SELECT MIN(SnapshotDate) AS FirstSatSnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklySat
), sat_ranked AS (
    SELECT
        s.*,
        ROW_NUMBER() OVER (
            PARTITION BY s.ItemSku, s.WarehouseCode, s.SnapshotDate
            ORDER BY
                CASE
                    WHEN s.FiscalMonthDate IS NULL THEN 2
                    WHEN s.FiscalMonthDate >= DATEFROMPARTS(YEAR(s.SnapshotDate), MONTH(s.SnapshotDate), 1) THEN 0
                    ELSE 1
                END,
                CASE WHEN s.FiscalMonthDate >= DATEFROMPARTS(YEAR(s.SnapshotDate), MONTH(s.SnapshotDate), 1) THEN s.FiscalMonthDate END ASC,
                s.FiscalMonthDate DESC
        ) AS rn
    FROM InventoryHistory_Enh.InventorySnapshotWeeklySat s
), legacy_ranked AS (
    SELECT
        l.*,
        ROW_NUMBER() OVER (
            PARTITION BY l.ItemSku, l.WarehouseCode, l.SnapshotDate
            ORDER BY
                CASE
                    WHEN l.FiscalMonthDate IS NULL THEN 2
                    WHEN l.FiscalMonthDate >= DATEFROMPARTS(YEAR(l.SnapshotDate), MONTH(l.SnapshotDate), 1) THEN 0
                    ELSE 1
                END,
                CASE WHEN l.FiscalMonthDate >= DATEFROMPARTS(YEAR(l.SnapshotDate), MONTH(l.SnapshotDate), 1) THEN l.FiscalMonthDate END ASC,
                l.FiscalMonthDate DESC
        ) AS rn
    FROM InventoryHistory_Enh.InventorySnapshotWeekly l
    CROSS JOIN sat_boundary b
    WHERE l.SnapshotDate < b.FirstSatSnapshotDate
)
SELECT
    CAST(ItemSku AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS WarehouseCode,
    CAST(SnapshotDate AS DATE) AS SnapshotDate,
    CAST(FiscalMonth AS INT) AS FiscalMonth,
    CAST(FiscalMonthDate AS DATE) AS FiscalMonthDate,
    CAST(OnHandQty AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(IOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
    CAST(OrderQty AS DECIMAL(18,4)) AS OrderQty,
    CAST(BuildQty AS DECIMAL(18,4)) AS BuildQty,
    CAST(ItemStatus AS VARCHAR(10)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemStatus,
    CAST(SourceLabel AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceLabel,
    CAST(SourceSystem AS VARCHAR(64)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceSystem,
    CAST(SourceTable AS VARCHAR(128)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceTable
FROM sat_ranked
WHERE rn = 1
UNION ALL
SELECT
    CAST(ItemSku AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS WarehouseCode,
    CAST(SnapshotDate AS DATE) AS SnapshotDate,
    CAST(FiscalMonth AS INT) AS FiscalMonth,
    CAST(FiscalMonthDate AS DATE) AS FiscalMonthDate,
    CAST(OnHandQty AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(IOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
    CAST(OrderQty AS DECIMAL(18,4)) AS OrderQty,
    CAST(BuildQty AS DECIMAL(18,4)) AS BuildQty,
    CAST(ItemStatus AS VARCHAR(10)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS ItemStatus,
    CAST(SourceLabel AS VARCHAR(50)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceLabel,
    CAST(SourceSystem AS VARCHAR(64)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceSystem,
    CAST(SourceTable AS VARCHAR(128)) COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 AS SourceTable
FROM legacy_ranked
WHERE rn = 1;
