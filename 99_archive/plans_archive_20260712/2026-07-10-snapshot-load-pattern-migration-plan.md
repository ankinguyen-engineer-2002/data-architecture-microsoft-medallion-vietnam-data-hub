# Snapshot Load-Pattern Migration Plan — PO + Inventory Weekly

Date: 2026-07-10  
Status: **P1 PLANNED; P2 RE-OPENED — proposed source-grain correction audit in progress; no migration approved or deployed**

## 1. Why this is the active plan

This plan supersedes the completed DemandForecast cutover plans as the active performance workstream. DemandForecast was exceptional: its historic source-grain/dedupe issue required a controlled C1–C8 rebuild. The two targets in this plan do **not** show that defect.

DemandForecast remains operationally complete:

- direct EL path is live;
- physical Staging and `Staging_Wrk` DemandForecast objects are dropped;
- FDM / FSW / KPI use DateRange `-30`;
- historical rebuild C1–C8 passed.

This plan changes no business formula, source grain, or historical data unless an audit gate proves that corrective work is needed.

> **2026-07-10 re-opened P2 finding — do not deploy/update TableDictionary yet:** DA proposed that the business grain be `ItemSku + WarehouseCode + dtea + FiscalMonth`, rather than the current `ItemSku + WarehouseCode + SnapshotWeekEndingDate + FiscalMonth`. A full read-only EL scan disproved the prerequisite that this proposed raw grain is clean: it has **8,604 duplicate groups / 8,604 extra rows**. The affected `dtea` dates are `2025-04-10` (7,200) and `2026-02-25` (1,404); both are non-Saturday and are not in the current weekly/latest output. The duplicate rows are non-identical business payload rows, while sharing the same proposed key and `dtec`. Therefore neither changing the TableDictionary key nor removing/changing dedupe is safe until DA confirms the authoritative business interpretation and tie-break rule. See §3.2A.

## 2. Scope and priority

| Priority | Target | Current method | Size observed 2026-07-10 | Candidate method | Decision |
|---|---|---|---:|---|---|
| P1 | `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical` | overwrite | 2,066,414,716 rows | guarded DateRange on `SnapshotDate` | first migration candidate |
| P2 | `InventoryHistory_Enh.InventorySnapshotWeekly` | overwrite | 695,357,244 rows; EL source 4,232,005,200 rows | guarded DateRange on `SnapshotWeekEndingDate` | second, semantic-sensitive candidate |
| Monitor | `InventoryHistory_Enh.ForecastSnapshotWeekly` | DateRange `-30` | 1,078,496,866 rows | none | already migrated; do not rework |
| Deferred | Inventory Health Gold downstream facts/helpers | overwrite / derived | smaller direct targets | evaluate only after P2 | not a first migration target |

Out of scope:

- historical backfill/rebuild by default;
- changes to business calculations, source mappings, or target DDL;
- generic changes to `ETL_Framework.DW_Developer.usp_UpdateCuratedTableFromView_DateRange`;
- live mutation without Aric approval;
- dropping `dbo.Usp_Refresh_Shared_Staging` (separate orchestration-cleanup decision).

## 3. Audit baseline — completed

### 3.1 PurchaseOrderSnapshotHistorical

**TableDictionary primary key:**

```text
SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost
```

**View mapping:**

```text
posSnapshot → SnapshotDate
posItNbr    → ItemSku
posWhse     → WarehouseCode
posVndnr    → VendorNumber
posPstts    → StatusCode
posDueDt    → DueDate
posUUD1PM   → UnitCost
```

| Audit | Result |
|---|---|
| View transform/dedupe | no `ROW_NUMBER` or hidden dedupe; direct mapped projection |
| Source/view/physical duplicate probes at TD key | PASS on sampled 2023–2026 dates (0 groups) |
| Full physical duplicate probe at TD key | PASS: 0 duplicate groups / 0 extra rows |
| View ↔ physical all-history parity | PASS: 2,368 snapshot dates, row count + Ordered / OnOrder / InTransit sums match |
| EL freshness | max `posSnapshot` = 2026-07-09; 40,733,444 rows across 30 active dates |

### 3.2 InventorySnapshotWeekly

**TableDictionary primary key:**

```text
ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
```

**View semantic contract:**

```text
EL DemandInventorySnapshotDaily
→ Saturday historical snapshots + latest effective snapshot
→ ROW_NUMBER PARTITION BY the exact TableDictionary primary key
→ choose newest technical version: ORDER BY dtec DESC, dtea DESC
```

| Audit | Result |
|---|---|
| `ROW_NUMBER()` partition vs TD key | PASS: exact match |
| View duplicate groups at TD key | PASS on historical/current probe dates (0 groups) |
| Full physical duplicate probe at TD key | PASS: 0 duplicate groups / 0 extra rows |
| View ↔ physical all-history parity | PASS: 185 output dates, row count + key quantity sums match |
| Output semantics | 180 `WEEKLY` Saturday dates plus one current `LATEST` non-Saturday date |
| EL freshness | max snapshot = 2026-07-09; 97,878,672 rows across active 26 dates |

### 3.2A Re-opened DA proposed `dtea` grain audit — 2026-07-10

**DA hypothesis under audit:**

```text
ItemSku, WarehouseCode, dtea, FiscalMonth
```

**Evidence from full read-only `Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily` scan (4,232,005,200 rows):**

| Check | Result | Consequence |
|---|---:|---|
| Null `dtea` | 0 | `dtea` is populated. |
| Raw duplicate groups at proposed `dtea` key | **8,604** | Proposed raw key is not unique. |
| Extra rows at proposed `dtea` key | **8,604** | Each detected group has two rows. |
| Duplicate `dtea` dates | `2025-04-10`: 7,200; `2026-02-25`: 1,404 | Isolated historical defects, not a clean raw grain. |
| Duplicate-row payload | non-identical | Cannot safely remove one without an approved deterministic business tie-break. |
| `dtea` versus `dinSnapshot` calendar date | 13,619,592 source rows differ (all `dtea = dinSnapshot - 1 day`) | These arise on 3 historic source snapshot dates; `dtea` cannot be substituted silently for the current target date. |
| Current weekly/latest output with `SnapshotDate <> CAST(dtea AS date)` | 0 rows | For the currently selected 181 output dates, `dtea` happens to map one-to-one with snapshot date. This is evidence of current output equivalence, not proof of full-source grain cleanliness. |
| Current selected output duplicates at proposed `dtea` key | 0 | Current Saturday + latest selection excludes the two duplicate `dtea` dates. |

**Additional critical implementation fact:** the current physical `InventoryHistory_Enh.InventorySnapshotWeekly` DDL does **not** persist a `dtea` column. Its historical key is currently represented by `SnapshotWeekEndingDate`. A TableDictionary change to a non-persisted `dtea` key would be invalid without an explicitly approved target schema/view contract change and a historical rebuild strategy.

**Decision as of this audit:**

```text
Do not update live TableDictionary.
Do not replace SnapshotWeekEndingDate with dtea in the view/table.
Do not remove ROW_NUMBER() dedupe.
Do not classify P2 as DemandForecast-like or schedule historical backfill yet.
```

**Required DA clarification before a corrective design:**

1. Is `dtea` the intended business as-of/snapshot date, or a technical extract timestamp?
2. For the 8,604 same-`dtea` key collisions with different payload, which deterministic row wins and why?
3. Should isolated non-Saturday snapshots be retained in the weekly history, or should the existing Saturday + latest contract remain authoritative?
4. If `dtea` is a new persisted business key, approve target DDL change, exact date-column mapping, downstream contract impact, and a full historical rebuild/parity plan.

### 3.3 Backfill decision

**No historical backfill is planned under the currently deployed contract.** Existing history matches each current view and contains no duplicates at the declared target grain. The DA `dtea` proposal has reopened this decision but has **not** met its clean-grain prerequisite; a historical rebuild becomes required only after DA approves a resolved source-grain/tie-break and target-schema contract, or a documented current-contract mismatch is found.

## 4. Non-negotiable safety controls

The framework DateRange procedure deletes the target window before inserting source rows. Bench evidence showed that an empty source window can successfully wipe the recent target window; duplicate source grain can create duplicate target rows.

Therefore every production wrapper must perform these checks **before** the DateRange `EXEC`:

1. Source/view window has `COUNT_BIG(*) > 0`.
2. Source/view has zero duplicate groups at its TableDictionary primary key inside the same window.
3. The wrapper `THROW`s on either failure; it must not call the framework procedure.
4. The target date key supplied to the framework equals the view filter date key.
5. No global framework-procedure modification: controls stay in these two business wrappers.

Required failure message attributes:

```text
target object, date key, resolved window start, source row count / duplicate-group count,
and statement that target was not changed.
```

## 5. Migration design

### 5.1 P1 — PurchaseOrderSnapshotHistorical

**Target wrapper:** `dbo.Usp_Refresh_InventoryHealth_Silver_W02`  
**Target date key:** `SnapshotDate`  
**Initial candidate window:** `-30` days, subject to late-arriving/correction audit.

Replace only this target call:

```sql
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
    'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'PurchaseOrderSnapshotHistorical';
```

with the guarded pattern:

```text
precheck v_PurchaseOrderSnapshotHistorical where SnapshotDate >= window start
→ assert non-empty
→ assert TD-key uniqueness
→ usp_UpdateCuratedTableFromView_DateRange(
      Processing, InventoryHistory_Enh, PurchaseOrderSnapshotHistorical,
      SnapshotDate, SnapshotDate, -N)
```

The view must be confirmed to apply/filter the DateRange predicate before broad remote processing; this is a performance gate, not merely a correctness gate.

### 5.2 P2 — InventorySnapshotWeekly

**Target wrapper:** `dbo.Usp_Refresh_InventoryHealth_Silver_W01`  
**Target date key:** `SnapshotWeekEndingDate`  
**Candidate window:** `-42` days initially; do not finalize until late-arrival and Query Insights evidence is reviewed.

The wrapper must insert the complete view output inside the window:

```text
Saturday WEEKLY snapshots
+ the LATEST effective snapshot even when it is a non-Saturday
```

Required prechecks:

```text
1. view rows in DateRange > 0;
2. zero duplicate groups at (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth);
3. one current latest-effective output exists and its date is within the selected window;
4. expected Saturday output exists in the selected window;
5. resolved live EL column names / repo SQL parameter name are reconciled before deployment.
```

Do not use a Saturday-only filter in the loader. That would remove the `LATEST` non-Saturday state used by Inventory Health.

## 6. Execution phases and gates

### Phase 0 — Freeze, evidence pack, and scope confirmation

- [ ] Aric approves P1-only development scope; P2 remains design/audit until separately approved.
- [ ] Confirm no active full PL / target wrapper run before each live test.
- [ ] Export live definitions, TableDictionary rows, target/view row-and-sum baseline, and Query Insights baseline.
- [ ] Reconcile generated orchestration repo wrappers with live wrappers. The current architecture mirror is stale for FSW method and must not be treated as deploy source without reconciliation.
- [ ] Document downstream consumers and expected post-load sequencing.

**Gate:** signed evidence bundle; no migration SQL executed.

### Phase 1 — P1 development (repo only)

- [ ] Add the PO non-empty and TD-key duplicate guard to the generated/canonical W02 wrapper source.
- [ ] Replace only PO's overwrite call with `usp_UpdateCuratedTableFromView_DateRange`.
- [ ] Keep all other W02 calls unchanged.
- [ ] Set PO TableDictionary proposal: `UpdateMethod=DateRange`, `DateKey=SnapshotDate`, `DateRangeDays=N`.
- [ ] Sync canonical repo, architecture deployment mirror, orchestration manifest/run order, and generated wrapper source.
- [ ] Add unit/static validation that checks wrapper order: guards precede DateRange `EXEC`.

**Gate:** peer SQL review; build/type/static checks pass; no live changes.

### Phase 2 — P1 test/audit in isolated or approved controlled window

- [ ] Run source/view duplicate and non-empty guards for candidate `N=30`, then profile correction/late-arrival behavior.
- [ ] Read-only parity: view vs physical for multiple dates inside and outside the candidate window.
- [ ] Execute a controlled DateRange prove-out only after approval.
- [ ] Validate post-run: source/view vs physical row count and three quantity sums in-window.
- [ ] Validate outside-window row count and sums unchanged.
- [ ] Rerun same window and prove idempotence/no duplicate TD keys.
- [ ] Inspect Query Insights: elapsed time, remote/memory/disk scans, concurrency, failures/retries.
- [ ] Run the dependent Inventory Health waves or approved full PL and validate terminal DQ.

**Pass criteria:** all checks pass, no unplanned full scan/regression, target has zero duplicate keys, and no downstream DQ regression.

### Phase 3 — P1 production adoption and monitoring

- [ ] Deploy wrapper + TableDictionary only after explicit approval.
- [ ] Execute first scheduled/approved full PL with monitoring.
- [ ] Capture runtime/CU proxy and compare with full-overwrite baseline.
- [ ] Reconcile target/view and run DQ after each of the first 3 successful operational runs.
- [ ] Mark P1 complete only after stability evidence is recorded.

### Phase 4 — P2 design/development

- [ ] Repeat Phase 0 baseline specifically for Saturday plus latest-effective output semantics.
- [ ] Choose/approve date window from correction-lag evidence (`-42` is a candidate, not a decision).
- [ ] Resolve DA's proposed `dtea` business-grain meaning, the two historical collision dates, and deterministic tie-break before any key change. Current full EL audit is **FAIL for raw proposed-key uniqueness: 8,604 groups**.
- [ ] Decide whether `dtea` requires an approved persisted target column/DDL and full historical rebuild; do not use a non-persisted TD key.
- [ ] Resolve live `dtea` versus repo `dinSnapshot` source-column naming/semantic drift; deploy only canonical verified SQL.
- [ ] Add P2 guards and DateRange call to W01 in repo only.
- [ ] Update P2 TableDictionary proposal only after the selected window is approved.

**Gate:** P1 stable and P2 semantic/Query Insights review passes.

### Phase 5 — P2 prove-out, adoption, monitoring

- [ ] Controlled DateRange execution validates Saturday plus non-Saturday `LATEST` output.
- [ ] In-window parity includes rows and `OnHandQty`, `SafetyStockTarget`, `IOSafetyStock`, `OrderQty`, `BuildQty` sums.
- [ ] Outside-window history preservation passes.
- [ ] Rerun idempotence and full duplicate-key check pass.
- [ ] Downstream `AwdHelper`, `AtpWeekEnding`, safety-stock/Inventory Health Gold and terminal DQ pass.
- [ ] Inspect Query Insights and compare against overwrite baseline.
- [ ] Deploy and monitor three operational runs after explicit approval.

## 7. Rollback and incident handling

Before a wrapper invokes DateRange, guard failure must stop the wave without touching target data.

If a post-load parity/DQ failure occurs:

```text
1. Stop subsequent dependent waves; preserve query/audit evidence.
2. Do not run another DateRange blindly.
3. Restore only the affected approved date window from the current canonical view using explicit bounded DELETE + INSERT after diagnosis.
4. Use full overwrite only with explicit approval; it is not the routine rollback.
5. Revert wrapper/TableDictionary to overwrite only if approved and only after confirming source/view correctness.
```

Historical backfill is not rollback. It requires a new approved plan and evidence of a historical defect.

## 8. Deliverables

- revised canonical + mirrored wrapper SQL;
- TableDictionary update script (not executed until approval);
- pre/post audit SQL pack and saved results;
- Query Insights baseline and comparison;
- orchestration/run-order/manifest synchronization;
- test evidence for empty-window, duplicate-grain, parity, outside-window preservation, idempotence, downstream DQ;
- context and status-board update after each approved phase.

## 9. Current next action

**Await Aric approval for Phase 0 / P1 (PurchaseOrderSnapshotHistorical) only.** No guard, DateRange migration, TableDictionary update, or live execution is authorized by this planning document.
