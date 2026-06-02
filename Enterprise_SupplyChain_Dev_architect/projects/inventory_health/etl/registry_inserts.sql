-- ============================================================
-- Meta.AssetRegistry rows — InventoryHealth Project
-- ============================================================
-- Target: SupplyChain_Processing_Warehouse.Meta.AssetRegistry
-- Purpose: register all 33 inventory_health assets so pl_sc_master ForEach DISTINCT project
--          auto-picks 'inventory_health' alongside 'forecast_accuracy'.
--          (Registry consolidated 2026-05-20: legacy labels 'supplychain' + 'SC_ForecastAccuracy'
--           → unified to 'forecast_accuracy' so distinct project values match real mart count = 2.)
-- Pattern matches forecast registry rows (33 live rows verified 2026-05-18).
--
-- Run order after deploy:
--   1. Execute silver_views.sql (Processing WH)
--   2. Execute gold_views.sql (Gold WH)
--   3. Execute this file (Processing WH — Meta schema)
--   4. EXEC Meta.usp_ComputeSilverWaves    (recompute Silver DAG)
--   5. EXEC Meta.usp_BuildLineage          (rebuild lineage edges from source_objects)
--   6. EXEC Meta.usp_CheckDqSingle per active DQ rule (or run pl_dq_check pipeline)
-- ============================================================
-- DEPLOY NOTE: most assets default is_active=0 until DE US fixes 4 stale bronze sources
-- + Robert signs off on H1/H5/M3. Promote individual rows to is_active=1 progressively.
-- ============================================================

DECLARE @ws VARCHAR(128) = 'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0';   -- SupplyChain Dev workspace
DECLARE @wh_proc VARCHAR(128) = 'SupplyChain_Processing_Warehouse';
DECLARE @wh_gold VARCHAR(128) = 'SupplyChain_Gold_Warehouse';


-- ============================================================
-- §1. ReferenceMaster layer — 1 NEW Vendor master
-- ============================================================

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
('ReferenceMaster_Enh.Vendor', 'inventory_health', 'ReferenceMaster',
 @ws, @wh_proc, 'ReferenceMaster_Enh', 'Vendor',
 'ReferenceMaster_Enh.v_Vendor', 'overwrite', 'VendorNumber',
 '["Enterprise_Lakehouse.Purchasing_AFI.VendorMaster"]', NULL,
 'monthly', '0 3 1 * *', 1, 'WarehouseTransform');


-- ============================================================
-- §2. DomainSilver layer — InventoryHistory_Enh (24 assets)
-- ============================================================

-- ── Master extensions (2 assets) ─────────────────────────────
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
('InventoryHistory_Enh.ItemMasterExt', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'ItemMasterExt',
 'InventoryHistory_Enh.v_ItemMasterExt', 'overwrite', 'ItemSku',
 '["Enterprise_Lakehouse.MasterData_DW.DimItemMaster","Enterprise_Lakehouse.Purchasing_AFI.VendorMaster","Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT","ReferenceMaster_Enh.ItemMaster"]', NULL,
 'monthly', '0 3 1 * *', 0, 'WarehouseTransform'), -- inlined via Shared_DW.DimProduct

('InventoryHistory_Enh.WarehouseExt', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'WarehouseExt',
 'InventoryHistory_Enh.v_WarehouseExt', 'overwrite', 'WarehouseCode',
 '["Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster","ReferenceMaster_Enh.Warehouse"]', NULL,
 'monthly', '0 3 1 * *', 0, 'WarehouseTransform');


-- ── Tier 1 base (12 assets) ──────────────────────────────────
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, watermark_column, primary_key, date_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
('InventoryHistory_Enh.CostCurrent', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'CostCurrent',
 'InventoryHistory_Enh.v_CostCurrent', 'overwrite', NULL, 'ItemSku', NULL,
 '["Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA"]', NULL,
 'daily', '0 2 * * *', 0, 'WarehouseTransform'), -- inlined in CogsRollingHelper / Gold facts

-- BLOCKED on DE US ITEMBL full load; set is_active=0 initially
('InventoryHistory_Enh.InventoryCurrent', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'InventoryCurrent',
 -- 2026-05-20: load_type swapped datekey → overwrite (fix 99-min hang; CAST=CAST predicate non-sargable + view returns today-only via SYSUTCDATETIME, so overwrite gives same result without history loss in physical table).
 'InventoryHistory_Enh.v_InventoryCurrent', 'overwrite', NULL, 'ItemSku,WarehouseCode,SnapshotDate', NULL,
 '["Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL"]', NULL,
 'daily', '0 2 * * *', 0, 'WarehouseTransform'),

('InventoryHistory_Enh.SupplyPlan', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'SupplyPlan',
 'InventoryHistory_Enh.v_SupplyPlan', 'overwrite', NULL, 'ItemSku,WarehouseCode,SnapshotDate,WeekEndingDate', NULL,
 '["Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail"]', NULL,
 'daily', '0 2 * * *', 0, 'WarehouseTransform'), -- retired 2026-06-01; DA removed ATP forward-looking logic

-- REMOVED 2026-05-28: DA-first flow reuses SalesHistory_Enh.v_InvoiceDetailLineLevel directly.
-- Do not register InventoryHistory_Enh.SalesShipment as a Mart B asset.

-- A2 RESOLVED 2026-05-19: Dhivya loaded Enterprise.PoMaster (5.69M); switched LEFT JOIN; is_active=1
-- D3.2 FIX 2026-05-19: PK includes VendorNumber. Source PoDetail reuses (PoNumber, PoLine) across vendors
--   (verified 48 collisions where same PoNumber+PoLine has 1 real PO + 1 SAMPLE PO with different VendorNumber).
('InventoryHistory_Enh.PurchaseOrder', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'PurchaseOrder',
 'InventoryHistory_Enh.v_PurchaseOrder', 'overwrite', NULL, 'PoNumber,PoLine,VendorNumber', NULL,
 '["Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail","Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster"]', NULL,
 'daily', '0 2 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.ManufacturingOrder', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'ManufacturingOrder',
 'InventoryHistory_Enh.v_ManufacturingOrder', 'overwrite', NULL, 'MoNumber,ItemSku,WarehouseCode', NULL,
 '["Enterprise_Lakehouse.Manufacturing_ProductionPlanning_AFI.MOMAST"]', NULL,
 'daily', '0 2 * * *', 1, 'WarehouseTransform'),

-- A3 RESOLVED 2026-05-19: Dhivya promoted to Enterprise.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility (38.36M); switched source; is_active=1
-- D1 NOTE: source has 9,128 grain-conflict groups; view dedupe prefers non-zero metrics
('InventoryHistory_Enh.LogilityItemStatus', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'LogilityItemStatus',
 'InventoryHistory_Enh.v_LogilityItemStatus', 'overwrite', NULL, 'WeekEndingDate,ItemSku,WarehouseCode', NULL,
 '["Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility"]', NULL,
 'weekly', '0 6 * * 6', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.HoldingTransfer', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'HoldingTransfer',
 'InventoryHistory_Enh.v_HoldingTransfer', 'overwrite', NULL, 'TransferNumber,ItemSku', NULL,
 '["Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRDTL","Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRHDR"]', NULL,
 'daily', '0 2 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.AtpWeekEnding', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'AtpWeekEnding',
 'InventoryHistory_Enh.v_AtpWeekEnding', 'overwrite', NULL, 'ItemSku,WarehouseCode,WeekNumber', NULL,
 '["Enterprise_Lakehouse.Wholesale_Purchasing_AFI.ATPSUM"]', NULL,
 'daily', '0 2 * * *', 0, 'WarehouseTransform'), -- inlined in FactInventoryRiskForward

-- DROPPED 2026-05-22: MovementHistory ── tagged orphan in Option B refactor 2026-05-21,
-- never wired into Fact (KPI #26 served via LastInvoiceHelper; KPI #30 not in Phase 1)

('InventoryHistory_Enh.AllocatedDemandCandidate', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'AllocatedDemandCandidate',
 'InventoryHistory_Enh.v_AllocatedDemandCandidate', 'overwrite', NULL, 'OrderNumber,OrderLine', NULL,
 '["Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail","Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderHeader"]', NULL,
 'daily', '0 2 * * *', 0, 'WarehouseTransform'); -- inlined in FactInventoryRiskForward

-- DROPPED 2026-05-22: ForecastCurrent ── tagged orphan in Option B refactor 2026-05-21,
-- never wired into Fact (KPI #7 served via ForecastSnapshotWeekly history)


-- ── Tier 2 snapshot history (2 assets, incremental) ──────────
-- BLOCKED on DE US ItemBalance load; is_active=0 initially.
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, watermark_column, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
-- 2026-05-28 DA feedback: use DemandInventorySnapshotDaily Saturday captures only.
-- Do not use ItemBalanceHistorical as InventorySnapshotWeekly backup/backfill.
('InventoryHistory_Enh.InventorySnapshotWeekly', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'InventorySnapshotWeekly',
 'InventoryHistory_Enh.v_InventorySnapshotWeekly', 'overwrite', NULL, 'ItemSku,WarehouseCode,SnapshotWeekEndingDate,FiscalMonth',
 '["Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotDaily"]', NULL,
 'weekly', '0 6 * * 6', 1, 'WarehouseTransform'),

-- 2026-05-28 DA feedback: ForecastSnapshotWeekly now reads Staging_Wrk.DemandForecastSnapshotDaily Saturday captures.
('InventoryHistory_Enh.ForecastSnapshotWeekly', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'ForecastSnapshotWeekly',
 'InventoryHistory_Enh.v_ForecastSnapshotWeekly', 'overwrite', NULL, 'ItemSku,WarehouseCode,SnapshotDate,FiscalMonth',
 '["Staging_Wrk.DemandForecastSnapshotDaily"]', NULL,
 'weekly', '0 6 * * 6', 1, 'WarehouseTransform');

-- ── Tier 3 helpers (4 assets, depend on Tier 1 + Tier 2) ─────
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
('InventoryHistory_Enh.AwdHelper', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'AwdHelper',
 'InventoryHistory_Enh.v_AwdHelper', 'overwrite', 'AsOfDate,ItemSku,WarehouseCode',
 '["Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL","InventoryHistory_Enh.InventorySnapshotWeekly","InventoryHistory_Enh.ForecastSnapshotWeekly","SalesHistory_Enh.v_InvoiceDetailLineLevel"]',
 'InventoryHistory_Enh.InventorySnapshotWeekly,InventoryHistory_Enh.ForecastSnapshotWeekly,SalesHistory_Enh.v_InvoiceDetailLineLevel',
 'daily', '0 3 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.LastInvoiceHelper', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'LastInvoiceHelper',
 'InventoryHistory_Enh.v_LastInvoiceHelper', 'overwrite', 'AsOfDate,ItemSku,WarehouseCode',
 '["InventoryHistory_Enh.InventorySnapshotWeekly","SalesHistory_Enh.v_InvoiceDetailLineLevel"]',
 'InventoryHistory_Enh.InventorySnapshotWeekly,SalesHistory_Enh.v_InvoiceDetailLineLevel',
 'daily', '0 3 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.MovementFlagHelper', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'MovementFlagHelper',
 'InventoryHistory_Enh.v_MovementFlagHelper', 'overwrite', 'AsOfDate,ItemSku,WarehouseCode',
 '["InventoryHistory_Enh.InventorySnapshotWeekly","SalesHistory_Enh.v_InvoiceDetailLineLevel"]',
 'InventoryHistory_Enh.InventorySnapshotWeekly,SalesHistory_Enh.v_InvoiceDetailLineLevel',
 'daily', '0 3 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.SafetyStockHelper', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'SafetyStockHelper',
 'InventoryHistory_Enh.v_SafetyStockHelper', 'overwrite', 'AsOfDate,ItemSku,WarehouseCode',
 '["InventoryHistory_Enh.InventorySnapshotWeekly"]',
 'InventoryHistory_Enh.InventorySnapshotWeekly',
 'daily', '0 3 * * *', 1, 'WarehouseTransform');


-- ── Tier 4 self-snapshots (4 assets, datekey) ────────────────
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key, date_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
('InventoryHistory_Enh.PurchaseOrderSnapshotDaily', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'PurchaseOrderSnapshotDaily',
 'InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily', 'datekey',
 'SnapshotDate,PoNumber,PoLine', 'SnapshotDate',
 '["InventoryHistory_Enh.PurchaseOrder"]', 'InventoryHistory_Enh.PurchaseOrder',
 'daily', '0 4 * * *', 0, 'WarehouseTransform'),

('InventoryHistory_Enh.ManufacturingOrderSnapshotDaily', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'ManufacturingOrderSnapshotDaily',
 'InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily', 'datekey',
 'SnapshotDate,MoNumber,ItemSku,WarehouseCode', 'SnapshotDate',
 '["InventoryHistory_Enh.ManufacturingOrder"]', 'InventoryHistory_Enh.ManufacturingOrder',
 'daily', '0 4 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.HoldingTransferSnapshotDaily', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'HoldingTransferSnapshotDaily',
 'InventoryHistory_Enh.v_HoldingTransferSnapshotDaily', 'datekey',
 'SnapshotDate,TransferNumber,TransferLine', 'SnapshotDate',
 '["InventoryHistory_Enh.HoldingTransfer"]', 'InventoryHistory_Enh.HoldingTransfer',
 'daily', '0 4 * * *', 1, 'WarehouseTransform'),

('InventoryHistory_Enh.LogilityItemStatusSnapshotWeekly', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'LogilityItemStatusSnapshotWeekly',
 'InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly', 'datekey',
 'WeekEndingDate,ItemSku,WarehouseCode', 'WeekEndingDate',
 '["InventoryHistory_Enh.LogilityItemStatus"]', 'InventoryHistory_Enh.LogilityItemStatus',
 'weekly', '0 6 * * 6', 0, 'WarehouseTransform');


-- NOTE 2026-05-22: LogilityItemStatusSnapshotWeekly above kept with is_active=0
-- (Phase 2 conditional — KPI #17/#18/#20a past-tracking, awaiting Robert sign-off).

-- ============================================================
-- §3. Gold layer — InventoryHealth_DW (3 Dim + 1 Helper + 2 Fact = 6 assets)
-- 2026-05-22 cleanup:
--   - DROPPED DimRuleVersion (over-engineering — versioning via new semantic model
--     when BRD changes, not via versioned dim)
--   - DROPPED DimDate (duplicate — consolidated to Shared_DW.DimCalendar
--     as single shared date dim; cross-schema TMDL bind from inv_health)
-- ============================================================

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES
-- DROPPED 2026-05-22: DimDate ── consolidated to Shared_DW.DimCalendar
-- (single shared date dim across both marts; inv_health TMDL rebinds via cross-schema)

('InventoryHealth_DW.DimItem', 'inventory_health', 'Gold',
 @ws, @wh_gold, 'InventoryHealth_DW', 'DimItem',
 'InventoryHealth_DW.v_DimItem', 'overwrite', 'ItemSku',
 '["InventoryHistory_Enh.ItemMasterExt"]', 'InventoryHistory_Enh.ItemMasterExt',
 'monthly', '0 3 1 * *', 1, 'GoldPublish'),

-- DROPPED 2026-05-29: InventoryHealth_DW.DimWarehouse
-- Consolidated to Shared_DW.DimWarehouse with forecast + inventory warehouse attrs.

('InventoryHealth_DW.DimVendor', 'inventory_health', 'Gold',
 @ws, @wh_gold, 'InventoryHealth_DW', 'DimVendor',
 'InventoryHealth_DW.v_DimVendor', 'overwrite', 'VendorNumber',
 '["ReferenceMaster_Enh.Vendor"]', 'ReferenceMaster_Enh.Vendor',
 'monthly', '0 3 1 * *', 1, 'GoldPublish'),

-- DROPPED 2026-05-22: DimRuleVersion ── versioning via new semantic model instead of dim

('InventoryHealth_DW.CogsRollingHelper', 'inventory_health', 'Gold',
 @ws, @wh_gold, 'InventoryHealth_DW', 'CogsRollingHelper',
 'InventoryHealth_DW.v_CogsRollingHelper', 'overwrite', 'ItemSku,WarehouseCode,FiscalMonthYear',
 '["SalesHistory_Enh.v_InvoiceDetailLineLevel","Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA","Shared_DW.DimCalendar"]',
 'SalesHistory_Enh.v_InvoiceDetailLineLevel,Shared_DW.DimCalendar',
 'daily', '0 5 * * *', 1, 'GoldPublish'),

('InventoryHealth_DW.FactInventoryHealthSnapshot', 'inventory_health', 'Gold',
 @ws, @wh_gold, 'InventoryHealth_DW', 'FactInventoryHealthSnapshot',
 'InventoryHealth_DW.v_FactInventoryHealthSnapshot', 'overwrite', 'ItemSku,WarehouseCode,SnapshotDate,SnapshotType',
 '["Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL","Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA","InventoryHistory_Enh.InventorySnapshotWeekly","InventoryHistory_Enh.PurchaseOrderSnapshotDaily","InventoryHistory_Enh.ManufacturingOrderSnapshotDaily","InventoryHistory_Enh.HoldingTransferSnapshotDaily","InventoryHistory_Enh.AwdHelper","InventoryHistory_Enh.LastInvoiceHelper","InventoryHistory_Enh.MovementFlagHelper","InventoryHistory_Enh.SafetyStockHelper","InventoryHealth_DW.CogsRollingHelper","Shared_DW.DimCalendar","Shared_DW.DimProduct","Shared_DW.DimWarehouse"]',
 'InventoryHistory_Enh.InventorySnapshotWeekly,InventoryHistory_Enh.PurchaseOrderSnapshotDaily,InventoryHistory_Enh.ManufacturingOrderSnapshotDaily,InventoryHistory_Enh.HoldingTransferSnapshotDaily,InventoryHistory_Enh.AwdHelper,InventoryHistory_Enh.LastInvoiceHelper,InventoryHistory_Enh.MovementFlagHelper,InventoryHistory_Enh.SafetyStockHelper,InventoryHealth_DW.CogsRollingHelper,Shared_DW.DimCalendar,Shared_DW.DimProduct,Shared_DW.DimWarehouse',
 'daily', '0 5 * * *', 1, 'GoldPublish'),

('InventoryHealth_DW.FactInventoryRiskForward', 'inventory_health', 'Gold',
 @ws, @wh_gold, 'InventoryHealth_DW', 'FactInventoryRiskForward',
 'InventoryHealth_DW.v_FactInventoryRiskForward', 'overwrite', 'ItemSku,WarehouseCode,WeekEndingDate',
 '["Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail","Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail","Shared_DW.DimProduct","Shared_DW.DimCalendar"]',
 'Shared_DW.DimProduct,Shared_DW.DimCalendar',
 'daily', '0 5 * * *', 1, 'GoldPublish');


-- ============================================================
-- §G. SC_LH workaround tables (DF2 → SC_LH; following forecast pattern) — NEW 2026-05-19
-- ============================================================
-- Forecast project precedent: wires `_ver2` DF2 tables into pipeline as Silver assets.
-- Inventory_health adopts same pattern: register SC_LH workaround sources NOW, swap source_objects
-- to EL when Dhivya promotes Enterprise.Inventory_Enh_History.ItemBalance + Enterprise.SupplyChain_Enh.PurchaseOrderSnapshot.
-- This avoids losing 5 years of historical inventory data + unblocks Phase 2 PO-as-of feature.

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, watermark_column, primary_key,
    source_objects,
    frequency, cron_expression, is_active, access_mode
) VALUES
('InventoryHistory_Enh.ItemBalanceHistorical', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'ItemBalanceHistorical',
 'InventoryHistory_Enh.v_ItemBalanceHistorical', 'overwrite', NULL, 'ItemSku,WarehouseCode,WeekEndingDate',
 '["SupplyChain_Lakehouse.dbo.itembalance"]',
 'weekly', '0 6 * * 6', 1, 'WarehouseTransform'),

-- Phase 2: 2B rows. Register but is_active=0 — flip to 1 when Phase 2 PO-as-of feature scoped.
('InventoryHistory_Enh.PurchaseOrderSnapshotHistorical', 'inventory_health', 'DomainSilver',
 @ws, @wh_proc, 'InventoryHistory_Enh', 'PurchaseOrderSnapshotHistorical',
 'InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical', 'incremental', 'SnapshotDate', 'SnapshotDate,ItemSku,WarehouseCode,VendorNumber,StatusCode',
 '["SupplyChain_Lakehouse.dbo.purchaseordersnapshot"]',
 'daily', '0 4 * * *', 0, 'WarehouseTransform');


-- ============================================================
-- After insert: recompute Silver DAG waves + rebuild lineage edges
-- ============================================================
-- EXEC Meta.usp_ComputeSilverWaves;
-- EXEC Meta.usp_BuildLineage;
--
-- Verify: SELECT project, canonical_layer, COUNT(*)
--         FROM Meta.AssetRegistry
--         WHERE project='inventory_health'
--         GROUP BY project, canonical_layer;
-- Expected after §G: ReferenceMaster=1, DomainSilver=26, Gold=8 → total 35
-- ============================================================
