# Forecast Accuracy DQ Execution Runbook

Purpose: run Forecast Accuracy DQ, enforce the publish decision, and hand the
same fail-fast contract to SQL Agent or another scheduler.

## Runtime Contract

The runtime lives in `SupplyChain_Processing_Warehouse.DataQuality`:

- `DQForecastAccuracyGate`: persisted result table.
- `usp_RunForecastAccuracyDQ`: three-gate runner; v1.7 emits 111 checks.
- `usp_GateForecastAccuracyPublish`: gates a requested persisted `DQRunId`.
- `usp_RunAndGateForecastAccuracyPublish`: production orchestration entrypoint;
  persists one run, gates that exact run, and raises SQL error `50003` when
  publication is blocked.

A local Python harness may still be used for bounded diagnostics, but it is not
the v1.7 release authority or scheduler entrypoint. The persisted T-SQL runtime
and exact-run gate are authoritative for this contract.

## Required E2E Order

```text
Shared ReferenceMaster
-> Shared Staging
-> Forecast Silver W01
-> Forecast Silver W02
-> Forecast Silver W03
-> Forecast Gold
-> Forecast exact-run DQ gate
-> downstream mart/publication only when PASS
```

The gate must be immediately after Forecast Gold. Do not gate the "latest" run
from another session; use `usp_RunAndGateForecastAccuracyPublish`, which captures
and gates its own exact `DQRunId`.

## Run Modes

Dry-run, no persisted rows:

```sql
EXEC [DataQuality].[usp_RunForecastAccuracyDQ]
    @AsOfDate = NULL,
    @Persist = 0;
```

Official orchestration call:

```sql
EXEC [DataQuality].[usp_RunAndGateForecastAccuracyPublish]
    @AsOfDate = NULL,
    @PipelineRunId = NULL;
```

For diagnostic clients that need output values:

```sql
DECLARE @DQRunId varchar(64), @Decision varchar(32);

EXEC [DataQuality].[usp_RunAndGateForecastAccuracyPublish]
    @PipelineRunId = 'scheduler-run-id',
    @DQRunIdOutput = @DQRunId OUTPUT,
    @DecisionOutput = @Decision OUTPUT;

SELECT @DQRunId AS DQRunId, @Decision AS Decision;
```

`PASS` returns normally. `FAIL`, `ERROR`, blocking `NOT_COMPARABLE`, or a missing
run raises error `50003`. `SKIPPED` is allowed only for explicitly nonblocking
rules.

## SQL Agent Configuration

Add a T-SQL job step after Forecast Gold:

```sql
EXEC [SupplyChain_Processing_Warehouse]
    .[DataQuality].[usp_RunAndGateForecastAccuracyPublish];
```

Configure the step as follows:

- On success: continue to the next approved step.
- On failure: quit the job reporting failure; never continue to Inventory or
  publication.
- Treat error `50003` as a DQ block, not as an ignorable warning.
- Apply DE-owned retry and alert policy. A retry must execute a new exact DQ run;
  it must not reuse a previously passing run.
- Pass the SQL Agent execution identifier as `@PipelineRunId` when the job
  framework supports it.

## v1.7 Blocking Controls

The runner keeps the fixed gates `BRONZE_TECH`, `GOLD_TECH`, and `BRONZE_GOLD`.
Two blocking Gold controls prevent recurrence of the frozen-Actual defect:

- `ActualEqualityAcrossLags`: for the same item, warehouse, and target month,
  `QtyActual` must be identical across Lag0-Lag4.
- `CurrentViewParity`: persisted `FactForecastKpi` must match the current work
  view over the bounded impact window.

All large fact/source scans remain bounded to the latest three fully completed
UTC calendar months. Bronze freshness is an upstream nonblocking observation;
Gold technical and reconciliation controls remain blocking unless explicitly
declared otherwise.

## Verified DEV Evidence - 2026-08-24

- Exact-run positive test: `4A6B4CA0-7CFB-4946-BB3D-7767067D0B63`.
- Decision: `PASS`; `PublishAllowed=true`.
- Results: 111 total; 107/107 blocking `PASS`.
- `NaiveForecastQty`: one intentional nonblocking `SKIPPED` result.
- `DemandForecastSnapshotDaily` freshness: one truthful nonblocking upstream
  `FAIL` (`2026-08-22`, expected `>=2026-08-23`).
- Negative-path test against an older failing run raised expected error `50003`.

## Forecast KPI Load Contract

`FactForecastKpi` must not use a rolling Snapshot DateRange load. The view joins
mutable `ActualDemandMonthly` by target month, so old snapshots must be restated
when Actual changes. Current safe production contract:

- wrapper: `usp_RefreshCuratedTableFromView` overwrite for `FactForecastKpi`;
- `TableDictionary.UpdateMethod = 'overwrite'`;
- `DateKey` and `DateRangeDays` are null;
- one controlled full rebuild is required when deploying the fix to an
  environment that contains mixed Actual vintages.

Do not change the generic DateRange loader globally. `ForecastDemandMonthly`
may retain its separate Snapshot DateRange contract because forecast snapshots
are the immutable measure there; the defect is specific to the Gold KPI fact
that combines old snapshots with mutable target-month Actual.

`TableDictionary.RowCount` is not authoritative for overwrite runs because the
current generic overwrite procedure does not maintain it. Validate with direct
counts, AuditLog completion, and persisted current-view parity DQ evidence.

## Production Deployment Checklist

1. Deploy corrected Forecast Gold wrapper.
2. Synchronize the `FactForecastKpi` TableDictionary contract to overwrite.
3. Deploy `DataQuality` schema/table and all three DQ procedures.
4. Capture a recoverable Gold restore point.
5. Run one controlled full rebuild of only `FactForecastKpi`.
6. Refresh `ReferenceMaster_Enh.CustomerGrouping` and
   `ForecastAccuracy_DW.DimCustomerGrouping` when source/target parity requires
   it.
7. Execute `usp_RunAndGateForecastAccuracyPublish`; require PASS.
8. Add the fail-fast SQL Agent step and verify a controlled negative-path test
   in the target environment.
9. Publish/serve downstream data only after the gate passes.

Deploying code without step 5 leaves stale data in place. Rebuilding without
steps 1-3 and 8 allows the defect or ungated publication to recur.

## References

- `01_docs/architecture/current/DQ_SYSTEM_STANDARD.md`
- `01_docs/decisions/ADR-011-dq-system-runtime-and-gate-contract.md`
- `02_marts/forecast_accuracy/04_quality/DQForecastAccuracyGate.table.sql`
- `02_marts/forecast_accuracy/04_quality/usp_RunForecastAccuracyDQ.sql`
- `02_marts/forecast_accuracy/04_quality/usp_GateForecastAccuracyPublish.sql`
- `02_marts/forecast_accuracy/04_quality/usp_RunAndGateForecastAccuracyPublish.sql`
- `03_operations/orchestration/main/manifest.json`
