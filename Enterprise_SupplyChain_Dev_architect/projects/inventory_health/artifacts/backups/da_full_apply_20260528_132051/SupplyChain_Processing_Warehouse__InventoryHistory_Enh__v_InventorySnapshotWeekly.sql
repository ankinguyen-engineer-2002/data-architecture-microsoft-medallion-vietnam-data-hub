
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
