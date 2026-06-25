/*============================================================
  09_master.sql — Master orchestration procs
  Compiles silver.usp_RefreshAll + gold.usp_RefreshAll.
  Wrap Fabric Pipeline schedule around these.
============================================================*/

-- ════════════════════════════════════════════════════════
-- silver.usp_RefreshAll
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_RefreshAll AS
BEGIN
    SET XACT_ABORT ON;
    PRINT '--- Silver refresh start: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);

    -- Tier 0: dims (no deps)
    PRINT 'Tier 0: dims';
    EXEC silver.usp_Build_ItemMaster;
    EXEC silver.usp_Build_Warehouse;
    EXEC silver.usp_Build_Vendor;

    -- Tier 1: base
    PRINT 'Tier 1: base';
    EXEC silver.usp_Build_CostCurrent;
    EXEC silver.usp_Build_InventoryCurrent;
    EXEC silver.usp_Build_ForecastCurrent;
    EXEC silver.usp_Build_SupplyPlan;
    EXEC silver.usp_Build_SalesShipment;
    EXEC silver.usp_Build_PurchaseOrder;
    EXEC silver.usp_Build_ManufacturingOrder;
    EXEC silver.usp_Build_HoldingTransfer;
    EXEC silver.usp_Build_MovementHistory;
    EXEC silver.usp_Build_AtpWeekEnding;
    EXEC silver.usp_Build_AllocatedDemandCandidate;
    EXEC silver.usp_Build_LogilityItemStatus;

    -- Tier 2: large snapshots
    PRINT 'Tier 2: large snapshots';
    EXEC silver.usp_Build_InventorySnapshotWeekly;
    EXEC silver.usp_Build_ForecastSnapshotWeekly;

    -- Tier 3: helpers (after Tier 2)
    PRINT 'Tier 3: helpers';
    EXEC silver.usp_Build_AwdHelper;
    EXEC silver.usp_Build_LastInvoiceHelper;
    EXEC silver.usp_Build_MovementFlagHelper;
    EXEC silver.usp_Build_SafetyStockHelper;

    -- Tier 4: snapshot capture (daily; weekly only on Saturday)
    PRINT 'Tier 4: snapshot capture';
    EXEC silver.usp_Snapshot_PurchaseOrder;
    EXEC silver.usp_Snapshot_ManufacturingOrder;
    EXEC silver.usp_Snapshot_HoldingTransfer;

    -- Weekly snapshot only on Saturday
    -- M1 FIX (2026-05-17): old formula `((@@DATEFIRST + 5) % 7 + 1)` returned 6 with DATEFIRST=7,
    -- but Saturday weekday=7 → mismatch, condition never fired.
    -- Replaced with DATENAME which is DATEFIRST-independent + uses session culture.
    -- Note: warehouse session culture must be en-US (Fabric Warehouse default).
    IF DATENAME(weekday, SYSUTCDATETIME()) = 'Saturday'
        EXEC silver.usp_Snapshot_LogilityItemStatus;

    PRINT '--- Silver refresh end:   ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_RefreshAll
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_RefreshAll AS
BEGIN
    SET XACT_ABORT ON;
    PRINT '--- Gold refresh start: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);

    EXEC gold.usp_Build_DimDate;
    EXEC gold.usp_Build_DimWarehouse;
    EXEC gold.usp_Build_DimVendor;
    EXEC gold.usp_Build_DimItem;
    EXEC gold.usp_Build_DimRuleVersion;

    EXEC gold.usp_Build_CogsRollingHelper;

    EXEC gold.usp_Build_FactInventoryHealthSnapshot;
    EXEC gold.usp_Build_FactInventoryRiskForward;

    PRINT '--- Gold refresh end:   ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);
END;
GO


PRINT '09_master.sql complete: silver.usp_RefreshAll + gold.usp_RefreshAll compiled.';
GO
