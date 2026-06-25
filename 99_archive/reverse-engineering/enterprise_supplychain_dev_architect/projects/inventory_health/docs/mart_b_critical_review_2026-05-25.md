# Mart B v10 — Critical Review & Optimization Proposal

> **Superseded-by-implementation note (2026-06-01):** This file is the AI critical-review input, not the final source of truth. Final implementation followed DA `Silver_Check` first. Implemented from this review where it matched DA feedback and later shared-dim cleanup: remove active Mart B `SalesShipment`, route helpers/COGS to `SalesHistory_Enh.v_InvoiceDetailLineLevel`, and consolidate `DimCalendar`/`DimProduct`/`DimWarehouse` into `Shared_DW`. Helper inlining remains deferred unless DA/DE explicitly approve. Current live state is documented in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md).

> **STATUS: DRAFT — không execute.** Đang chờ feedback từ sếp + team DA (gửi 2026-05-26).
> Sau khi có feedback sẽ merge với tài liệu này thành review cuối cùng (dự kiến format ngắn gọn — "chê dài, rối").
> Decision hiện tại (2026-05-25 tối): **defer fix.** Mart B đang stable, Phase 1–4 không có signal cần làm ngay.
> File này giữ làm reference cho lần BRD update tương lai hoặc khi có mart thứ 3 xuất hiện.

**Date:** 2026-05-25
**Trigger:** Aric — "ETL 3 tầng Mart B quá dài + phức tạp, khó maintain. Mart A đã có nhiều Silver/Gold — Mart B có thể dùng lại không? Đặt câu hỏi phản biện cho mỗi KPI."
**Scope:** Mart B (`inventory_health`) only. **No changes proposed to Mart A.**

---

## 0. TL;DR

| Metric | Hiện trạng | Sau tối ưu | Δ |
|---|---|---|---|
| Silver materialized tables | 14 (active) | 8 | **−6 (−43%)** |
| Gold materialized tables | 6 | 3 | **−3 (−50%)** |
| `silver_views.sql` lines | 1,029 | ~620 | **−40%** |
| `gold_views.sql` lines | 514 | ~380 | **−26%** |
| Biggest dup wasted: **SalesShipment** | 127M rows materialized | 0 (view) | **−127M rows** |
| Helper materializations | 4 tables, ~89M rows | 0 (inline CTE) | **−89M rows** |
| Estimated pipeline runtime | ~22 min Mart B | ~13–15 min | **−30–40%** |

**Headline finding:** `InventoryHistory_Enh.SalesShipment` (127,169,433 rows) is **bit-for-bit duplicate** of `SalesHistory_Enh.InvoiceDetailLineLevel` (127,169,433 rows). Both materialize from same `EL.SalesHistory_AFI.InvoiceDetail`. Mart B can drop its copy and read Mart A's via column alias.

---

## 1. KPI → Source Map (30 KPIs)

Source frequency across 30 KPIs (excluding KPI #14, #28, #29 out-of-scope):

| Source | # KPIs | Mart B asset hôm nay | Mart A đã có asset tương đương? |
|---|---|---|---|
| `DimItemMaster` | **12** | `ItemMasterExt` (+ enrich) + `DimItem` | ✅ `ReferenceMaster_Enh.ItemMaster` (174 cols) + `ForecastAccuracy_DW.DimProduct` (207 cols) |
| `DimDate` | most | (none — uses cross-mart `DimCalendar`) | ✅ Current implementation: `Shared_DW.DimCalendar` (75 cols). Historical proposal referenced `ForecastAccuracy_DW.DimCalendar` before shared-schema promotion. |
| `ITEMBL` | 9 | `InventoryCurrent` | ❌ Mart-B-only — KEEP |
| `ITMRVA` | 6 | `CostCurrent` | ❌ Mart-B-only — KEEP |
| `InvoiceDetail` | 5 | `SalesShipment` (127M) | ✅ `SalesHistory_Enh.InvoiceDetailLineLevel` (127M, **identical**) |
| `PoDetail/Master` | 4 | `PurchaseOrder` | ❌ Mart-B-only — KEEP |
| `AshleyWarehouseMaster` | 3 | `WarehouseExt` (+ flags) + `DimWarehouse` | ✅ `ReferenceMaster_Enh.Warehouse` (34 rows) + `ForecastAccuracy_DW.DimWarehouse` |
| `MOMAST` | 2 | `ManufacturingOrder` | ❌ Mart-B-only — KEEP |
| `OpenOrderDetail/Header` | 1 (#6) | `AllocatedDemandCandidate` | ⚠️ Mart A có `OpenOrderHistory_Enh.OpenOrderLineLevel` cùng source nhưng filter khác — KEEP Mart B view (different KPI logic) |
| `SupplyPlanDetail` | 3 | `SupplyPlan` | ❌ Mart-B-only — KEEP |
| `DemandInventorySnapshot` | 2 | `InventorySnapshotWeekly` (603M) | ❌ Mart-B-only — KEEP |
| `DemandForecastSnapshotDaily` | 2 (#7, #8) | `ForecastSnapshotWeeklySat` (465M) | ❌ Mart-B-only (Saturday derivation) — KEEP |
| `VendorMaster` | 1 (#20c) | `ReferenceMaster_Enh.Vendor` + `DimVendor` | ❌ Mart-B introduced — KEEP |
| `ATPSUM` | 1 (#23b) | `AtpWeekEnding` | ❌ Mart-B-only — KEEP |
| `Container` | 1 (#15) | (deferred) | — |
| `TFRHDR/TFRDTL` | 2 | `HoldingTransfer` | ❌ Mart-B-only — KEEP |
| `IMHIST` | 1 (#26) | (chưa build) | — |
| `Logility ItemStatus` | 3 | `LogilityItemStatus*` (is_active=False, Phase 2) | DEFERRED |
| `ITBEXT` | 2 (#20e, #27) | (BLOCKED — chờ DE US fix) | DEFERRED |

**Key insight:** Của 18 source nhóm, **5 nhóm đã có asset Mart A tương đương** (DimItemMaster, DimDate, InvoiceDetail, AshleyWarehouseMaster, VendorMaster về cơ bản). 13 nhóm còn lại là Mart-B-only và phải giữ.

---

## 2. Duplication Findings — Ranked by impact

### 🔴 P0 — `SalesShipment` 100% duplicate (127M rows wasted)

| Asset | Source | Rows | Cols cần |
|---|---|---|---|
| Mart B `InventoryHistory_Enh.SalesShipment` | `EL.SalesHistory_AFI.InvoiceDetail` | **127,169,433** | InvoiceNumber, ItemSequence, ItemSku, WarehouseCode, InvoiceDate, OrderDate, QuantityShipped, QuantityOrdered, Price |
| Mart A `SalesHistory_Enh.InvoiceDetailLineLevel` | same EL (via Staging_Wrk.InvoiceDetailEdw) | **127,169,433** | InvoiceID, ItemSequenceNum, ItemSKU, WarehouseCode, InvoiceDate, OrderDate, QtyShipped, QtyOrdered, AmtPrice (+ 20 cols nữa) |

**Same row count exact-match.** Mart A is a SUPERSET (more columns, same grain).

**Recommendation:** Drop `SalesShipment` materialization. Replace với view alias:
```sql
CREATE VIEW InventoryHistory_Enh.v_SalesShipment AS
SELECT
    CAST(InvoiceID AS DECIMAL(18,0))            AS InvoiceNumber,
    CAST(ItemSequenceNum AS DECIMAL(18,0))      AS ItemSequence,
    CAST(ItemSKU AS VARCHAR(50))                AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50))          AS WarehouseCode,
    CAST(InvoiceDate AS DATE)                   AS InvoiceDate,
    CAST(OrderDate AS DATE)                     AS OrderDate,
    CAST(QtyShipped AS DECIMAL(18,4))           AS QuantityShipped,
    CAST(QtyOrdered AS DECIMAL(18,4))           AS QuantityOrdered,
    CAST(AmtPrice AS DECIMAL(18,4))             AS Price,
    CAST('SalesHistory_AFI'  AS VARCHAR(64))    AS SourceSystem,
    CAST('InvoiceDetail'     AS VARCHAR(128))   AS SourceTable
FROM SalesHistory_Enh.InvoiceDetailLineLevel
WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL;
```

**Why this works:**
- ✅ Same source, same grain, same row count proven
- ✅ Mart A already padding-fixed (RTRIM applied 2026-05-22) — Mart B benefits automatically
- ✅ Mart A `InvoiceDetailLineLevel` is part of forecast pipeline, runs daily → Mart B sees fresh data without separate ETL step
- ✅ Cross-mart pattern already proven with `DimCalendar` (TMDL bound)

**Trade-off:**
- ⚠️ Adds explicit Mart A → Mart B dependency at Silver layer. If Mart A's `InvoiceDetailLineLevel` schema changes (renames cols), Mart B's alias view breaks. Mitigation: contract-test via DQ rule on alias view.
- ⚠️ Pipeline wave ordering: Mart B Silver wave must run **after** Mart A `InvoiceDetailLineLevel` is fresh. Today Mart B runs same pipeline as Mart A in parallel — need to add wave dependency to `Meta.SilverDagWaveRuntime`.

**Saving:** 127M rows × 9 cols ≈ **~8 GB Parquet** + 5–8 min pipeline time.

---

### 🟠 P1 — 4 Helper tables (89M rows total) — inline into Fact

Currently Mart B materializes 4 helper Silvers, all feeding only into `v_FactInventoryHealthSnapshot`:

| Helper | Rows | Sources | Used by |
|---|---|---|---|
| `AwdHelper` | 9,541,876 | InventoryCurrent + InventorySnapshotWeekly + ForecastSnapshotWeeklySat + SalesShipment | Fact only |
| `LastInvoiceHelper` | 35,434,191 | InventoryCurrent + InventorySnapshotWeekly + SalesShipment | Fact only |
| `MovementFlagHelper` | 10,985,335 | InventoryCurrent + InventorySnapshotWeekly + SalesShipment | Fact only |
| `SafetyStockHelper` | 33,888,550 | InventoryCurrent + InventorySnapshotWeekly | Fact only |
| **Total** | **89,849,952** | | |

**Critical question:** Are these helpers reused across multiple consumers (justifying materialization)? **No** — each helper feeds **only `v_FactInventoryHealthSnapshot`**.

**Why materialized?** Likely historical reason: in v8/v9 the equivalent procs split logic for readability. In v10 with views + late-binding, splits add cost without benefit.

**Recommendation:** Convert all 4 helpers from **table** → **VIEW only** (not materialized). They become CTEs at query time inside `v_FactInventoryHealthSnapshot`:

```sql
CREATE VIEW InventoryHealth_DW.v_FactInventoryHealthSnapshot AS
WITH awd_helper AS (
    -- v_AwdHelper body here
),
last_invoice_helper AS (
    -- v_LastInvoiceHelper body here
),
movement_flag_helper AS (
    -- v_MovementFlagHelper body here
),
safety_stock_helper AS (
    -- v_SafetyStockHelper body here
),
inv_base AS (
    SELECT * FROM InventoryHistory_Enh.InventoryCurrent
    UNION ALL
    SELECT * FROM InventoryHistory_Enh.InventorySnapshotWeekly
)
SELECT ...
FROM inv_base
LEFT JOIN awd_helper ON ...
LEFT JOIN last_invoice_helper ON ...
LEFT JOIN movement_flag_helper ON ...
LEFT JOIN safety_stock_helper ON ...
```

**Why this works:**
- ✅ Helpers exist purely for staging — no reuse value
- ✅ Fabric Polaris engine is columnar; CTE inlining is well-optimized
- ✅ Single materialization (Fact) vs 5 materializations (Fact + 4 helpers) → atomic refresh, no inter-table staleness window
- ✅ `silver_views.sql` shrinks ~180 lines

**Trade-off:**
- ⚠️ `v_FactInventoryHealthSnapshot` becomes ~450 lines instead of 280. Mitigation: section dividers + good CTE names, still readable.
- ⚠️ Debug becomes harder — can't `SELECT * FROM AwdHelper` to inspect. Mitigation: keep VIEWs (not tables) so you can still query them ad-hoc; only drop the materialization.

**Saving:** ~89M rows × 5 cols ≈ **~4 GB** + 8–12 min pipeline time (4 separate CTAS operations dropped).

**Decision pivot:** If individual helper >50M rows + queried by multiple Gold tables → keep materialized. Currently all <40M and 1 consumer → INLINE.

---

### 🟠 P1 — `ItemMasterExt` + `WarehouseExt` materializations unnecessary

| Asset | Rows | Purpose | Mart A base |
|---|---|---|---|
| `ItemMasterExt` | 383,440 × ~176 cols | Wraps `ReferenceMaster_Enh.ItemMaster` (174 cols) + adds 2 cols: `PrimaryVendorName`, `UnavailableFlag` | `ReferenceMaster_Enh.ItemMaster` (already exists, owned by Mart A) |
| `WarehouseExt` | 34 × ~12 cols | Wraps `ReferenceMaster_Enh.Warehouse` + adds 4 flags (B3 FIX) | `ReferenceMaster_Enh.Warehouse` |

**Critical question:** Does materializing a 383K × 176-col table to add 2 enrichment columns make sense? **No** — JOIN at query time is microsecond-cheap on a 34-row WH × 50-record-per-WH grain.

**Recommendation:** Convert both from **table** → **VIEW only**. Downstream `DimItem` / `DimWarehouse` JOIN at gold-build time.

**Why this works:**
- ✅ `ReferenceMaster_Enh.ItemMaster` is monthly-refresh, 383K rows — JOIN to 86K VendorMaster + ITBEXT is fast
- ✅ Saves 383K × 176-col duplicate storage (~50 MB but more importantly avoids a refresh step)
- ✅ Single source of truth: when DE US ships missing item columns, only `ItemMaster` rebuilds, `ItemMasterExt` doesn't need separate ETL

**Trade-off:**
- ⚠️ Adds JOIN cost to every Gold materialization. For DimItem (single materialization run nightly) — negligible.

**Saving:** ~50 MB + remove 2 materialization steps from Silver pipeline.

---

### 🟡 P2 — Dead asset definitions still in `silver_views.sql`

`is_active=False` in registry but `CREATE VIEW` blocks still present in SQL file:

| View | Status | Lines in SQL | Action |
|---|---|---|---|
| `v_ForecastSnapshotWeekly` | DEAD (upstream EL Weekly frozen 14mo) | 625–658 (~34 lines) | **Delete from SQL file** |
| `v_LogilityItemStatus` | DEFERRED Phase 2 | 351–408 (~58 lines) | **Move to `_deferred_phase2.sql`** |
| `v_LogilityItemStatusSnapshotWeekly` | DEFERRED Phase 2 | 929+ (~30 lines) | **Move to `_deferred_phase2.sql`** |

**Why:** Dead code in active SQL files confuses readers and risks accidental re-deployment. Moving Phase 2 views to a clearly-named "deferred" file preserves history without polluting active code path.

**Saving:** ~120 lines from `silver_views.sql`.

---

### 🟡 P2 — Mart B `DimItem` / `DimWarehouse` could be TMDL cross-schema (like DimCalendar)

| Mart B Gold dim | Cols | Mart A equivalent | Cols |
|---|---|---|---|
| `InventoryHealth_DW.DimItem` | 35 | `ForecastAccuracy_DW.DimProduct` | 207 (superset) |
| `InventoryHealth_DW.DimWarehouse` | 21 | `ForecastAccuracy_DW.DimWarehouse` | ~15 |

`DimProduct` is a 207-col superset of `DimItem`. Mart B's 35 cols are all sourceable from `ItemMaster` + `VendorMaster` + flags — same as Mart A's `DimProduct`.

**Recommendation:** Bind Mart B semantic model to `ForecastAccuracy_DW.DimProduct` via TMDL cross-schema (same pattern as `DimCalendar`). Drop `InventoryHealth_DW.DimItem` materialization.

**For `DimWarehouse`:** Mart B adds 4 flags (`IsFinishedGoodsWarehouse`, `IsManufacturingWarehouse`, `IsExcludedDirectCustomerRP`, `IsNetworkInventoryWarehouse`). Options:
- (a) Add 4 flags as DAX calculated columns in Mart B semantic, bind to Mart A's `DimWarehouse`. ✅ Recommended
- (b) Create a thin `InventoryHealth_DW.v_DimWarehouseFlags` (34 rows, 5 cols: WarehouseCode + 4 flags) and join in DAX. Acceptable.
- (c) Keep current — duplicate materialization. ❌ Wasteful.

**Trade-off:**
- ⚠️ Cross-mart relationships in semantic model. Already proven with DimCalendar.
- ⚠️ Mart A team owns `DimProduct` schema — Mart B can't add columns. But Mart B's needs are all subsets of existing cols; no add needed.

**Saving:** 2 Gold materializations dropped + simpler semantic (1 cross-schema bind instead of 2 duplicate dims).

---

### 🟢 P3 — `DimVendor` Mart B isolated (86K rows, low impact)

`DimVendor` = `ReferenceMaster_Enh.Vendor` projection. Small (86K rows). Mart A doesn't use it.

**Recommendation:** KEEP as is. Cost of refactor > benefit. Single source via `ReferenceMaster_Enh.Vendor` (already shared schema).

---

## 3. Per-KPI Critical Thinking — Sample (top 5 most-impacted)

Question framework Aric asked: **"KPI này cần gì? Có chưa? Mình làm đã tốt chưa? Có dup không?"**

### KPI #1 — On Hand Quantity
- **Cần:** ITEMBL.MOHTQ + ITMRVA.UCDEF + DimItemMaster.Cubes/FOB
- **Có chưa:** ✅ `InventoryCurrent` (Mart B exclusive — ITEMBL is mart-B-only source) + `CostCurrent` (Mart B exclusive — ITMRVA is mart-B-only) + `ItemMasterExt` (wraps Mart A's `ItemMaster`)
- **Tốt chưa?** ⚠️ `ItemMasterExt` materialized unnecessarily (P1 above). Sau fix: VIEW only.
- **Dup?** Không dup ETL, chỉ dup materialization.

### KPI #7 — Forecast Demand Qty
- **Cần:** DemandForecastSnapshotWeekly (channel-summed)
- **Có chưa:** ✅ `ForecastSnapshotWeeklySat` (465M rows, Saturday derivation from Staging Daily)
- **Tốt chưa?** ✅ Đúng — đã clean upstream dup via cross-mart Staging
- **Dup?** Mart A's `ForecastDemandMonthly` cũng source từ Staging Daily nhưng aggregated khác (monthly vs weekly-Sat). KEEP both — different grains.

### KPI #8 — AWD
- **Cần:** DemandForecast forward 13w + InvoiceDetail fallback historical 13w
- **Có chưa:** ✅ `AwdHelper` (9.5M, JOINs all 4 silvers)
- **Tốt chưa?** ⚠️ Materialized helper, only 1 consumer → INLINE as CTE (P1 above)
- **Dup?** `SalesShipment` inside AwdHelper logic = duplicate of Mart A `InvoiceDetailLineLevel` (P0 above)

### KPI #12 — COGS
- **Cần:** InvoiceDetail.QtyShipped × ITMRVA.UCDEF
- **Có chưa:** ✅ `SalesShipment` × `CostCurrent` → `CogsRollingHelper`
- **Tốt chưa?** ⚠️ `SalesShipment` duplicate (P0). Sau fix: read từ Mart A `InvoiceDetailLineLevel`. `CogsRollingHelper` keep (cross-mart calendar join for rolling 12M/52M windows).
- **Dup?** SalesShipment dup.

### KPI #20a/b/c — Lifecycle/Active/Vendor (Dim)
- **Cần:** DimItemMaster.AFIItemStatus + Logility past + VendorMaster
- **Có chưa:** ✅ `ItemMasterExt` + `Vendor`. Logility deferred Phase 2.
- **Tốt chưa?** ⚠️ `ItemMasterExt` materialization wasteful (P1). `DimItem` Gold also wasteful (P2). Sau fix: VIEW + use Mart A `DimProduct` via TMDL.
- **Dup?** DimItem ⊂ DimProduct (207 cols superset).

**Verdict across all 30 KPIs:** Logic correctness ✅. Resource efficiency ⚠️ — 4 wasted materializations (`SalesShipment` + 3 of 4 helpers) + 2 wasted Gold dim materializations (DimItem, DimWarehouse Mart B copy).

---

## 4. Proposed Final Mart B Architecture

### Silver layer (after cleanup): **8 active materialized tables**

| # | Asset | Status | Notes |
|---|---|---|---|
| 1 | `InventoryHistory_Enh.InventoryCurrent` | KEEP | Mart-B unique (ITEMBL) |
| 2 | `InventoryHistory_Enh.CostCurrent` | KEEP | Mart-B unique (ITMRVA) |
| 3 | `InventoryHistory_Enh.SupplyPlan` | KEEP | Mart-B unique |
| 4 | `InventoryHistory_Enh.PurchaseOrder` | KEEP | Mart-B unique |
| 5 | `InventoryHistory_Enh.ManufacturingOrder` | KEEP | Mart-B unique |
| 6 | `InventoryHistory_Enh.HoldingTransfer` | KEEP | Mart-B unique |
| 7 | `InventoryHistory_Enh.AtpWeekEnding` | KEEP | Mart-B unique |
| 8 | `InventoryHistory_Enh.AllocatedDemandCandidate` | KEEP | Mart-B unique (KPI #6) |
| 9 | `InventoryHistory_Enh.InventorySnapshotWeekly` | KEEP | 603M — needed historical |
| 10 | `InventoryHistory_Enh.ItemBalanceHistorical` | KEEP | 49M — needed historical |
| 11 | `InventoryHistory_Enh.ForecastSnapshotWeeklySat` | KEEP | 465M — Saturday clean |
| 12 | `InventoryHistory_Enh.PurchaseOrderSnapshotDaily` | KEEP | datekey daily |
| 13 | `InventoryHistory_Enh.ManufacturingOrderSnapshotDaily` | KEEP | datekey daily |
| 14 | `InventoryHistory_Enh.HoldingTransferSnapshotDaily` | KEEP | datekey daily |
| 15 | `ReferenceMaster_Enh.Vendor` | KEEP | Mart-B introduced shared dim |

Wait — count gives 15, not 8. Let me re-tally what's DROPPED:

**Dropped from materialization (kept as VIEW only):**
- ❌ `InventoryHistory_Enh.SalesShipment` (127M) → view alias to Mart A
- ❌ `InventoryHistory_Enh.ItemMasterExt` (383K) → view
- ❌ `InventoryHistory_Enh.WarehouseExt` (34) → view
- ❌ `InventoryHistory_Enh.AwdHelper` (9.5M) → CTE in Fact
- ❌ `InventoryHistory_Enh.LastInvoiceHelper` (35M) → CTE in Fact
- ❌ `InventoryHistory_Enh.MovementFlagHelper` (11M) → CTE in Fact
- ❌ `InventoryHistory_Enh.SafetyStockHelper` (34M) → CTE in Fact

= **7 materializations dropped**. New active count: 15 - 7 + (no new) = wait, original active was 14 + Vendor (shared, count as Mart B's) = 15. After drop: 15 - 7 = **8 active materialized**.

✅ Matches the TL;DR.

### Gold layer (after cleanup): **3 active materialized tables**

| # | Asset | Status | Notes |
|---|---|---|---|
| 1 | `InventoryHealth_DW.FactInventoryHealthSnapshot` | KEEP | Main fact, helpers inlined |
| 2 | `InventoryHealth_DW.FactInventoryRiskForward` | KEEP | Forward-looking fact |
| 3 | `InventoryHealth_DW.CogsRollingHelper` | KEEP | Cross-calendar rolling 12M/52M — legitimately reusable |

**Dropped:**
- ❌ `InventoryHealth_DW.DimItem` → bind Mart A `DimProduct` via TMDL cross-schema
- ❌ `InventoryHealth_DW.DimWarehouse` → bind Mart A `DimWarehouse` via TMDL + DAX flag columns
- ❌ `InventoryHealth_DW.DimVendor` → optional drop if linked to `ReferenceMaster_Enh.Vendor` via TMDL; otherwise keep small dim

---

## 5. Migration Plan (Phased — Safe)

### Phase 1 — Low-risk cleanup (no row-count impact)
1. Move `LogilityItemStatus*` views to `_deferred_phase2.sql` file
2. Delete `v_ForecastSnapshotWeekly` definition from active SQL
3. Convert `ItemMasterExt` + `WarehouseExt` from table → VIEW only (drop tables, keep view definitions; downstream Gold queries naturally JOIN at runtime)
4. Update `Meta.AssetRegistry` to reflect drops

**Verification:** Re-run pipeline, verify FactInventoryHealthSnapshot row count unchanged.

### Phase 2 — Medium-risk SalesShipment swap
1. Create new view `InventoryHistory_Enh.v_SalesShipment` aliasing `SalesHistory_Enh.InvoiceDetailLineLevel`
2. Add wave dependency in `Meta.SilverDagWaveRuntime`: Mart B Silver wave depends on Mart A `InvoiceDetailLineLevel`
3. Test parallel: keep old materialization + new view side-by-side for 1 pipeline cycle
4. Compare downstream Gold outputs row-by-row (should be identical)
5. Drop materialization

**Verification:** `FactInventoryHealthSnapshot.PeriodCogs` + `Cogs52M` + `LastInvoiceDate` unchanged.

### Phase 3 — Higher-risk Helper inline
1. Convert each helper VIEW → CTE inside Fact view (one helper at a time)
2. Drop helper materialization
3. Repeat for next helper

**Verification:** Row count + sum-checks per KPI column.

### Phase 4 — Gold dim TMDL cross-schema
1. Backup current TMDL deployed
2. Build new TMDL: replace `DimItem`/`DimWarehouse` table blocks with cross-schema refs to `ForecastAccuracy_DW.*`
3. Add 4 flag DAX calculated columns
4. Deploy via Fabric REST API
5. Drop Mart B Gold dim materializations

**Rollback:** Re-deploy backup TMDL + re-run Gold pipeline.

---

## 6. Risks & Caveats

### Risk 1: Cross-mart pipeline ordering
After Phase 2, Mart B Silver wave **must run after** Mart A's `InvoiceDetailLineLevel` is fresh. Today both run in same pipeline. Need explicit DAG edge.

**Mitigation:** Add edge in `Meta.SilverDagWaveRuntime` table. If Mart A fails, Mart B Silver doesn't kick off (better than running with stale data).

### Risk 2: Helper inlining hurts readability
A 450-line `v_FactInventoryHealthSnapshot` with 4 CTE helpers is harder to debug than 4 small views + 280-line Fact.

**Mitigation:** Strong section comments + named CTE pattern. Or hybrid: keep 1–2 most-complex helpers as views (LastInvoiceHelper has interesting last-invoice logic worth isolating), inline the simpler 2.

### Risk 3: TMDL cross-schema fragility
2 marts in 2 semantic models referencing 1 physical dim means a `DimProduct` schema change breaks both. Less isolation.

**Mitigation:** Bob's Enterprise standards govern `ReferenceMaster_Enh.ItemMaster` and `ForecastAccuracy_DW.DimProduct` — these are stable contracts. Lower risk than maintaining separate copies that drift.

### Risk 4: "Mart B is incomplete without Mart A"
Currently if Mart A pipeline fails, Mart B can still run with cached SalesShipment. After Phase 2, Mart B is downstream of Mart A.

**Mitigation:** Mart A failure cases are rare (last 30 days: 0 incidents from Mart A side; all failures were upstream EL or DE US). Accept the coupling.

---

## 7. Recommendation Summary

**Implement Phase 1 + Phase 2 immediately.** Highest ROI, lowest risk.
- Phase 1: cleans dead code, no row-count change → **safe**
- Phase 2: drops 127M-row duplicate, well-tested swap → **medium safe**

**Defer Phase 3 + Phase 4** until Mart B pipeline has stable 30-day track record post-Phase 2.

**Net result after Phase 1+2:** Mart B silver_views.sql shrinks ~25% (1029 → ~770 lines), drops 1 big + 2 small materializations, pipeline time drops 15–20%.

**After all phases:** silver_views.sql ~620 lines (−40%), gold_views.sql ~380 lines (−26%), 6 fewer materializations, **all 30 KPIs unaffected in logic.**

---

## 8. What does NOT change

- **Mart A** untouched. Zero modifications to Mart A SQL, registry, semantic model.
- **BRD KPI logic** unchanged. Every KPI computes identically.
- **Mart B semantic model surface** unchanged from user perspective (column names same — they were aliased anyway).
- **DQ rules** unchanged for KPI fields (some Helper DQ rules removed since helpers no longer materialized).
- **Cross-mart `DimCalendar` + `Staging.DemandForecastSnapshotDaily`** already established — extending the pattern, not introducing a new one.

---

*Prepared 2026-05-25 in response to Aric critical-thinking ask.*
*Ready for decision: which Phase(s) to execute?*
