/*============================================================
  99_cleanup_silver.sql — DROP ALL silver objects (mandatory after test)
  Run on: SupplyChain Processing Warehouse
  Safety: each DROP uses IF EXISTS — safe to re-run.

  Order:
    1. Drop procs (master + build + snapshot)
    2. Drop tables (base + helpers + snapshots + watermark)
    3. Drop schema [silver]
============================================================*/

PRINT 'silver cleanup start: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);

-- ════════════════════════════════════════════════════════
-- 1. DROP PROCEDURES (master + build + snapshot)
-- ════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS silver.usp_RefreshAll;

DROP PROCEDURE IF EXISTS silver.usp_Build_ItemMaster;
DROP PROCEDURE IF EXISTS silver.usp_Build_Warehouse;
DROP PROCEDURE IF EXISTS silver.usp_Build_Vendor;
DROP PROCEDURE IF EXISTS silver.usp_Build_CostCurrent;
DROP PROCEDURE IF EXISTS silver.usp_Build_InventoryCurrent;
DROP PROCEDURE IF EXISTS silver.usp_Build_ForecastCurrent;
DROP PROCEDURE IF EXISTS silver.usp_Build_SupplyPlan;
DROP PROCEDURE IF EXISTS silver.usp_Build_SalesShipment;
DROP PROCEDURE IF EXISTS silver.usp_Build_PurchaseOrder;
DROP PROCEDURE IF EXISTS silver.usp_Build_ManufacturingOrder;
DROP PROCEDURE IF EXISTS silver.usp_Build_HoldingTransfer;
DROP PROCEDURE IF EXISTS silver.usp_Build_MovementHistory;
DROP PROCEDURE IF EXISTS silver.usp_Build_AtpWeekEnding;
DROP PROCEDURE IF EXISTS silver.usp_Build_AllocatedDemandCandidate;
DROP PROCEDURE IF EXISTS silver.usp_Build_LogilityItemStatus;
DROP PROCEDURE IF EXISTS silver.usp_Build_InventorySnapshotWeekly;
DROP PROCEDURE IF EXISTS silver.usp_Build_ForecastSnapshotWeekly;
DROP PROCEDURE IF EXISTS silver.usp_Build_AwdHelper;
DROP PROCEDURE IF EXISTS silver.usp_Build_LastInvoiceHelper;
DROP PROCEDURE IF EXISTS silver.usp_Build_MovementFlagHelper;
DROP PROCEDURE IF EXISTS silver.usp_Build_SafetyStockHelper;

DROP PROCEDURE IF EXISTS silver.usp_Snapshot_PurchaseOrder;
DROP PROCEDURE IF EXISTS silver.usp_Snapshot_ManufacturingOrder;
DROP PROCEDURE IF EXISTS silver.usp_Snapshot_HoldingTransfer;
DROP PROCEDURE IF EXISTS silver.usp_Snapshot_LogilityItemStatus;

PRINT '  procs dropped';

-- ════════════════════════════════════════════════════════
-- 2. DROP TABLES (staging + final + helpers + snapshots + watermark)
-- ════════════════════════════════════════════════════════

-- Staging tables (created during CTAS + sp_rename pattern, may linger if proc failed)
DROP TABLE IF EXISTS silver.ItemMaster_stg;
DROP TABLE IF EXISTS silver.Warehouse_stg;
DROP TABLE IF EXISTS silver.Vendor_stg;
DROP TABLE IF EXISTS silver.CostCurrent_stg;
DROP TABLE IF EXISTS silver.ForecastCurrent_stg;
DROP TABLE IF EXISTS silver.SupplyPlan_stg;
DROP TABLE IF EXISTS silver.PurchaseOrder_stg;
DROP TABLE IF EXISTS silver.ManufacturingOrder_stg;
DROP TABLE IF EXISTS silver.HoldingTransfer_stg;
DROP TABLE IF EXISTS silver.AtpWeekEnding_stg;
DROP TABLE IF EXISTS silver.AllocatedDemandCandidate_stg;
DROP TABLE IF EXISTS silver.LogilityItemStatus_stg;
DROP TABLE IF EXISTS silver.AwdHelper_stg;
DROP TABLE IF EXISTS silver.LastInvoiceHelper_stg;
DROP TABLE IF EXISTS silver.MovementFlagHelper_stg;
DROP TABLE IF EXISTS silver.SafetyStockHelper_stg;

-- Base + helper tables
DROP TABLE IF EXISTS silver.ItemMaster;
DROP TABLE IF EXISTS silver.Warehouse;
DROP TABLE IF EXISTS silver.Vendor;
DROP TABLE IF EXISTS silver.CostCurrent;
DROP TABLE IF EXISTS silver.InventoryCurrent;
DROP TABLE IF EXISTS silver.ForecastCurrent;
DROP TABLE IF EXISTS silver.SupplyPlan;
DROP TABLE IF EXISTS silver.SalesShipment;
DROP TABLE IF EXISTS silver.PurchaseOrder;
DROP TABLE IF EXISTS silver.ManufacturingOrder;
DROP TABLE IF EXISTS silver.HoldingTransfer;
DROP TABLE IF EXISTS silver.MovementHistory;
DROP TABLE IF EXISTS silver.AtpWeekEnding;
DROP TABLE IF EXISTS silver.AllocatedDemandCandidate;
DROP TABLE IF EXISTS silver.LogilityItemStatus;
DROP TABLE IF EXISTS silver.InventorySnapshotWeekly;
DROP TABLE IF EXISTS silver.ForecastSnapshotWeekly;
DROP TABLE IF EXISTS silver.AwdHelper;
DROP TABLE IF EXISTS silver.LastInvoiceHelper;
DROP TABLE IF EXISTS silver.MovementFlagHelper;
DROP TABLE IF EXISTS silver.SafetyStockHelper;

-- Snapshot capture tables
DROP TABLE IF EXISTS silver.PurchaseOrderSnapshotDaily;
DROP TABLE IF EXISTS silver.ManufacturingOrderSnapshotDaily;
DROP TABLE IF EXISTS silver.HoldingTransferSnapshotDaily;
DROP TABLE IF EXISTS silver.LogilityItemStatusSnapshotWeekly;

-- Watermark + ItemBalanceHistory (placeholder)
DROP TABLE IF EXISTS silver.EtlWatermark;
DROP TABLE IF EXISTS silver.ItemBalanceHistory;

PRINT '  tables dropped';

-- ════════════════════════════════════════════════════════
-- 3. DROP SCHEMA
-- ════════════════════════════════════════════════════════
-- Note: only drops if all objects gone. If error, re-run section 1+2.
DROP SCHEMA IF EXISTS silver;
PRINT '  schema dropped';


-- ════════════════════════════════════════════════════════
-- 4. VERIFY cleanup complete
-- ════════════════════════════════════════════════════════
SELECT
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES   WHERE TABLE_SCHEMA = 'silver') AS RemainingTables,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = 'silver') AS RemainingProcs,
    (SELECT COUNT(*) FROM sys.schemas WHERE name = 'silver') AS SchemaExists;
-- expect: 0, 0, 0

PRINT 'silver cleanup done: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);
GO
