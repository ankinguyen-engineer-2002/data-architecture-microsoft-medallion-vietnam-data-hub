# DemandForecast Staging Drop Cutover Checklist

Date: 2026-07-09  
Last status update: 2026-07-10 ICT (completed; superseded as active work plan)

> **Plan status: COMPLETE / ARCHIVED AS ACTIVE PLAN.** All cutover items #1–#17 are complete. The active follow-on performance plan is [`2026-07-10-snapshot-load-pattern-migration-plan.md`](2026-07-10-snapshot-load-pattern-migration-plan.md). Do not reopen this checklist for Purchase Order or Inventory Snapshot migration work.

## Goal

Remove physical `Staging.DemandForecastSnapshotDaily` from the Forecast Accuracy + Inventory Health path.

Keep:

- same silver/gold transform formulas
- results equal to a correct full load from the new source path
- daily DateRange load pattern after cutover

---

## Status board

| # | Item | Status |
|---|---|---|
| 1 | Audit EL 5-key clean (ops + historical probes) | [x] DONE |
| 2 | Audit parity EL ≈ Staging ≈ view ≈ physical (multi-cycle) | [x] DONE |
| 3 | Confirm DateRange live validation already done for FDM/FSW/KPI | [x] DONE (earlier 2026-07-09) |
| 4 | Re-scope: historical multi-year rebuild = conditional only | [x] DONE |
| 5 | Chốt path: **direct EL**, no `Source_Wrk` | [x] DONE |
| 6 | Code: repoint `v_ForecastDemandMonthly` → direct EL | [x] DONE (repo only) |
| 7 | Code: repoint `v_ForecastSnapshotWeekly` → direct EL | [x] DONE (repo only) |
| 8 | Code: `Usp_Refresh_Shared_Staging` → no-op | [x] DONE (repo only) |
| 9 | Mirror architecture `02_marts` + `03_operations/deployment/sqlproj` | [x] DONE |
| 10 | Reject/remove `Source_Wrk` draft | [x] DONE |
| 11 | Live deploy Dev: 2 silver views + Shared_Staging no-op | [x] DONE 2026-07-10 |
| 12 | Parity gate after deploy (`2026-06-15` + FSW Saturdays) | [x] PASS 2026-07-10 |
| 13 | DateRange prove-out FDM / FSW / KPI | [x] PASS 2026-07-10 |
| 14 | Retire DQ rules Staging_Wrk vs Staging physical (DemandForecast) | [x] DONE 2026-07-10 |
| 15 | Drop/archive physical `Staging.DemandForecastSnapshotDaily` | [x] DROPPED 2026-07-10 |
| 16 | Deprecate `Staging_Wrk.v_DemandForecastSnapshotDaily` | [x] DROPPED 2026-07-10 |
| 17 | Historical window rebuild (~5-mo chunks C1–C8) | [x] PASS 2026-07-10 |

---

## Target path (CHỐT: direct EL, no Source_Wrk)

```text
Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
  -> ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
  -> ForecastHistory_Enh.ForecastDemandMonthly
  -> ForecastAccuracy_DW.FactForecastKpi

Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
  -> InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly
  -> InventoryHistory_Enh.ForecastSnapshotWeekly
  -> InventoryHistory_Enh.AwdHelper (cascade if needed)
```

In sqlproj / Fabric warehouse SQL, EL is referenced as:

```sql
[$(Databricks)].[SupplyChain_Enh].[DemandForecastSnapshotDaily]
```

## Decision note

`Source_Wrk` thin wrapper was drafted then **rejected**.

Reason: Aric wants direct EL — no extra hop. Staging drop does not require a replacement schema.

---

## Files changed (repo — not live)

### Canonical (`data-edw-fabric`)

| File | Change |
|---|---|
| `SupplyChain_Processing_Warehouse/ForecastHistory_Enh_Wrk/Views/v_ForecastDemandMonthly.sql` | `FROM [$(Databricks)]...DemandForecastSnapshotDaily` |
| `SupplyChain_Processing_Warehouse/InventoryHistory_Enh_Wrk/Views/v_ForecastSnapshotWeekly.sql` | same direct EL; `SourceSystem='Enterprise_Lakehouse'` |
| `SupplyChain_Processing_Warehouse/dbo/StoredProcedures/Usp_Refresh_Shared_Staging.sql` | NO-OP |

### Architecture mirror

| Path | Change |
|---|---|
| `02_marts/forecast_accuracy/02_silver/ForecastHistory_Enh_Wrk/v_ForecastDemandMonthly.sql` | synced |
| `02_marts/inventory_health/02_silver/InventoryHistory_Enh_Wrk/v_ForecastSnapshotWeekly.sql` | synced |
| `03_operations/deployment/sqlproj/SupplyChain_Processing_Warehouse/...` | synced 3 objects above |
| `Source_Wrk/**` | removed (not used) |

### Docs

| Path | Change |
|---|---|
| this checklist | status board + ticks |
| `01_docs/plans/2026-07-09-demandforecast-historical-backfill-and-load-reset-plan.md` | supersede note + phase ticks |
| `00_CONTEXT/current.md` | status handoff |

---

## What is intentionally NOT changed yet

- KPI business formulas
- Live warehouse objects (still old Staging path until deploy)
- `Staging_Wrk.v_DemandForecastSnapshotDaily` (rollback / legacy DQ)
- physical `Staging.DemandForecastSnapshotDaily` table
- DQ view rules comparing Staging_Wrk vs Staging physical
- historical multi-year rebuild

---

## Live deploy order — COMPLETED 2026-07-10

1. [x] Alter `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly` (direct EL).
2. [x] Alter `InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly` (direct EL).
3. [x] Alter `dbo.Usp_Refresh_Shared_Staging` to no-op.
4. [x] Run **parity gate** before any DateRange load. — PASS 2026-07-10

Do not run full PL between step 1 and parity PASS.

## Parity gate (required PASS)

Use cycle date with ForecastCycle membership, e.g. `2026-06-15`.

Also check FSW Saturdays, e.g. `2026-06-13` and `2026-06-20`.

### A. Source cleanliness

```sql
SELECT COUNT_BIG(*) AS DuplicateGroups
FROM (
  SELECT dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups
  FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
  WHERE CAST(dfcSnapshot AS DATE) = '2026-06-15'
  GROUP BY dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups
  HAVING COUNT_BIG(*) > 1
) d;
```

### B. New path vs old physical baseline

```sql
-- FDM: new view vs current physical
SELECT 'view' AS src, COUNT_BIG(*) rows_cnt, SUM(CAST(QtyForecast AS FLOAT)) sum_qty
FROM ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
WHERE Snapshot = '2026-06-15'
UNION ALL
SELECT 'phys', COUNT_BIG(*), SUM(CAST(QtyForecast AS FLOAT))
FROM ForecastHistory_Enh.ForecastDemandMonthly
WHERE Snapshot = '2026-06-15';

-- FSW
SELECT 'view' AS src, COUNT_BIG(*) rows_cnt, SUM(CAST(ForecastQty AS FLOAT)) sum_qty
FROM InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly
WHERE SnapshotDate = '2026-06-13'
UNION ALL
SELECT 'phys', COUNT_BIG(*), SUM(CAST(ForecastQty AS FLOAT))
FROM InventoryHistory_Enh.ForecastSnapshotWeekly
WHERE SnapshotDate = '2026-06-13';

-- KPI
SELECT 'view' AS src, COUNT_BIG(*) rows_cnt, SUM(CAST(QtyForecast AS FLOAT)) sum_fcst
FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_FactForecastKpi
WHERE Snapshot = '2026-06-15'
UNION ALL
SELECT 'phys', COUNT_BIG(*), SUM(CAST(QtyForecast AS FLOAT))
FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi
WHERE Snapshot = '2026-06-15';
```

PASS criteria:

- EL 5-key dups = 0
- FDM/FSW/KPI view rows+sums = physical rows+sums

If FAIL: stop, do not DateRange, investigate before dropping staging.

## DateRange prove-out after parity PASS

Pre-check:

1. source window count > 0
2. EL 5-key dups = 0 in window

| Table | Date column | NumberofDays |
|---|---|---:|
| `ForecastDemandMonthly` | `Snapshot` | -30 or -45 (cover last ForecastCycle) |
| `ForecastSnapshotWeekly` | `SnapshotDate` | -15 to -30 |
| `FactForecastKpi` | `Snapshot` | same as FDM |

## After stable production

1. [ ] Retire DQ rules requiring Staging physical for DemandForecast.
2. [ ] Pipeline no longer needs Shared Staging for this table (SP already no-op in repo).
3. [ ] Optionally drop/archive `Staging.DemandForecastSnapshotDaily` after 1–2 stable weeks.
4. [ ] Deprecate `Staging_Wrk.v_DemandForecastSnapshotDaily` when no longer needed for rollback/compare.

## Historical rebuild policy

Only if post-cutover parity finds physical history != new view on a business-critical cycle date.

Use adhoc absolute window DELETE+INSERT (DateRange proc is relative to GETDATE only).

## Rollback

1. Repoint FDM/FSW views back to `Staging.DemandForecastSnapshotDaily`.
2. Restore `Usp_Refresh_Shared_Staging` DateRange body.

---

## Production DateRange standard (chốt 2026-07-10)

Unified for all three snapshot-neo tables:

| Table | DateKey | DateRangeDays | Wrapper |
|---|---|---:|---|
| `ForecastHistory_Enh.ForecastDemandMonthly` | `Snapshot` | **-30** | `Usp_Refresh_ForecastAccuracy_Silver_W02` |
| `InventoryHistory_Enh.ForecastSnapshotWeekly` | `SnapshotDate` | **-30** | `Usp_Refresh_InventoryHealth_Silver_W02` |
| `ForecastAccuracy_DW.FactForecastKpi` | `Snapshot` | **-30** | `Usp_Refresh_ForecastAccuracy_Gold` |

Pre-check before load:
1. View window rows > 0
2. EL 5-key dups in window = 0
3. FDM/KPI window contains latest ForecastCycle

Do **not** use FSW-only `-15` for FDM/KPI (can miss monthly cycle).

TableDictionary (`ETL_Framework.DW_Developer.TableDictionary`) synced: `UpdateMethod=DateRange`, `DateRangeDays=30`.
