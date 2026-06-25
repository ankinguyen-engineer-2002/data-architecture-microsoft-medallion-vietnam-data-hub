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
