# Demand Forecast Historical Backfill And Load Reset Plan

Date: 2026-07-09  
Last status update: 2026-07-10 ICT (completed; superseded as active work plan)

> **Plan status: COMPLETE / ARCHIVED AS ACTIVE PLAN.** The DemandForecast C1–C8 historical rebuild and DateRange reset are complete. For the active snapshot performance backlog, use [`2026-07-10-snapshot-load-pattern-migration-plan.md`](2026-07-10-snapshot-load-pattern-migration-plan.md). This document remains historical evidence only.

Scope:

- Workspace: Enterprise SupplyChain-Dev
- Source table: `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily`
- Official candidate grain:
  - `dfcItem`
  - `dfcWarehouse`
  - `dfcFiscalMonth`
  - `dfcSnapshot`
  - `DfcCustomerGroups`
- Affected marts:
  - Forecast Accuracy
  - Inventory Health
- Affected warehouse items:
  - `SupplyChain_Processing_Warehouse`
  - `SupplyChain_Gold_Warehouse`

---

## Status board (2026-07-09 re-scope)

> **Superseding note:** Multi-year historical rebuild is **no longer the default next action**.
> Live parity probes showed EL ≈ Staging ≈ silver/gold view/physical on multiple cycle dates.
> Primary path = **drop staging hop (direct EL) + DateRange daily**.
> Historical chunk rebuild remains **conditional** if post-cutover parity fails.

| Phase / item | Status | Note |
|---|---|---|
| Phase 0.1 Freeze: no full PL running | [x] DONE | REST + QI audit |
| Phase 0.2 Confirm EL 5-key grain | [x] DONE | ops + hist probes dups=0 |
| Phase 0.3 Understand DateRange vs full overwrite | [x] DONE | DateRange = relative GETDATE only |
| Phase 0.4 Deep parity EL/Staging/view/phys | [x] DONE | 2023–2026 probes PASS |
| Phase 0.5 Re-scope history rebuild | [x] DONE | conditional only |
| Staging-drop path chốt direct EL | [x] DONE | no Source_Wrk |
| Repo code repoint + Shared_Staging no-op | [x] DONE | not live |
| Phase 1 dry-run historical window rebuild | [x] SUPERSEDED | full chunk rebuild executed 2026-07-10 |
| Phase 2 historical chunks (~5-mo C1–C8) | [x] PASS 2026-07-10 | FDM+FSW+KPI window DELETE+INSERT; no Staging; no full PL |
| Phase 3 2026 transition rebuild | [x] PASS via C7–C8 | included in C1–C8 run |
| Phase 4 daily DateRange production | [x] PASS 2026-07-10 prove-out | FDM-30/FSW-15/KPI-30 |
| Live deploy direct-EL views | [x] DONE 2026-07-10 | see staging-drop checklist |

**Execution handoff doc:**  
`01_docs/plans/2026-07-09-demandforecast-staging-drop-cutover-checklist.md`

---

## Current Decision (updated 2026-07-09)

Original draft prioritized historical baseline rebuild first, then DateRange.

**Updated priority (evidence-based):**

1. [x] Confirm EL 5-key cleanliness and parity with current physical outputs.
2. [x] Prepare **direct EL** cutover code (drop Staging hop for this source).
3. [x] Live deploy + parity gate (2026-07-10 PASS).
4. [x] DateRange daily for FDM / FSW / KPI with empty-window + 5-key pre-checks (2026-07-10 PASS).
5. [x] Historical window rebuild executed 2026-07-10 (Aric requested for certainty): C1–C8 PASS.

Reason for re-scope:

- Probes on `2023-05-15`, `2024-01-15`, `2024-10-14`, `2025-06-09`, `2026-06-15` showed EL=Staging rows/sums and FDM view=physical.
- Blind multi-year rebuild burns CU without proven correctness gain.
- `usp_UpdateCuratedTableFromView_DateRange` cannot target absolute 2023 ranges (relative `@NumberofDays` from GETDATE only).

---

## Important Feasibility Finding

Chunked historical backfill is feasible, but not with default overwrite alone.

Default framework overwrite, using:

```sql
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
    '<warehouse>', '<schema>', '<table>';
```

is a full target replacement pattern.

If a view is temporarily filtered to six months and the default overwrite loader is run against the real target table:

1. Batch 1 writes months 1-6.
2. Batch 2 writes months 7-12.
3. Batch 2 replaces the target, so months 1-6 are lost.

Therefore, a multi-batch historical rebuild into the same physical target must use one of these two patterns:

| Pattern | Safe for cumulative six-month rebuild? | Notes |
|---|---:|---|
| Default full overwrite into real target | No | Last chunk wins; earlier chunks are removed. |
| Delete/insert by explicit date window | Yes | Target keeps history outside the current chunk. |
| Load each chunk into separate physical chunk tables, then union/swap | Yes | More setup, useful if final table swap is required. |

For conditional historical work, preferred pattern is explicit date-window delete/insert.

**DateRange framework proc constraint:**

```text
@MinDate = DATEADD(DAY, @NumberofDays, GETDATE())
DELETE/INSERT WHERE date >= @MinDate
```

No absolute `[Start, End)` parameters. Historical absolute windows need adhoc SQL.

---

## Confirmed Raw Source Finding

Read-only source audit from `2023-01-01` through `2026-07-08` showed:

| Scope | Duplicate 5-key groups | Extra rows | Notes |
|---|---:|---:|---|
| Recent 15-day operational window | 0 | 0 | Clean for daily operation. |
| 2023-05-01 through 2026-07-08 | 0 | 0 | Clean by 5-key. |
| 2023-04-16 through 2023-05-01 exclusive | 1,512 | 1,512 | Historical exception, same 5-key but different payload. |

The April 2023 exception is not exact full-row duplication. It contains same 5-key with different attribute and forecast values, for example different `dfcFCSTTypeCode`.

Decision:

- Treat the 5-key as the target grain for current and future operation.
- Do not silently rebuild the April 2023 exception without a business rule if the rebuild starts before `2023-05-01`.
- Prefer historical start `2023-05-01` if rebuild ever required.
- If `2023-01-01` is required, handle April 2023 as a documented exception.

---

## Target Direction (CHỐT)

Staging removed for this source. **Direct EL** (no Source_Wrk wrapper).

```text
Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
  -> ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
  -> ForecastHistory_Enh.ForecastDemandMonthly
  -> ForecastAccuracy_DW facts

Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
  -> InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly
  -> InventoryHistory_Enh.ForecastSnapshotWeekly
  -> Inventory Health downstream tables
```

Sqlproj reference:

```sql
[$(Databricks)].[SupplyChain_Enh].[DemandForecastSnapshotDaily]
```

Optional wrapper path (`Source_Wrk`) was considered then **rejected** by Aric.

---

## What Must Not Happen

- Do not run normal full PL between view repoint and parity PASS.
- Do not default-overwrite a six-month filtered view into the real full history table.
- Do not change KPI business formulas during cutover.
- Do not use dry-run window `2026-06-24`–`2026-07-09` for FDM/KPI (no ForecastCycle in that window → no-op).
- Do not multi-year rebuild without a failed parity probe.

---

## FDM / KPI cadence note

`ForecastDemandMonthly` and `FactForecastKpi` are **ForecastCycle** snapshot tables (monthly cycle dates), not daily continuum.

Example recent physical snapshots: `2026-06-15`, `2026-05-16`, `2026-04-20`, …

DateRange `@NumberofDays` must cover the last cycle date (e.g. -30 / -45).

---

## Conditional historical chunks (only if needed later)

Main historical range if rebuild triggered:

```text
2023-05-01 <= snapshot < 2026-01-01
```

| Phase chunk | Start inclusive | End exclusive | Purpose |
|---:|---|---|---|
| 2.1 | 2023-05-01 | 2023-07-01 | Shorter first clean chunk after April exception. |
| 2.2 | 2023-07-01 | 2024-01-01 | Second half of 2023. |
| 2.3 | 2024-01-01 | 2024-07-01 | First half of 2024. |
| 2.4 | 2024-07-01 | 2025-01-01 | Second half of 2024. |
| 2.5 | 2025-01-01 | 2025-07-01 | First half of 2025. |
| 2.6 | 2025-07-01 | 2026-01-01 | Second half of 2025. |

Load pattern per chunk: window DELETE+INSERT on physical targets (not full overwrite).  
Order inside chunk: FDM + FSW → FactForecastKpi → AwdHelper/IH confirmed only.

---

## Run Phases (original, with ticks)

### Phase 0: Freeze And Preparation — [x] mostly DONE

Goal:

- Stop accidental normal full-pipeline runs while mixed logic risk exists.
- Prepare controlled scripts / cutover.

Actions:

1. [x] Confirm no full refresh pipeline is currently running.
2. [x] Confirm no long-running foreground user request (QI sample).
3. [x] Confirm official 5-key grain.
4. [x] Freeze business transformation formulas (no formula edits in cutover).
5. [x] Understand parameterized window delete/insert vs DateRange relative.
6. [x] Parity / DQ probe scripts executed (read-only).
7. [x] Query Insights awareness documented.

Do not:

- run normal full PL during cutover window,
- run default overwrite against only one six-month filtered window,
- change KPI business formulas,
- remove staging live before parity scripts/deploy order ready.

### Phase 1: Small Dry Run — [ ] SKIPPED as historical rebuild dry-run

Original recommended window `2026-06-24`–`2026-07-09` is **invalid for FDM/KPI** (0 ForecastCycle rows).

**Replacement proof path:**

1. Live deploy direct-EL views.
2. Parity gate on cycle `2026-06-15` + FSW Saturdays.
3. DateRange relative prove-out (already validated once on Staging path 2026-07-09; re-run after EL path).

### Phase 2: Historical Backfill Main Run — [ ] CONDITIONAL

Do not start unless post-cutover parity fails on a business cycle date.

### Phase 3: 2026 Transition Window — [ ] CONDITIONAL

Same gate as Phase 2.

### Phase 4: Daily DateRange / incremental — [ ] TODO after cutover parity

Tables:

| Table | Date column | Suggested NumberofDays |
|---|---|---:|
| `ForecastHistory_Enh.ForecastDemandMonthly` | `Snapshot` | -30 or -45 |
| `InventoryHistory_Enh.ForecastSnapshotWeekly` | `SnapshotDate` | -15 to -30 |
| `ForecastAccuracy_DW.FactForecastKpi` | `Snapshot` | same as FDM |

Pre-check: source window count > 0; EL 5-key dups = 0.  
Post-check: phys == view in window; outside window preserved.

---

## Related docs

- Cutover checklist (primary next steps): `2026-07-09-demandforecast-staging-drop-cutover-checklist.md`
- Load pattern live validation: `2026-07-09-supplychain-load-pattern-live-validation-results.md`
- Load pattern bench: `2026-07-09-supplychain-load-pattern-bench-results.md`

---

## Unified production DateRange -30 (2026-07-10)

Operational standard after cutover + history rebuild:

- FDM / FSW / KPI all use **DateRange -30** (one rule).
- Wrappers already call `usp_UpdateCuratedTableFromView_DateRange` with `-30`.
- TableDictionary metadata updated from `overwrite` → `DateRange` + `DateKey` + `DateRangeDays=30`.
- Historical multi-year work remains adhoc absolute windows (not DateRange GETDATE).
