# 10 — Bronze Layer

> **Status (updated 2026-06-01):** live source paths verified after DA-first refactor and shared dimension consolidation. `SalesShipment` is no longer active; helper/COGS logic reads `SalesHistory_Enh.v_InvoiceDetailLineLevel`. `ItemBalance` remains the active SC_LH workaround; `PurchaseOrderSnapshot` remains inactive Phase 2. Shared `DimProduct` now uses EL `DimItemMaster` plus `VendorMaster` and `ITBEXT`.

## Source pattern

Inventory Health views read Bronze sources via **OneLake shortcuts** mounted in `SupplyChain_Processing_Warehouse` pointing to `Enterprise_Lakehouse` (Bob hub). No physical Staging_Wrk table is required for the 22 sources that land cleanly.

**Source-path state (verified pyodbc 2026-05-19):**
- 25 EL-ready (22 always-ready + 3 newly loaded by Dhivya 2026-05-18: PoDetail, PoMaster, Logility)
- 2 SC_LH workaround active (ItemBalance, PurchaseOrderSnapshot — EL still missing)
- 5 columns confirmed deprecated (ITBEXT.CRHLD/DLHLD/TOHLD/ATPQT + ITEMBL.PHYOH — `expected_zero` DQ rule, NO reload)
- 3 SC_LH legacy paths to DEPRECATE after view-source-switch (pomaster, podetail_v2, logility_demandfulfillment — superseded by EL Tier 0)

## Source inventory (27 source paths total: 25 EL primary + 2 SC_LH workaround)

### Tier 0 — Enterprise_Lakehouse PRIMARY (25 tables, READY)

| Schema | Table | Rows (verified 2026-05-19) | Used by Silver view | Loaded |
|---|---|---:|---|---|
| `ItemMaster_AFI` | `ITEMBL` | 3,412,490 | v_InventoryCurrent (H3 + B3 filters) | pre-existing |
| `ItemMaster_AFI` | `ITMRVA` | TBD | v_CostCurrent | pre-existing |
| `ItemMaster_AFI` | `ITBEXT` | 3,389,222 | v_ItemMasterExt (MFPUS → UnavailableFlag); ⚠️ 4 cols deprecated zero | pre-existing |
| `MasterData_DW` | `DimItemMaster` | 379K | v_ItemMasterExt (base) | pre-existing |
| `MasterData_DW` | `DimDate` | 21.5K | v_MovementHistory (TRNDT join) | pre-existing |
| `Wholesale_Codis_AFI` | `AshleyWarehouseMaster` | 55 | v_WarehouseExt | pre-existing |
| `Wholesale_DemandPlanning_AFI` | `SupplyPlanDetail` | TBD | v_SupplyPlan | pre-existing |
| `Wholesale_DemandPlanning_AFI` | `DemandForecast` | 12.27M | v_ForecastCurrent (B2 fix) | pre-existing |
| `SalesHistory_AFI` | `InvoiceDetail` | via Mart A Silver: `SalesHistory_Enh.v_InvoiceDetailLineLevel` has 127,418,735 rows | Helpers + COGS read Mart A invoice silver directly; no Mart B `SalesShipment` | pre-existing |
| `Manufacturing_ProductionPlanning_AFI` | `MOMAST` | TBD | v_ManufacturingOrder | pre-existing |
| `Manufacturing_Inventory_AFI` | `IMHIST` | TBD | v_MovementHistory (incremental) | pre-existing |
| `Manufacturing_Inventory_AFI` | `TFRDTL` | TBD | v_HoldingTransfer | pre-existing |
| `Manufacturing_Inventory_AFI` | `TFRHDR` | TBD | v_HoldingTransfer | pre-existing |
| `CustomerOrders_AFI` | `OpenOrderDetail` | 918K | v_AllocatedDemandCandidate (H1 fix) | pre-existing |
| `CustomerOrders_AFI` | `OpenOrderHeader` | TBD | v_AllocatedDemandCandidate | pre-existing |
| `Wholesale_Purchasing_AFI` | `ATPSUM` | TBD | v_AtpWeekEnding (H2 UNPIVOT) | pre-existing |
| **`Wholesale_ProductSourcing_AFI`** | **`PoDetail`** | **21,945,294** | v_PurchaseOrder (B1 fix) | **🆕 Dhivya 2026-05-18 (backfilled from 0 rows)** |
| **`Wholesale_ProductSourcing_AFI`** | **`PoMaster`** | **5,688,132** | v_PurchaseOrder (LEFT JOIN h) — switch from SC_LH | **🆕 Dhivya 2026-05-18 (new table)** |
| `Wholesale_ProductSourcing_AFI` | `Container` | TBD | Phase 2 | pre-existing |
| `Purchasing_AFI` | `VendorMaster` | 86.6K | v_Vendor (NEW) + v_ItemMasterExt | pre-existing |
| `SupplyChain_Enh_1` | `DemandInventorySnapshotDaily` | live via Saturday-derived paths | `InventorySnapshotWeekly`, AWD source mapping (`dinMakeBuyCode`, `dinSource1`) | DA-first active path |
| `Staging_Wrk` | `DemandForecastSnapshotDaily` | live Saturday-derived path | `ForecastSnapshotWeekly` | DA-first active path; replaces stale weekly source |
| `CustomerOrders_AFI` | `WarehouseMaster` | 53 active warehouse codes | (used by ReferenceMaster_Enh.Warehouse already) | pre-existing |
| **`SupplyChain_Enh`** | **`DemandFulfillmentCommonContainer_Logility`** | **38,356,303** | v_LogilityItemStatus + Snapshot — switch from SC_LH | **🆕 Dhivya 2026-05-18 (new table, 53 cols match SC_LH workaround)** |

### Tier 1 — SupplyChain_Lakehouse workaround (2 tables ACTIVE, EL still missing)

| Table | Rows (verified 2026-05-19) | Used by | Status | Action |
|---|---:|---|---|---|
| `dbo.itembalance` | 48,968,574 | **NEW 2026-05-19**: wired via `v_ItemBalanceHistorical` → `InventoryHistory_Enh.ItemBalanceHistorical` materialized (48.97M rows, 5-year history 2021-03-06 → 2026-05-16). Following forecast `_ver2` pattern | EL.Inventory_Enh_History.ItemBalance schema vẫn missing — `df_brz_ItemBalance` đang là primary. Swap source_objects khi Dhivya promote |
| `dbo.purchaseordersnapshot` | 1,997,040,026 ⚠️ 2B | **NEW 2026-05-19**: wired via `v_PurchaseOrderSnapshotHistorical` (registered, is_active=0, defer materialize). Phase 2 PO-as-of feature | EL.SupplyChain_Enh.PurchaseOrderSnapshot vẫn missing. Flip is_active=1 + materialize khi Phase 2 scoped |

**Architectural alignment 2026-05-19**: Following forecast's pattern (4 `_ver2` SC_LH tables wired via Silver views like `v_InvoiceDetailLineLevel`), inventory_health now wires SC_LH workaround sources INTO the 3-tier ETL pipeline (not idle). Benefits:
- KPI historical trend works (Inventory Turns 52M trailing, SLOB, MOS) — 5 years vs 10 weeks via stale alternate
- Phase 2 PO-as-of feature unblockable
- Consistent multi-mart pattern
- DQ rules monitor SC_LH source freshness (alert if df_brz_ItemBalance refresh fails)
- Future EL promote = swap `source_objects` JSON only (no view rewrite)

### Tier 1B — SupplyChain_Lakehouse LEGACY (3 paths to DEPRECATE post-deploy)

These were Aric's local workarounds before EL gained equivalent. Switch view source refs in next ETL release:

| SC_LH legacy path | Replace with EL path | View needs switch |
|---|---|---|
| `dbo.pomaster` (5.68M) | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster` | `v_PurchaseOrder` LEFT JOIN h |
| `dbo.podetail_v2` (21.95M) | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail` (B1 already applied) | `v_PurchaseOrder` main FROM — **already switched** |
| `dbo.logility_demandfulfillment` (38.46M, ~105K extra vs EL) | `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` (38.36M) | `v_LogilityItemStatus` main FROM |

### Tier 2 — Resolution status (verified 2026-05-19 via pyodbc)

| Table | Status 2026-05-19 | Rows | Source | Used by |
|---|---|---:|---|---|
| `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail` | ✅ **LOADED** (Dhivya 2026-05-18) | 21,945,294 | EDW backfill | v_PurchaseOrder (B1) |
| `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster` | ✅ **LOADED** (Dhivya 2026-05-18) | 5,688,132 | EDW load | v_PurchaseOrder (LEFT JOIN h) |
| `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | ✅ **LOADED** (Dhivya 2026-05-18; Dhivya viết tắt thành "DemandFulfilmentCommonContain_Logility.ItemStatus" — thực ra `ItemStatus` là cột trong bảng này) | 38,356,303 | EDW promote | v_LogilityItemStatus + Snapshot |
| `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance` | ⏳ Enterprise schema vẫn missing — **WORKAROUND OK**: `SupplyChain_Lakehouse.dbo.itembalance` via `df_brz_ItemBalance` | 48,968,574 | EDW raw via dataflow | v_InventorySnapshotWeekly |
| `Enterprise_Lakehouse.SupplyChain_Enh.PurchaseOrderSnapshot` | ⏳ Enterprise vẫn missing — **WORKAROUND OK**: `SupplyChain_Lakehouse.dbo.purchaseordersnapshot` via `df_brz_PurchaseOrderSnapshot` | 1,997,040,026 ⚠️ 2B rows | EDW raw via dataflow | Phase 2 PO-as-of |

**Verification queries (2026-05-19):** all 5 row-counts confirmed via pyodbc TDS against Enterprise_Lakehouse SQL endpoint `7woj2wroypauvkpn72b56t46ju-...datawarehouse.fabric.microsoft.com`.

**Column-deprecation finding (Dhivya 2026-05-18, verified 2026-05-19):**
- `ItemMaster_AFI.ITBEXT.CRHLD / DLHLD / TOHLD / ATPQT` — all 4 cols 100% zero across 3,389,222 rows on Enterprise_LH
- `ItemMaster_AFI.ITEMBL.PHYOH` — 100% zero across 3,412,490 rows on Enterprise_LH
- → EDW upstream cũng zero. **Confirmed deprecated**, không cần reload. Action: thêm DQ rule `expected_zero` thay vì alert.

Recent commits addressing these:
- `8683eaeb` — feat: batch-create 4 remaining dataflows via Fabric REST API
- `533fb1c6` — fix: route ITBEXT/ITEMBL dataflows via Lakehouse not EDW
- `b38d4e81` — fix: route 3 dataflows to real EDW schemas (iteration #2)

**Cleanup actions queued** (after deploy verify; destructive actions require explicit approval in the active conversation):
- Candidate cleanup: `df_brz_ITBEXT_Reloaded` + `df_brz_ITEMBL_PHYOH_Reloaded` (column-level deprecation, reload không cứu)
- KEEP `df_brz_ItemBalance` + `df_brz_PurchaseOrderSnapshot` (still primary path)
- Switch `v_PurchaseOrder` source path từ `SupplyChain_Lakehouse.dbo.pomaster` → `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster`
- Switch `v_LogilityItemStatus` source path từ `SC_LH.dbo.logility_demandfulfillment` → `Enterprise_LH.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`

## Source contracts

Each source is referenced from `Meta.AssetRegistry.source_objects` (JSON array). After deploy:
- Run `EXEC Meta.usp_BuildLineage` to generate `Meta.LineageEdge` direct edges
- Run `EXEC Meta.usp_ValidateSourceContract` per asset to flag schema drift

---

## Bronze Readiness Issues — full inventory

> Tổng hợp toàn bộ vấn đề Bronze từ deliverable v1 (`_source_v1/docs/02_QC_REPORT.md`, `_source_v1/docs/03_BRONZE_STATUS.md`, `_source_v1/reference/source_corrections.md`). Chia 4 nhóm: A) chưa load, B) stale, C) logic/column corrections, D) dedupe.

### §A. Chưa load / Không tồn tại trên Enterprise_Lakehouse — RESOLUTION STATUS (verified 2026-05-19)

| # | Bronze table | Status 2026-05-19 | Rows | Action remaining |
|---|---|---|---:|---|
| A1 | `Enterprise.Wholesale_ProductSourcing_AFI.PoDetail` | ✅ **DONE** — Dhivya backfilled 2026-05-18 | 21,945,294 | None — `v_PurchaseOrder` đã đọc Enterprise.PoDetail (B1 fix). |
| A2 | `Enterprise.Wholesale_ProductSourcing_AFI.PoMaster` | ✅ **DONE** — Dhivya loaded 2026-05-18 | 5,688,132 | Switch `v_PurchaseOrder` LEFT JOIN từ `SC_LH.dbo.pomaster` → `Enterprise_LH.Wholesale_ProductSourcing_AFI.PoMaster`. |
| A3 | `Enterprise.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | ✅ **DONE** — Dhivya promoted 2026-05-18 (Dhivya viết tắt thành "DemandFulfilmentCommonContain_Logility.ItemStatus" — `ItemStatus` là cột, không phải bảng) | 38,356,303 | Switch `v_LogilityItemStatus` từ `SC_LH.dbo.logility_demandfulfillment` → Enterprise path. |
| A4 | `Enterprise.Inventory_Enh_History.ItemBalance` | ⏳ **Enterprise vẫn missing** — **WORKAROUND OK**: `df_brz_ItemBalance` đã load `SC_LH.dbo.itembalance` | 48,968,574 | (a) Chase Dhivya promote Enterprise, OR (b) Deploy v1 với SC_LH source — switch sau. |
| A5 | `Enterprise.SupplyChain_Enh.PurchaseOrderSnapshot` | ⏳ **Enterprise vẫn missing** — **WORKAROUND OK**: `df_brz_PurchaseOrderSnapshot` đã load `SC_LH.dbo.purchaseordersnapshot` | 1,997,040,026 ⚠️ | Phase 2 only; defer to backlog. ⚠️ 2B rows — review whether full EDW raw needed hay incremental sufficient. |

**Registry impact**: trong [etl/registry_inserts.sql](etl/registry_inserts.sql):
- A1/A2/A3 → `is_active=1` (Enterprise paths live)
- A4 → `is_active=1` with SC_LH workaround source
- A5 → keep `is_active=0` (Phase 2 only)

**Update 2026-05-19**:
- Dhivya (DE US) confirmed table-level loads cho A1+A2+A3 via Slack 2026-05-18 4:45 PM
- Aric verified row counts via pyodbc 2026-05-19
- Aric workaround dataflows (A4 + A5) verified to have loaded (49M + 2B rows respectively)
- See [_dataflow_drafts/README.md](_dataflow_drafts/README.md)

### §A.1. Column-deprecation finding (NEW 2026-05-19)

Dhivya rows 3+4 confirmed "Source and EDW also having zero for those columns" — verified 2026-05-19 via pyodbc:

| Cột | Bảng | Nonzero rows / total | Status |
|---|---|---:|---|
| `CRHLD` | `ItemMaster_AFI.ITBEXT` | 0 / 3,389,222 | ✅ Confirmed deprecated |
| `DLHLD` | `ItemMaster_AFI.ITBEXT` | 0 / 3,389,222 | ✅ Confirmed deprecated |
| `TOHLD` | `ItemMaster_AFI.ITBEXT` | 0 / 3,389,222 | ✅ Confirmed deprecated |
| `ATPQT` | `ItemMaster_AFI.ITBEXT` | 0 / 3,389,222 | ✅ Confirmed deprecated |
| `PHYOH` | `ItemMaster_AFI.ITEMBL` | 0 / 3,412,490 | ✅ Confirmed deprecated |

**Action**: thêm DQ rule type `expected_zero` (không alert) trong [etl/dq_rules_inserts.sql](etl/dq_rules_inserts.sql). Candidate cleanup for `df_brz_ITBEXT_Reloaded` + `df_brz_ITEMBL_PHYOH_Reloaded` requires explicit approval before any delete operation.

### §B. Stale data (cần refresh pipeline)

| # | Bronze table | Stale duration | Fix đã apply trong v10 | Còn lại |
|---|---|---|---|---|
| B1 | `SupplyChain_Enh_1.DemandForecastSnapshotWeekly` (LastSnap 2024-03-25) | **2.1 năm** | Active flow bypasses it with DA `ForecastSnapshotWeekly` from `Staging_Wrk.DemandForecastSnapshotDaily` Saturday rows | Do not use stale weekly source |
| B2 | `SupplyChain_Enh_1.DemandInventorySnapshotWeekly` | stale legacy source | DA `InventorySnapshotWeekly` uses `DemandInventorySnapshotDaily` Saturday-derived path | Do not use stale weekly source or ItemBalance backup/backfill |

### §C. Logic / Column corrections (đã apply trong views — Track A markers preserved)

| # | Bronze table | Vấn đề | Fix code trong v10 | Code | View |
|---|---|---|---|---|---|
| C1 | `ITEMBL` | KHÔNG có FG filter → 68% rows orphan (chỉ 32% match DimItemMaster) | Add `LEFT(ITCLS,1)='Z' AND RIGHT(ITCLS,1)='K'` → 99.98% match | **H3** | `v_InventoryCurrent` |
| C2 | `ITEMBL` + `PoDetail` | KHÔNG exclude direct-to-customer/RP warehouses | Add `HOUSE/podwarehouse NOT IN ('C','CNW','AF','IOR','C35','55','MAX')` | **B3** | `v_InventoryCurrent`, `v_PurchaseOrder`, `v_WarehouseExt` (flag column) |
| C3 | `ATPSUM` | UNPIVOT references `APWK01-27` nhưng chỉ có `APWK01` (1 col) → compile fail | UNPIVOT chỉ `APAT01-43`; derive `WeekEndingDate = APWK01 + (n-1)*7` | **H2** | `v_AtpWeekEnding` |
| C4 | `OpenOrderDetail` | `ItemAllocationFlag = 1` → 0 rows (giá trị thực là `2`: 901K rows) | Change `= 1` → `= 2` (**Robert sign-off pending**) | **H1** | `v_AllocatedDemandCandidate` |
| C5 | `MOMAST` | OSTAT firm list `('10','40','45')` chỉ là placeholder | Placeholder giữ nguyên — Robert confirm | L3 | `v_ManufacturingOrder` |
| C6 | `DimItemMaster` | KHÔNG có cột `Category` / `Series` như Plan v3 giả định | Rename: `Category → RetailCategoryName`, `Series → SeriesNumber+SeriesName+SeriesDescription` | (data shape) | `v_ItemMasterExt` |
| C7 | `AshleyWarehouseMaster` | KHÔNG có cột `wmaWarehouseName` (29 cols, no name col) | Dùng `wmaWarehouse` làm cả code + name | (data shape) | `v_WarehouseExt` |
| C8 | `InvoiceDetail` | Mart B no longer owns invoice materialization | Reuse Mart A `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly | DA Silver_Check | `AwdHelper`, `LastInvoiceHelper`, `MovementFlagHelper`, `CogsRollingHelper` |
| C9 | `podetail_v2` | Cột `poditem` thực ra là `poditemnum`; `podstatuscode` là VARCHAR (không phải INT) | Rename + TRY_CAST | (data shape) | `v_PurchaseOrder` |
| C10 | `SupplyForecast` (7-col thin: FCST_1_ID/FCST_2_ID/FCST_YR_PRD/FCST_RSLT_QTY/PROMO_LIFT_QTY) | Plan v3 giả định cột chuẩn nhưng schema khác hẳn; semantic của FCST_1_ID/FCST_2_ID không xác nhận business | **B2**: drop entirely, switch sang `DemandForecast` 23-col (fresh, channel-split present) | **B2** | `v_ForecastCurrent` |
| C11 | `DemandInventorySnapshotDaily` | DA requested `dinMakeBuyCode` / `dinSource1` mapping for dependent demand | Active AWD logic maps make/buy + source warehouse from daily snapshot rows | DA Silver_Check | `v_AwdHelper` |
| C12 | `DemandForecastSnapshotDaily` | DA requested Saturday history and channel-collapsed forecast grain | `ForecastSnapshotWeekly` filters Saturday snapshots and SUMs forecast quantities | DA Silver_Check | `v_ForecastSnapshotWeekly` |
| C13 | `DemandForecastSnapshotDaily` | `dfcSnapshot` is the Saturday snapshot date for active path | Use `dfcSnapshot` as `SnapshotDate`; old weekly source not used | DA Silver_Check | `v_ForecastSnapshotWeekly` |

### §D. Dedupe patterns — RECLASSIFIED 2026-05-19 (full-row dup vs grain-conflict)

**Critical distinction** (verified via column-by-column comparison pyodbc 2026-05-19):
- **True dup** = all columns identical → safe to drop any row, ordering doesn't matter
- **Grain conflict** = same key but DIFFERENT metric values → grain definition incomplete; need deterministic tiebreaker that prefers data-bearing row

| # | Bronze table | Grain | Dup count | Type | Evidence | Current view fix | View |
|---|---|---|---:|---|---|---|---|
| D1 | `DemandFulfillmentCommonContainer_Logility` | (Item, Whse, WeekEnding) | **9,128 groups × 2 rows** | ❌ **GRAIN CONFLICT** | 47/53 cols identical; **6 metrics differ** (FirmDemand, Netfcst, ShippableInvQty, ShippableInvAmt, MosofSupply, OnHandAmt). Pattern: 1 data-row + 1 zero-placeholder row. | **FIXED**: `ORDER BY CASE WHEN ShippableInvQty=0 AND FirmDemand=0 THEN 1 ELSE 0 END ASC, StatusChngDate DESC, OnHandAmt DESC, FileDate DESC` | `v_LogilityItemStatus` |
| D2 | `ITMRVA` (Enterprise) | (STID, ITNBR) | 0 at STID='000'; 2 at STID='042' (filtered out) | ✅ True dup (filtered out) | n/a | Keep as-is (defensive) | `v_CostCurrent` |
| D3 | `PoDetail` (Enterprise) | (podordernum, podvendornum, poditemsequence) | **1 group × 2 rows** | ✅ **TRUE 100% DUP** | 53/53 cols identical (verified key `('P0SM242', '612908', 1)`) | Current dedupe OK — `ORDER BY podduedate DESC` deterministic | `v_PurchaseOrder` (line 275-276) |
| D4 | `OpenOrderDetail` | OrderNumber | (unknown — Phase 1 OK) | (no obvious line col) | n/a | `ROW_NUMBER() ORDER BY LoadDate DESC, PromiseDate DESC` (synthetic OrderLine) | `v_AllocatedDemandCandidate` |
| D5 | `TFRDTL` + `TFRHDR` | (DTFRNO, DITNBR) | multi-version | versioning (not bug) | n/a | `ROW_NUMBER() ORDER BY HDLDTE DESC` (latest version) | `v_HoldingTransfer` |

### §D.1. Logility grain-conflict — DE team feedback

Rakeshbalaji (DE US, Slack 2026-05-09): "Root cause of duplicates is unclear (upstream EDW vs ingestion/lakehouse load)". DE team **cannot fix at source** — bug is upstream in Logility export.

**Aric 2026-05-19 root-cause hypothesis** (after column-by-column diff):
- Logility daily export emits 2 rows per (Item, Whse, WeekEnding):
  - Row A: actual data (real FirmDemand/ShippableInvQty/MosofSupply)
  - Row B: zero-placeholder (likely default-initialized record before update merge)
- Both rows have IDENTICAL StatusChngDate, FileDate, ItemStatus, all identity attrs → not distinguishable by any "version" semantic
- Current dedupe ordering by StatusChngDate is undefined for ties — silent buggy behavior

**Verified 9,128 dup groups distribution (2026-05-19 pyodbc probe):**

| Pattern | Count | % | Heuristic outcome |
|---|---:|---:|---|
| 1 data-row + 1 zero-placeholder | 6,786 | 74.3% | CASE picks data row ✅ |
| Both rows zero (no info) | 1,791 | 19.6% | Drop any (CASE ties; tiebreaker by StatusChngDate/OnHandAmt) |
| Both rows have data | 551 | 6.0% | CASE ties; tiebreaker = highest OnHandAmt (proxy for more inclusive view) |

**Plan to fix in v10** (no DE team dependency):
1. `v_LogilityItemStatus` ORDER BY uses 4-tier ranking — **CASE WHEN identifies placeholder by demand-side metrics ONLY** (NOT OnHandQty — that's identity-attribute, always populated on both rows):
   ```sql
   ROW_NUMBER() OVER (
       PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
       ORDER BY
           CASE WHEN COALESCE(ShippableInvQty,0)=0 AND COALESCE(FirmDemand,0)=0 THEN 1 ELSE 0 END ASC,  -- prefer demand-bearing row
           StatusChngDate DESC,                       -- legacy tiebreaker
           COALESCE(OnHandAmt,0) DESC,                -- for "both have data" 6% case
           CAST(FileDate AS DATETIME2) DESC           -- final fallback
   ) AS rn
   ```
2. Add DQ rule **`expected_dup_ratio_max`** (~0.024% = 9,128/38.36M) — alert if dup count grows materially → signals Logility export degradation
3. Add lineage comment in view header: "Source has known grain-conflict (Item/Whse/WeekEnding × actual+placeholder); dedupe prefers demand-bearing row. Re-evaluate if Phase 2 surfaces extra dimension."

**Iteration history (2026-05-19):**
- v1 heuristic used `OnHandQty=0` in CASE → bug: placeholder rows still had OnHandQty ≠ 0 (identity attr) so CASE never fired → still random pick
- v2 (current) heuristic: only ShippableInvQty + FirmDemand in CASE → verified 5/5 sample picks data row correctly

**Risk of remaining alternative dimensions**: explored all 53 cols — none distinguish the 2 rows beyond the 6 differing metrics themselves. If future Logility schema adds a `ScenarioCode` or `ChannelCode`, MUST re-evaluate grain (could be a 4th dim we're collapsing).

### §E. Coverage observations (informational)

| Metric | Value | Note |
|---|---|---|
| `ITEMBL` all items vs `DimItemMaster` match rate | 32% (179K of 558K) | Without FG filter — 68% orphan |
| `ITEMBL` FG-filtered (`ITCLS LIKE 'Z%K'`) vs `DimItemMaster` | **99.98%** (5,672 of 5,673) | H3 fix justification |
| `DimItemMaster.FOBArcPrice` NULL rate | 6.13% (23,441 of 382K) | Acceptable Phase 1 |
| `DimItemMaster.Cubes` NULL rate | 0.0003% (1 of 382K) | ✅ |
| `DimItemMaster.AFIItemStatus` NULL rate | 0% | ✅ |
| `SupplyPlanDetail` distinct snapshot dates | 1 (today only) | Forward 18 weeks data per snapshot |
| `SupplyPlanDetail` SI<0 rows (Revenue at Risk candidates) | 334K (8.6%) | Material for KPI #19 |
| `MOMAST.OSTAT='55'` (closed) | 165,709 (66%) | Excluded by firm filter |
| `MOMAST.OSTAT IN ('10','40','45')` (open candidates) | 91,601 (37%) | Robert sign-off pending |

### §F. Recap counts (updated 2026-05-19)

| Category | Count | Status |
|---|---|---|
| §A. Chưa load — DONE (A1+A2+A3 Dhivya 2026-05-18) | 3 sources | ✅ Enterprise paths live, switch view refs |
| §A. Chưa load — workaround OK (A4 ItemBalance + A5 PurchaseOrderSnapshot) | 2 sources | ⏳ SC_LH dataflow workarounds verified, Enterprise promote pending |
| §A.1. Column deprecation confirmed (CRHLD/DLHLD/TOHLD/ATPQT/PHYOH) | 5 columns | ✅ Add `expected_zero` DQ rule, delete 2 dataflows |
| §B. Stale (DE US pipeline refresh) | 2 sources | B1 fix applied; B2 still reads stale |
| §C. Logic/column corrections (Track A) | 13 fixes | All applied inline in views |
| §D. Dedupe patterns | 5 patterns | All applied via ROW_NUMBER |
| **Total Bronze issues documented** | **25** | per `_source_v1/docs/02_QC_REPORT.md` + `source_corrections.md` |

### §G. Source documents for cross-reference

- [`_source_v1/docs/03_BRONZE_STATUS.md`](_source_v1/docs/03_BRONZE_STATUS.md) — Single source of truth (25 bronze tables, all columns + row counts verified 2026-05-14)
- [`_source_v1/docs/02_QC_REPORT.md`](_source_v1/docs/02_QC_REPORT.md) — 18 bugs (5H + 6M + 7L) including bronze probe evidence
- [`_source_v1/reference/source_corrections.md`](_source_v1/reference/source_corrections.md) — vs Plan v3 assumptions schema corrections
- [`_source_v1/reference/bronze_source_truth.md`](_source_v1/reference/bronze_source_truth.md) — full column inventory per table
- [`_source_v1/04_TRACK_A_FIXES.md`](_source_v1/04_TRACK_A_FIXES.md) — 14 fix log với line refs
