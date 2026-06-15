# Open Questions — inventory_health mart

> **Status (updated 2026-05-22 evening):** 3 Robert sign-offs ⏳ (H1/H5/M3) + 1 NEW Robert Phase 2 ask ⏳ (Logility past-tracking) + 1 Bob architecture Q resolved (DimCalendar consolidated) + ~~4 DE US loads~~ → 3 done + 1 workaround OK + 1 deferred Phase 2 + **1 NEW critical finding for DE US** (Daily/Weekly forecast snapshot quality).
>
> **2026-05-22 evening cleanup** (continued from morning DimDate consolidation):
> - **NEW layer** `Staging_Wrk.DemandForecastSnapshotDaily` (cross-mart cleaned Bronze materialization)
>   - 5.53B rows materialized via ROW_NUMBER() = 1 dedupe (raw EL 5.89B → -6%)
>   - Insulates downstream marts from upstream Logility row-dup x16 bug (2025+)
> - **Mart A** `ForecastHistory_Enh.v_ForecastDemandMonthly`: source EL.Daily → Staging_Wrk.DemandForecastSnapshotDaily (clean)
> - **Mart B NEW** `InventoryHistory_Enh.ForecastSnapshotWeeklySat` (replaces Monday-based ForecastSnapshotWeekly):
>   - Saturday filter from Staging_Wrk.DemandForecastSnapshotDaily
>   - 465M rows materialized (vs 153M old Weekly — 3x for 160 Saturdays vs 56 Mondays)
>   - Matches BRD "week ending Saturday" requirement
> - **AwdHelper** source swapped: ForecastSnapshotWeekly → ForecastSnapshotWeeklySat
> - **Old ForecastSnapshotWeekly** deactivated (is_active=0) — upstream EL.Weekly DEAD since 2024-03-25 (~14 months)
> - **Resilient**: dedupe layer idempotent — if DE US fixes upstream dup, no harm; pipeline keeps working.
>
> **2026-05-22 cleanup** (post-lineage audit on Streamlit):
> - **DROPPED 3 dead assets** — `DimRuleVersion` (Gold over-engineering — Aric decision), `v_MovementHistory` + `v_ForecastCurrent` (Silver views tagged orphan in Option B refactor 2026-05-21; never wired into Fact)
> - **DEACTIVATED 1 Phase 2** — `LogilityItemStatusSnapshotWeekly` (is_active=0; awaits Robert sign-off below as Q5)
> - **Phase 1 KPI coverage maintained**: 26/30 (no KPI lost — dead assets had 0 downstream consumers)

---

## §A. Robert sign-offs (3 critical + 1 new Phase 2)

Email draft ready in `_source_v1/05_NEXT_STEPS.md` Section "Track D". Send to Robert, cc team lead.

### Q1 — H1: ItemAllocationFlag value

`Wholesale_OrderManagement_AFI.OpenOrderDetail.ItemAllocationFlag` probe results:
- `0` → 16,802 rows
- `2` → 901,411 rows
- (value `1` does NOT exist)

Original ETL filtered `= 1` → 0 rows. Fix: changed to `= 2`. **Question for Robert**: is "Allocated" semantically `= 2`, or is there another valid value? Affects AllocatedDemandQty on FactInventoryHealthSnapshot.

**Where in v10**: [etl/silver_views.sql:v_AllocatedDemandCandidate](etl/silver_views.sql) — comment `H1 FIX`.

### Q2 — H5: WeekFourFlag interpretation

BRD §6.3 Revenue at Risk: "At Week Four Ending: [SINegQty] × [FOBPrice]". Two interpretations:
- **(A) Exact** — single week, week-ending = today + 28 days (Saturday rounding). Current implementation.
- **(B) Range** — 4 weeks forward (W1+W2+W3+W4 = 4 weeks). Would inflate Revenue at Risk ~4×.

**Where in v10**: [etl/gold_views.sql:v_FactInventoryRiskForward](etl/gold_views.sql) — comment `H5 FIX`.

### Q3 — M3: COGS rolling grain (52M vs 52W)

BRD says "52 weeks trailing COGS" for KPI #22 Inventory Turns. Implementation: monthly grain `ROWS BETWEEN 51 PRECEDING` → 52 months (~4.3 yr), not 52 weeks (~1 yr).

Options:
- **(A) Keep 52M** (current) — label measure clearly "COGS 52M Trailing"
- **(B) Rewrite 52W** — rebuild CogsRollingHelper at weekly grain (Saturday week-ending), add FiscalWeekYear join column, accept ~30 min extra ETL time

**Where in v10**: [etl/gold_views.sql:v_CogsRollingHelper](etl/gold_views.sql) + [semantic/Measures_DAX.dax](semantic/Measures_DAX.dax) + [semantic/SemanticModel.tmdl](semantic/SemanticModel.tmdl) — all marked `M3 FIX`.

### Q5 — NEW 2026-05-22: Logility past-status tracking (Phase 2 conditional)

Per Excel `Source_to_KPI` sheet: `DemandFulfilmentCommonContain_Logility.ItemStatus` serves **3 Phase 2 KPIs**:
- **#17** Inactive Item Logic (past-tracking part — current served via `DimItemMaster.AFIItemStatus`)
- **#18** SLOB (past-status part)
- **#20a** Lifecycle Status (past tracking)

**Decision made 2026-05-22 (post-lineage audit)**: deactivated `LogilityItemStatusSnapshotWeekly` (is_active=0) because:
1. 0 Gold view / DAX measure / FK relationship consumes it (orphan)
2. 38M base rows weekly snapshot = significant compute
3. Phase 1 KPI #17/#18/#20a current-state path via `DimItemMaster.AFIItemStatus` works fine
4. Excel note: "P2 conditional, chờ Robert chốt past tracking có cần"

**Question for Robert**: Do we need item-status PAST tracking (week-by-week historical) for KPI #17/#18/#20a in Phase 2, OR is current-state status sufficient?
- **(A)** YES, need past tracking → reactivate `LogilityItemStatusSnapshotWeekly` + wire into Fact via new RuleVersion/SnapshotDate join
- **(B)** NO, current-state sufficient → drop the Phase 2 scaffold entirely (clean repo)

**Where in v10**: [etl/silver_views.sql:v_LogilityItemStatus](etl/silver_views.sql) + [etl/silver_views.sql:v_LogilityItemStatusSnapshotWeekly](etl/silver_views.sql) — both annotated `[PHASE 2 DEACTIVATED 2026-05-22]`.

### Q6 — NEW 2026-05-22 PM: DemandForecast Daily/Weekly upstream quality (DE US action)

Probe results on `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotDaily` (5.89B rows) + `DemandForecastSnapshotWeekly` (306M rows):

**Finding 1 — Weekly DEAD upstream**:
- Weekly max snapshot = `2024-03-25` (~14 months stale)
- Inv_health Silver `ForecastSnapshotWeekly` (Monday-source) was reading this dead source
- **Workaround applied 2026-05-22**: replaced with `ForecastSnapshotWeeklySat` derived from Daily filtered Saturday
- DE US action: investigate why Weekly load stopped March 2024 (Logility job? EL pipeline?)

**Finding 2 — Daily row-dup x16 from Q1 2025 onwards**:
- Q1 2023 → Q1 2024: clean grain
- Q2 2024: dup leak starts (mild, 2x)
- **Q1 2025: explosion** to 8x, peaking **Q4 2025 at 27x** (max dup factor)
- Q4 2025 avg ratio 6.6x — `SUM(dfcResultantForecast)` inflated **~6.6× across all Daily 2025+ data**
- Cause: TRUE row-level duplicates — every column 100% identical in dup bucket
- Sample bucket: B1323-53 / ECR / 202709 / 2025-12-15 / HSLIC / M / H had 16 identical rows
- DE US action: investigate Logility upstream write behavior — appears to write N identical rows per snapshot from Q1 2025
- **Workaround applied 2026-05-22**: `Staging_Wrk.v_DemandForecastSnapshotDaily` applies `ROW_NUMBER() OVER (full grain) = 1` dedupe → 5.89B raw → 5.53B clean
- Idempotent: if DE US fixes upstream dup, our dedupe is no-op (no harm to revert)

**Where in v10**: [forecast/etl/staging_ddl.sql:v_DemandForecastSnapshotDaily](../forecast/etl/staging_ddl.sql)

---

## §B. DE US team — bronze loads — RESOLUTION (updated 2026-05-19)

Dhivya (DE US) confirmed 5-row table in Slack 2026-05-18 4:45 PM. Aric verified via pyodbc 2026-05-19.

| # | Table | Status 2026-05-19 | Rows verified | Action remaining |
|---|---|---|---:|---|
| 1 | `Enterprise.Wholesale_ProductSourcing_AFI.PoMaster` | ✅ **DONE** (Dhivya 2026-05-18) | 5,688,132 | Switch `v_PurchaseOrder` source path SC_LH → Enterprise |
| 2 | `Enterprise.Inventory_Enh_History.ItemBalance` | ⏳ Enterprise schema vẫn missing — **WORKAROUND OK**: `SC_LH.dbo.itembalance` via `df_brz_ItemBalance` | 48,968,574 | (a) Chase Dhivya Enterprise promote OR (b) deploy v1 với SC_LH source |
| 3 | `Enterprise.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` (Dhivya viết tắt "DemandFulfilmentCommonContain_Logility.ItemStatus") | ✅ **DONE** (Dhivya 2026-05-18) | 38,356,303 | Switch `v_LogilityItemStatus` source path SC_LH → Enterprise |
| 4 | `Enterprise.SupplyChain_Enh.PurchaseOrderSnapshot` | ⏳ Enterprise vẫn missing — **WORKAROUND OK**: `SC_LH.dbo.purchaseordersnapshot` via `df_brz_PurchaseOrderSnapshot` (2B rows ⚠️) | 1,997,040,026 | Phase 2 only; defer |
| 5 | `Enterprise.Wholesale_ProductSourcing_AFI.PoDetail` (originally 0 rows, separate item) | ✅ **DONE** (Dhivya 2026-05-18) | 21,945,294 | None — view already reads Enterprise (B1) |

**Plus column-deprecation finding (Dhivya rows 3-4, verified Aric 2026-05-19):**
- `ITBEXT.CRHLD/DLHLD/TOHLD/ATPQT` — 0 nonzero/3.39M rows → deprecated, không cần reload
- `ITEMBL.PHYOH` — 0 nonzero/3.41M rows → deprecated
- Action: thêm DQ rule `expected_zero` + DELETE 2 dataflow drafts (`df_brz_ITBEXT_Reloaded`, `df_brz_ITEMBL_PHYOH_Reloaded`)

**Plus dup classification update (Rakeshbalaji Slack 2026-05-09, verified Aric 2026-05-19):**

| Bảng | Grain | Loại | Evidence | Fix |
|---|---|---|---|---|
| `PoDetail` | (podordernum, podvendornum, poditemsequence) | ✅ **TRUE row dup** | 1 pair, 53/53 cols identical (Key 'P0SM242'\|'612908'\|1) | ROW_NUMBER ORDER BY podduedate DESC (current, OK) |
| `Logility` | (Item, Whse, WeekEnding) | ❌ **GRAIN CONFLICT** (không phải dup) | 9,128 pairs, 47/53 cols identical, 6 metrics differ (FirmDemand/Netfcst/ShippableInvQty/ShippableInvAmt/MosofSupply/OnHandAmt). Pattern: 1 data-row + 1 zero-placeholder | **FIXED 2026-05-19**: new ORDER BY prefers non-zero metrics row, then StatusChngDate, then OnHandAmt |
| `MasterData_ItemMaster_AFI.ITEMASA` | (STID, ITNBR) | N/A (out of scope) | Not used in inventory_health views | Not our concern; Bob's hub stranded-table issue |

**ETL code fixes applied 2026-05-19** (Silver layer only — Gold unaffected):
1. `v_PurchaseOrder` LEFT JOIN switched: `SC_LH.dbo.pomaster` → `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster`
2. `v_LogilityItemStatus` FROM switched: `SC_LH.dbo.logility_demandfulfillment` → `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`
3. `v_LogilityItemStatus` ORDER BY rewritten for grain-conflict (prefer non-zero data row)
4. `v_LogilityItemStatusSnapshotWeekly` SourceSystem/SourceTable hardcodes updated to Enterprise
5. `registry_inserts.sql`: A2 PurchaseOrder `is_active=1` (was 0), A3 LogilityItemStatus `is_active=1` (was 0), source_objects JSON now points to EL

**Registry final state**: A1/A2/A3 → `is_active=1` (EL primary); A4 → `is_active=0` (still blocked, but workaround dataflow ready); A5 → `is_active=0` (Phase 2 defer).

**Deploy unblocked**: với 3 EL loads + 2 SC_LH workarounds + view code updated, bronze layer ready cho v1 deploy. Còn lại: **3 Robert sign-offs (H1/H5/M3)** — critical path.

---

## §C. Bob architecture — 1 question

### Q4 — Cross-mart Dim reuse: DimCalendar / DimProduct / DimWarehouse

V10 forecast project originally published mart-specific `ForecastAccuracy_DW.DimCalendar/DimProduct/DimWarehouse`. **2026-06-01 update:** all three shared dimensions have now been promoted to `Shared_DW` and both Forecast Accuracy + Inventory Health semantic models bind to:

- `Shared_DW.DimCalendar`
- `Shared_DW.DimProduct`
- `Shared_DW.DimWarehouse`

**Decision made (this folder)**: use shared physical dims in `Shared_DW`, but preserve Inventory semantic table names/aliases (`DimProduct`, `DimWarehouse`, `DimCalendar`) so report/DAX contracts remain stable.

**Question for Bob**: confirm whether `Shared_DW` is the preferred naming/location for reusable Gold dimensions, or whether enterprise convention should use a different shared schema name later.

---

## §D. Deferred (L3) — Phase 2

| Item | Owner | Defer reason |
|---|---|---|
| MOMAST OSTAT firm list `('10','40','45')` | Robert | Phase 2 — current placeholder works for now |
| Transfer InTransit historical (currently NULL for SnapshotType='Weekly') | Aric | Phase 2 — snapshot-aware version using InventorySnapshotWeekly |
| ATPSUM "8AM 2nd version" intraday refresh | DE US | Phase 2 if needed |
| AvgIvc subquery tightening (potential dup rows) | Aric | Phase 2 — current accuracy acceptable for Phase 1 |

---

## Email status

- 2026-05-18: Draft prepared.
- 2026-05-18 4:45 PM: Dhivya (DE US) confirmed §B items via Slack — 3 Enterprise loads done + 2 workarounds via Aric dataflows + 5 cols confirmed deprecated.
- 2026-05-19: Aric verified all row counts via pyodbc.
- Email NOT yet sent (waiting for Aric to consolidate Q1/Q2/Q3 into single email per memory `feedback_working_style`). **§B items can now be dropped from email — only Q1/Q2/Q3 + Q4 remain.**
