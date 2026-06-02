-- =====================================================================
-- Inventory Health Mart B - Inventory weekly Saturday fix
-- Created: 2026-05-26
--
-- Goal:
--   1. Derive inventory weekly snapshots from DemandInventorySnapshotDaily
--      on Saturday, matching ForecastSnapshotWeeklySat.
--   2. Dedupe Daily at source grain:
--      (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth).
--   3. Collapse weekly inventory to Mart B fact grain:
--      (ItemSku, WarehouseCode, SnapshotDate).
--
-- Live additive objects created in DEV:
--   Staging_Wrk.v_DemandInventorySnapshotDailySatClean
--   InventoryHistory_Enh.v_InventorySnapshotWeeklySat
--   InventoryHistory_Enh.InventorySnapshotWeeklySat
--   InventoryHistory_Enh.v_InventorySnapshotWeeklyFactBase
--   InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
--
-- Candidate objects created in DEV for validation only:
--   InventoryHistory_Enh.*_InvFixCandidate helper views/tables
--   InventoryHealth_DW.v_FactInventoryHealthSnapshot_InvFixCandidate
--   InventoryHealth_DW.FactInventoryHealthSnapshot_InvFixCandidate
--
-- Production swap completed in DEV, 2026-05-26:
--   InventoryHistory_Enh.AwdHelper_Backup_20260526
--   InventoryHistory_Enh.LastInvoiceHelper_Backup_20260526
--   InventoryHistory_Enh.MovementFlagHelper_Backup_20260526
--   InventoryHistory_Enh.SafetyStockHelper_Backup_20260526
--   InventoryHealth_DW.FactInventoryHealthSnapshot_Backup_20260526
--
-- Current production names remain standard:
--   InventoryHistory_Enh.AwdHelper
--   InventoryHistory_Enh.LastInvoiceHelper
--   InventoryHistory_Enh.MovementFlagHelper
--   InventoryHistory_Enh.SafetyStockHelper
--   InventoryHealth_DW.FactInventoryHealthSnapshot
--
-- Safety:
--   Do not run destructive replacement from this script without explicit
--   approval. Current Meta.usp_GenericLoad overwrite path uses
--   DROP TABLE IF EXISTS before CTAS.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Validation evidence from DEV, 2026-05-26
-- ---------------------------------------------------------------------
-- InventorySnapshotWeeklySat:
--   rows                    = 97,190,388
--   snapshot dates          = 24
--   date range              = 2025-12-06 -> 2026-05-23
--   weekday_monday_1        = 6 only (Saturday)
--   source grain duplicates = 0
--
-- InventorySnapshotWeeklyFactBase:
--   rows                    = 60,823,881
--   snapshot dates          = 401
--   date range              = 2021-03-06 -> 2026-05-23
--   fact grain duplicates   = 0
--
-- FactInventoryHealthSnapshot_InvFixCandidate:
--   rows                    = 60,863,596
--   snapshot dates          = 402
--   date range              = 2021-03-06 -> 2026-05-26
--   fact grain duplicates   = 0
--
-- Post-swap actual FactInventoryHealthSnapshot:
--   rows                    = 60,863,596
--   snapshot dates          = 402
--   date range              = 2021-03-06 -> 2026-05-26
--   fact grain duplicates   = 0
--
-- ForecastSnapshotWeeklySat re-check:
--   rows                    = 465,306,850
--   snapshot dates          = 160
--   date range              = 2023-01-07 -> 2026-02-21
--   Saturday-only check     = pass
--   source grain duplicates = 0
--   latest Sat parity       = pass vs Staging_Wrk.DemandForecastSnapshotDaily
--   freshness note          = staging daily max snapshot is 2026-02-24
--
-- Current actual FactInventoryHealthSnapshot before replacement:
--   rows                    = 603,018,417
--   fact grain duplicates   = 538,621,125 extra rows
--   max rows per key        = 36


-- ---------------------------------------------------------------------
-- QC queries
-- ---------------------------------------------------------------------

-- 1. Saturday-only and source-grain uniqueness.
WITH source_grain AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonth,
        COUNT_BIG(*) AS row_count
    FROM InventoryHistory_Enh.InventorySnapshotWeeklySat
    GROUP BY ItemSku, WarehouseCode, SnapshotDate, FiscalMonth
)
SELECT
    SUM(row_count) AS raw_rows,
    COUNT_BIG(*) AS source_grain_rows,
    SUM(row_count) - COUNT_BIG(*) AS duplicate_extra_rows,
    MAX(row_count) AS max_rows_per_source_key
FROM source_grain;


-- 2. FactBase uniqueness.
WITH fact_grain AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        COUNT_BIG(*) AS row_count
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    GROUP BY ItemSku, WarehouseCode, SnapshotDate
)
SELECT
    SUM(row_count) AS raw_rows,
    COUNT_BIG(*) AS fact_grain_rows,
    SUM(row_count) - COUNT_BIG(*) AS duplicate_extra_rows,
    MAX(row_count) AS max_rows_per_fact_key
FROM fact_grain;


-- 3. Candidate fact uniqueness.
WITH fact_grain AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        SnapshotType,
        COUNT_BIG(*) AS row_count
    FROM InventoryHealth_DW.FactInventoryHealthSnapshot_InvFixCandidate
    GROUP BY ItemSku, WarehouseCode, SnapshotDate, SnapshotType
)
SELECT
    SUM(row_count) AS raw_rows,
    COUNT_BIG(*) AS fact_grain_rows,
    SUM(row_count) - COUNT_BIG(*) AS duplicate_extra_rows,
    MAX(row_count) AS max_rows_per_fact_key
FROM fact_grain;
