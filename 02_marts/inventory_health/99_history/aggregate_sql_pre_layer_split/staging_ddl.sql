-- ============================================================
-- Staging DDL — InventoryHealth Project
-- ============================================================
-- Target: SupplyChain_Processing_Warehouse.Staging_Wrk
-- Pattern: minimal staging tables only for EDW supplements the views need
-- but which DON'T yet land cleanly via Enterprise_Lakehouse shortcut.
--
-- v10 design intent: inventory_health uses Bronze shortcuts directly from
-- Enterprise_Lakehouse (no staging) for ~80% of sources. The remaining
-- 4 sources are STALE / NOT YET LOADED by DE US team and need a
-- dataflow-fed staging table OR a fix at the Bronze layer.
--
-- STATUS: Staging tables NOT YET REQUIRED — all current views read directly
-- from Enterprise_Lakehouse shortcuts. The 4 blocking sources below are
-- being addressed via the `dataflows/drafts/` folder (Fabric Gen2 dataflows),
-- which writes back into Enterprise_Lakehouse, NOT Staging_Wrk.
-- ============================================================
-- BLOCKED on DE US team (parallel track, separate from this file):
--   1. Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster    — not loaded
--   2. Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance         — schema missing
--   3. SupplyChain_Lakehouse.dbo.logility_demandfulfillment           — partial / stale
--   4. SupplyChain_Enh.PurchaseOrderSnapshot                          — EDW-only currently
--
-- See `01_docs/open_questions_for_bob.md` + `dataflows/drafts/README.md` + recent
-- commits (8683eaeb, 533fb1c6, b38d4e81) for dataflow fix progress.
-- ============================================================
-- If/when DE US declines to fix one of the 4 at the Bronze layer and we
-- must materialize an EDW supplement table here instead, uncomment the
-- relevant block below and:
--   1. Insert a row into Meta.AssetRegistry with canonical_layer='Staging'
--      and project='inventory_health'
--   2. Update the corresponding Silver view (silver_views.sql) to read
--      from [Staging_Wrk].[...] instead of [Enterprise_Lakehouse].[...]
-- ============================================================


-- =========================================================
-- Optional: PoMasterEdw staging (uncomment if Bronze load fails)
-- =========================================================
/*
CREATE TABLE Staging_Wrk.PoMasterEdw (
    PoNumber            VARCHAR(50)     NOT NULL,
    VendorNumber        VARCHAR(50)     NULL,
    EstimatedArrivalDt  DATE            NULL,
    EstimatedDepartDt   DATE            NULL,
    PromisedReceiptDt   DATE            NULL,
    ContainerNumber     VARCHAR(50)     NULL,
    TotalCubes          DECIMAL(18,4)   NULL,
    LoadDT              DATETIME2(6)    NOT NULL DEFAULT CAST(GETUTCDATE() AS DATETIME2(6))
);
*/


-- =========================================================
-- Optional: ItemBalanceEdw staging (uncomment if Bronze load fails)
-- =========================================================
/*
CREATE TABLE Staging_Wrk.ItemBalanceEdw (
    ItemSku            VARCHAR(50)     NOT NULL,
    WarehouseCode      VARCHAR(50)     NOT NULL,
    SnapshotDate       DATE            NOT NULL,
    OnHandQty          DECIMAL(18,4)   NULL,
    SafetyStockTarget  DECIMAL(18,4)   NULL,
    OrderQty           DECIMAL(18,4)   NULL,
    BuildQty           DECIMAL(18,4)   NULL,
    LoadDT             DATETIME2(6)    NOT NULL DEFAULT CAST(GETUTCDATE() AS DATETIME2(6))
);
*/


-- =========================================================
-- Optional: LogilityItemStatusEdw staging (uncomment if Bronze load fails)
-- =========================================================
/*
CREATE TABLE Staging_Wrk.LogilityItemStatusEdw (
    ItemSku            VARCHAR(50)     NOT NULL,
    WarehouseCode      VARCHAR(50)     NOT NULL,
    WeekEndingDate     DATE            NOT NULL,
    ItemStatus         VARCHAR(20)     NULL,
    FutureStatus       VARCHAR(20)     NULL,
    OnHandQty          DECIMAL(18,4)   NULL,
    SafetyStockQty     DECIMAL(18,4)   NULL,
    ShippableInvQty    DECIMAL(18,4)   NULL,
    LoadDT             DATETIME2(6)    NOT NULL DEFAULT CAST(GETUTCDATE() AS DATETIME2(6))
);
*/


-- =========================================================
-- Optional: PurchaseOrderSnapshotEdw staging (uncomment if Bronze load fails)
-- =========================================================
/*
CREATE TABLE Staging_Wrk.PurchaseOrderSnapshotEdw (
    SnapshotDate       DATE            NOT NULL,
    PoNumber           VARCHAR(50)     NOT NULL,
    PoLine             INT             NOT NULL,
    ItemSku            VARCHAR(50)     NULL,
    WarehouseCode      VARCHAR(50)     NULL,
    POOnOrderQty       DECIMAL(18,4)   NULL,
    POInTransitQty     DECIMAL(18,4)   NULL,
    LoadDT             DATETIME2(6)    NOT NULL DEFAULT CAST(GETUTCDATE() AS DATETIME2(6))
);
*/


-- ============================================================
-- END staging_ddl.sql — no active staging tables in Phase 1.
-- ============================================================
