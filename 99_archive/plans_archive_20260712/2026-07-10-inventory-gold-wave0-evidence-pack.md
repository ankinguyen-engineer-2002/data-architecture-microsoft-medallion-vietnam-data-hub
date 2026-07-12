# Inventory Health Gold — Wave 0 Evidence Pack

Date: 2026-07-10 ICT (Module 04 extended 2026-07-11)
Status: **Wave 0 COMPLETE. Module 04 C1 inv_base parity PASS. Module 05 Layer F 9/9 PASS, Layer G perf baseline captured, e2e SubStatus + ClassQty both PASS. Report-contract preservation locked as a hard constraint (§2.1 / §6.3 gate 7 / §8). No live production object mutated. No optimization deployed. Ready to request the Wave 1 gate.**
Companion to: `2026-07-10-inventory-gold-business-parity-optimization-plan.md`

Harness: `05_tools/03_gold_parity/` (read-only; `ApplicationIntent=ReadOnly`; pyodbc + Entra token).
Artifacts: `05_tools/03_gold_parity/contracts/*.contract.json`, `*.baseline.json`; run logs in `runs/`.

## 1. What was executed

All against LIVE `SupplyChain_Gold_Warehouse` / `SupplyChain_Processing_Warehouse` / `Enterprise_Lakehouse`, read-only:

1. **Contract inventory** (Module 01) — 9 Gold targets: live view SQL + `INFORMATION_SCHEMA` columns + static SQL parse (CTE/ROW_NUMBER/GROUP BY/JOIN/CASE) + loader positional contract.
2. **Risk probes R1/R2/R3** (Module 02) — join multiplicity, dim uniqueness, dedup tie-break materiality.
3. **Baseline capture** (Module 03) — row count, business-key uniqueness, date coverage, exact measure sums, categorical distributions, per-week reconciliation, best-effort Query Insights.
4. **C1 inline shadow parity** (Module 04) — pure SELECT A-vs-B inv_base proof; **no live DDL/DML**, no shadow object created on Fabric.
## 2. Contract & loader safety (Layer A)

| Target | Wave | View→Table cols | Loader `SELECT *` safe | Drift |
|---|---|---|---|---|
| Shared_DW.DimCalendar | W01 | 75/75 | OK | 0 |
| Shared_DW.DimProduct | W01 | 40/40 | OK | 0 |
| Shared_DW.DimWarehouse | W01 | 21/21 | OK | 0 |
| InventoryHealth_DW.DimVendor | W10 | 2/2 | OK | 0 |
| ProjectedInventoryHealthSubStatus | W20 | 28/28 | OK | 0 |
| InventoryHealthSubStatusWeekly | W20 | 12/12 | OK | 0 |
| InventoryClassificationQtyWeekly | W21 | 12/12 | OK | 0 |
| FactInventoryHealthFutureWeekEnding | W30 | 34/34 | OK | 0 |
| FactInventoryHealthSnapshot | W30 | 54/54 | OK | 0 |

- All 9 view column sets match their final-table column sets exactly (position + count). The `usp_RefreshCuratedTableFromView` `INSERT ... SELECT *` path is currently safe for all 9. The 2026-07-03 `DimWarehouse` drift class is not currently present.

### 2.1 Live-vs-repo view drift (must record, not a blocker)

The LIVE serving views expose columns the repo `_Wrk` `.sql` files do not generate. Live view = live table, so load is safe, but repo is behind live:

- `FactInventoryHealthSnapshot` LIVE has **54** cols incl. `WeightedSINegScore`, `OutageClass`; repo view SQL ends at `AFIStatus` (53 modelled). 
- `FactInventoryHealthFutureWeekEnding` LIVE has `ProjectedShortageValue` where repo view names `ProjectedRevenueAtRisk`.
- **Action:** the behavioural oracle uses LIVE columns (correct). Repo view files should later be reconciled to live, separately from optimization scope.

## 3. Risk probes (decisive for candidate safety)

### R1 — Fan-out / row multiplication (FactSnapshot LEFT JOINs)
All 7 joined helper/status tables have **0 duplicate groups** at their exact join grain → FactSnapshot is **not** multiplied by any join.

| Joined table | rows | dup groups at join grain |
|---|---:|---:|
| SafetyStockHelper | 21,070,457 | 0 |
| Cogs52WWeekly | 19,605,162 | 0 |
| LastInvoiceWeekly | 19,605,162 | 0 |
| AFIStatusSnapshotWeekly | 19,605,162 | 0 |
| AwdHelper | 13,632,832 | 0 |
| InventoryHealthSubStatusWeekly | 19,605,162 | 0 |
| InventoryClassificationQtyWeekly | 19,605,162 | 0 |

### R2 — DimProduct uniqueness (fact joins on ItemSKU only)
`Shared_DW.DimProduct` is unique at `ItemSKU`: 783,945 rows, 0 duplicate item groups → `OnHand Value`, `UsedStorageCube`, `Revenue at risk` are not inflated.

### R3 — `inv_base` dedup tie-break materiality
Source `InventoryHistory_Enh.InventorySnapshotWeekly`:
- **705,785,832** raw rows → **19,605,162** groups at `(ItemSku, WarehouseCode, SnapshotWeekEndingDate)` ≈ **36:1** collapse.
- `groups_where_onhand_differs = 0` → the `ORDER BY FiscalMonthDate ASC` tie-break does **not** change `OnHandQty` (all rows in a group share the value on that column).
- `groups_where_fiscalmonthdate_tied = 0` → ordering is deterministic on `OnHandQty`.
- Initial Module 02 gap: stability was proven for `OnHandQty` only. **This gap was subsequently closed by Module 04 full-history T1:** `MakeBuyCode`, `PrimaryVendorName`, `SecondaryVendorName`, `ReplenishmentLeadTime`, and `SnapshotType` also have 0 within-group differences; FiscalMonthDate ties remain 0.

This 705M→19.6M source is scanned + deduped **3 times** across the weekly family — the core repeated-work finding and the primary ROI target.

## 4. Frozen baseline oracle (system A)

Business-key uniqueness holds at declared grain for all 9 targets (all `unique_at_grain = True`):

| Target | rows | distinct key | unique |
|---|---:|---:|---|
| DimCalendar | 21,551 | 21,551 | ✔ (DateSK) |
| DimProduct | 783,945 | 783,945 | ✔ (ItemSKU) |
| DimVendor | 87,003 | 87,003 | ✔ (VendorNumber) |
| DimWarehouse | 53 | 53 | ✔ (WarehouseCode) |
| ProjectedInventoryHealthSubStatus | 3,785,137 | 3,785,137 | ✔ (Item,WH,FactAsOfDate,FutureWeekEnding) |
| FactInventoryHealthFutureWeekEnding | 3,785,137 | 3,785,137 | ✔ (Item,WH,FutureWeekEnding,SnapshotDate) |
| InventoryHealthSubStatusWeekly | 19,605,162 | 19,605,162 | ✔ (Item,WH,SnapshotWeekEnding) |
| InventoryClassificationQtyWeekly | 19,605,162 | 19,605,162 | ✔ (Item,WH,SnapshotWeekEnding) |
| FactInventoryHealthSnapshot | 19,501,346 | 19,501,346 | ✔ (Item,WH,SnapshotWeekEndingDate) |

### 4.1 Row-count relationship (parity invariant B must reproduce)
- Weekly family = 19,605,162; FactSnapshot = 19,501,346; **Δ = 103,816**.
- Initial hypothesis was the FactSnapshot non-null-key filter. Module 04 disproved that as the current cause: shared_rn1 and shared_nonnull are both 19,605,162 (0 rn=1 groups excluded by null keys). The observed **Δ=103,816 is exactly the rn=1 `SnapshotType='LATEST'` population** excluded by FactSnapshot's post-dedup WEEKLY filter. A candidate must preserve this post-pick SnapshotType behavior exactly.
- Future family = 3,785,137 rows and Projected = 3,785,137 (1:1), both keyed off `SupplyPlanDetail WHERE IsLatestSupplyPlanSnapshot = 1`.

### 4.2 Frozen grand totals — FactInventoryHealthSnapshot (max date 2026-07-04)
- `SUM(OnHandQty)` = 2,146,230,631
- `SUM(OnHandValue)` = 76,277,084,285.2561
- `SUM(OnOrderQty)` = 957,865,819
- `SUM(SIQty)` = 1,538,875,984
- `SUM(ShortageValue)` = -18,577,955,997
- Date coverage: SnapshotWeekEndingDate 2023-01-07 → 2026-07-04.

### 4.3 Frozen distributions — FactInventoryHealthSnapshot
`InventoryClassificationFinalStatus`: SWEET_SPOT 6,427,701 · OVER_TARGET 6,329,621 · BELOW_TARGET 2,801,722 · INACTIVE 2,054,373 · EXCESS 850,753 · SLOB 622,709 · AGGRESSIVE_EXCESS 224,402 · TB_INVENTORY 190,065.
`IsShortage/Surplus/InStock`: SURPLUS 9,600,945 · IN_STOCK 6,511,664 · SHORTAGE 3,388,737.

Per-week reconciliation (row count + 8 measure sums by SnapshotWeekEndingDate) is stored in each `*.baseline.json` under `weekly_recon`. These are the coarse→fine anchors for Layer D.

## 5. Candidate ranking (test-only; NOT deployed)

| Rank | Candidate | ROI | Parity risk | Gate before build | Module 04 status |
|---|---|---|---|---|---|
| C1 | Shared deduped `inv_base` (1× instead of 3× scan of 705M-row source) | High | R3 closed | Preserve NULL-filter + SnapshotType Δ=103,816 | **inv_base parity PASS** (inline A-vs-B) |
| C2 | Shared PO/MO aggregate (FactSnapshot + SubStatusWeekly) | Medium | Low (already GROUP BY, grain proven) | Exact SUM parity | not started |
| C3 | Shared `sp_latest` + as-of `awd`/`afi` for future family | Med-High (FutureWeekEnding 45m) | R4 as-of ordering | Latest-selection must stay invariant | not started |
| C4 | Narrow projected columns before big FactSnapshot joins | Medium | Low | Drop-unused-only, grain unchanged | not started |
| C5 | Predicate pushdown where provably equivalent | Low-Med | R3/R4 if it crosses dedupe/latest | Layer A must be green | not started |

No candidate may alter `InventorySnapshotWeekly` semantics (blocked, US/DA). Full overwrite retained until a mutable-window + temporal-parity case exists.

## 6. Module 04 — C1 inv_base parity (read-only, no live object)

Safety: `ApplicationIntent=ReadOnly`; SELECT only; **zero** CREATE/ALTER/DROP/INSERT/UPDATE/DELETE on live Fabric.

Design under test:
- shared_inv_base = `ROW_NUMBER() OVER (PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate ORDER BY FiscalMonthDate ASC) = 1` on **all** `InventorySnapshotWeekly` rows, carrying OnHandQty + MakeBuyCode + PrimaryVendorName + SecondaryVendorName + ReplenishmentLeadTime + SnapshotType.
- FactSnapshot consumer: non-null keys + `SnapshotType IN ('WEEKLY','WEEKLY_AND_LATEST')` **after** shared pick.
- SubStatus/ClassQty consumer: shared surface projected to OnHandQty (no extra filter).

### 6.1 Bounded smoke (`--recent-weeks 8`) — PASS

Artifact: `runs/20260711T021117Z_shadow_parity_c1.*`

| Check | Result |
|---|---|
| T1 R3 extended (FMD ties + carried-col variance) | multi_row_groups=833,223; FMD tied=0; all carried cols differ=0 |
| T2 shared counts | rn1=833,223; fact_eligible=729,407 |
| T5 SnapshotType dist | WEEKLY=729,407; LATEST=103,816 |
| T3 Fact A-vs-B (full-tuple EXCEPT) | a=b=833,223; a∉b=0; b∉a=0 |
| T4 SubStatus A-vs-B (full-tuple EXCEPT) | a=b=833,223; a∉b=0; b∉a=0 |

### 6.2 Full history — PASS

Artifacts:
- T1/T2/T5 + invariants: run log `/tmp/m04_full.txt` (T1–T5 pass; T3 timed out on first wide-EXCEPT attempt)
- T3/T4 optimized anti-join: `runs/20260711T022510Z_shadow_parity_c1.*`

| Check | Result |
|---|---|
| T1 R3 extended | multi_row_groups=**19,605,162**; FMD tied=**0**; all carried cols (OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName, ReplenishmentLeadTime, SnapshotType) differ=**0** |
| T2 shared counts | shared_rn1=**19,605,162**; nonnull=19,605,162; fact_eligible=**19,501,346** |
| T5 SnapshotType dist | WEEKLY=**19,501,346**; LATEST=**103,816**; excluded=103,816 |
| Full-history invariants | shared==weekly family **True**; fact_eligible==FactSnapshot table **True** |
| T3 Fact A-vs-B (key anti-join + value mismatch) | a=b=**19,605,162**; a∉b=0; b∉a=0; value_mismatches=**0** (189s) |
| T4 SubStatus A-vs-B | a=b=**19,605,162**; a∉b=0; b∉a=0; value_mismatches=**0** (265s) |

### 6.3 Interpretation

1. **R3 closed:** `ORDER BY FiscalMonthDate ASC` is deterministic (0 FMD ties). Carried columns are **constant** within every multi-row group, so the pick is unique for all columns FactSnapshot/SubStatus consume — not just OnHandQty.
2. **NULL-before-RN vs RN-then-NULL is equivalent** on this source (T3 empty both ways). C1 can apply NULL filter after shared pick without changing FactSnapshot inv_base grain/values.
3. **SnapshotType alone explains weekly-family vs FactSnapshot Δ:** 19,605,162 − 19,501,346 = **103,816** = all `LATEST` rn=1 rows. No `WEEKLY_AND_LATEST` rows present.
4. **C1 inv_base business parity: PASS.** This does **not** prove end-to-end Gold table parity (joins/CASE still per-view), does **not** prove performance gain (no materialization), and does **not** authorize production deployment.

## 7. Module 05 — Downstream serving (Layer F) + performance baseline (Layer G)

Safety: `ApplicationIntent=ReadOnly`; SELECT + metadata only; zero CREATE/ALTER/DROP/INSERT/UPDATE/DELETE on live Fabric. Harness `05_tools/03_gold_parity/05_downstream_perf.py`.

### 7.1 Layer F — view-vs-table sanity (oracle still valid)

Each Gold target: live final table vs live `_Wrk.v_*` recompute. Light targets (4 dims) compared on row count + anchor measure SUMs; heavy views compared on row count only (measure recompute = a full Gold refresh worth of scan; opt-in via `--measures-for`). All 9 PASS, 0 diffs.

| Target | table.n | view.n | diffs | mode | elapsed | run |
|---|---:|---:|---:|---|---:|---|
| DimCalendar | 21,551 | 21,551 | 0 | rowcount+measures | 0.6s | 20260711T124109Z |
| DimProduct | 783,945 | 783,945 | 0 | rowcount+measures | 0.7s | 20260711T124109Z |
| DimWarehouse | 53 | 53 | 0 | rowcount+measures | 0.7s | 20260711T124109Z |
| DimVendor | 87,003 | 87,003 | 0 | rowcount+measures | 0.6s | 20260711T124109Z |
| InventoryHealthSubStatusWeekly | 19,605,162 | 19,605,162 | 0 | rowcount | 124.3s | 20260711T124123Z |
| InventoryClassificationQtyWeekly | 19,605,162 | 19,605,162 | 0 | rowcount | 113.0s | 20260711T124338Z |
| ProjectedInventoryHealthSubStatus | 3,785,137 | 3,785,137 | 0 | rowcount | 325.1s | 20260711T124542Z |
| FactInventoryHealthFutureWeekEnding | 3,785,137 | 3,785,137 | 0 | rowcount | 670.8s | 20260711T125118Z |
| FactInventoryHealthSnapshot | 19,501,346 | 19,501,346 | 0 | rowcount | 97.6s | 20260711T130242Z |

Interpretation: the Module 03 frozen baseline still reconciles against every live view; the oracle is not stale. Row counts match §4 exactly. Dim measure SUMs match view vs table with 0 diff.

### 7.2 Layer D e2e — full-tuple A-vs-B for small consumers

A = live final table; B = live `_Wrk.v_*` recompute. Key anti-join + null-safe value mismatch over **all** columns (same shape as Module 04 T3/T4). Each heavy count runs on its own short-lived read-only connection with one retry, so a dropped TCP session cannot cascade.

| Target | keys | a_rows | b_rows | a∉b | b∉a | value_mismatches | pass | run |
|---|---|---:|---:|---:|---:|---:|---|---|
| InventoryHealthSubStatusWeekly | Item,WH,SnapshotWeekEnding | 19,605,162 | 19,605,162 | 0 | 0 | 0 | ✔ | 20260711T131645Z |
| InventoryClassificationQtyWeekly | Item,WH,SnapshotWeekEnding | 19,605,162 | 19,605,162 | 0 | 0 | 0 | ✔ | 20260712T010259Z |

Both small consumers PASS full-tuple A-vs-B: 0 anti-join rows either direction, 0 value mismatches across all columns. Note: the first ClassQty attempt failed on infra, not logic — Fabric capacity was paused mid-run (error 24800), and a long anti-join on the shared connection dropped its TCP session. The harness was hardened (per-query fresh read-only connection + one retry); the clean rerun took 1,388s and passed.

### 7.3 Layer G — performance baseline (Wave 1 must beat this)

Source: `queryinsights.exec_requests_history`, `INSERT INTO <target>_LOAD SELECT * FROM v_*`, 30-day window. Run `20260711T084148Z_downstream_perf_perf.*`.

- Chain median elapsed (sum of per-target medians) = **643s**; chain median remote scan = **10,150 MB**.
- Hotspots: `FactInventoryHealthFutureWeekEnding` p95=886s (compute-bound); `FactInventoryHealthSnapshot` remote_med=5,154 MB (scan hotspot); `InventoryHealthSubStatusWeekly` remote_med=3,703 MB.

Any Wave 1 candidate B must reduce the relevant per-target elapsed/scan while satisfying every parity gate **and** the §2.1 in-place report-contract constraint.

## 8. Report-contract preservation (added 2026-07-11)

Production Power BI (`sc_control_tower`, Direct Lake on `SupplyChain_Gold_Warehouse`) already binds visuals/measures/relationships to these physical Gold facts, and the same report surface also consumes Forecast Accuracy Gold facts. Rebuilding that authoring layer is not an acceptable cost of an ETL optimization. Plan §2.1 now makes in-place identity a hard constraint and §6.3 gate 7 requires proving it before any deploy:

- Optimize the producer (`_Wrk.v_*` view + loader), never the physical serving object.
- Same table name/schema/columns/order/types/nullability/key — byte-for-byte compatible; no drop-and-recreate, no `_v2` fact, no rename/reorder/retype.
- Post-candidate must require zero Power BI measure/relationship/visual edits, verified by a column/type/key diff + a `sc_control_tower` read-only smoke query.
- Applies to Inventory Health Gold now and any Forecast Accuracy Gold fact touched later.

This is why C1 is viable: it changes only the shared inv_base logic feeding the existing `INSERT ... SELECT *` into the same physical facts; it does not create or repoint any report-facing object.

## 9. Next actions (still Wave 0 → Wave 1 gate)

1. ~~Close R3 gap~~ **DONE** (Module 04 T1 full history).
2. ~~Build Module 04 C1 inv_base parity~~ **DONE** (inline A-vs-B; no live DDL).
3. ~~Build Module 05 (downstream serving + performance baseline)~~ **DONE** — Layer F 9/9 PASS, Layer G baseline captured, e2e SubStatus + ClassQty both PASS.
4. ~~Record report-contract preservation as a hard constraint~~ **DONE** (§8; plan §2.1 + §6.3 gate 7).
5. **Wave 0 complete.** Request the Wave 1 gate for the first in-place C1 candidate on `FactInventoryHealthSnapshot` / shared inv_base.
6. Only after explicit approval: any production object change, in-place only per §2.1.
