# ADR-011: DQ System Runtime And Gate Contract (Forecast Accuracy)

## Status

Accepted and amended 2026-08-24. DEV v1.7 is deployed in
`SupplyChain_Processing_Warehouse.DataQuality` (Option A coexist; legacy objects
untouched). The exact-run orchestration gate is now the required scheduler
entrypoint for Forecast publication.

## Context

The Forecast Accuracy mart needs a Data Quality system that is safe to run repeatedly against live DEV without risking full-history scans over billion-row Bronze sources, and whose result contract is strong enough to gate semantic/report publish.

The initial diagnostic implementation was a read-only Python harness. The
current release authority is the persisted T-SQL runtime in DEV. It reads from
three items in `Enterprise SupplyChain-Dev`:

- Bronze: `Enterprise_Lakehouse` (shortcuts)
- Silver: `SupplyChain_Processing_Warehouse`
- Gold: `SupplyChain_Gold_Warehouse`

Canonical rules are in `01_docs/architecture/current/DQ_SYSTEM_STANDARD.md`. This ADR records the runtime and gate decisions that make that standard operational for this mart.

## Decision

### 1. Three gates, no fourth

`BRONZE_TECH`, `GOLD_TECH`, `BRONZE_GOLD`. Silver is a post-failure diagnostic checkpoint only, never a gate.

### 2. Bounded scan is mandatory — no full-history

Every fact/source scan is restricted to the latest three fully completed UTC calendar months, computed once as `[WindowStart, WindowEndExclusive)`.

- Known large ever-growing transactional sources **must** declare a bounding `date_column`. A guard (`KNOWN_LARGE_TRANSACTIONAL` + `_validate_bronze_bounding()`) fails fast at import if one is missing. Current set: `SalesHistory_AFI_Enh.InvoiceDetail`, `SalesHistory_AFI_Enh.InvoiceHeader`, `SupplyChain_Enh.DemandForecastSnapshotDaily`.
- Current-state master/reference sources (cardinality bounded by business key, not time) may be full-scanned per the standard's current-state exemption. `ItemMaster_AFI.ITBEXT` (~3.4M, one row per item-branch) is intentionally excluded from the guard set.
- Verified live row counts (2026-07): DemandForecastSnapshotDaily ~11.0B, InvoiceDetail ~296.7M, InvoiceHeader ~63.2M. Bounding reduces the two Invoice scans to ~5.7M and ~1.9M rows respectively.

### 3. Bronze grain contract

21 DA-defined Bronze grains live in the runner (`BRONZE_CONTRACTS`) and are mirrored into `ETL_Framework.DW_Developer.TableDictionary` as a registry (verified 21/21 match). The runner is the runtime source of grain; the registry is discoverability.

### 4. Gate 3 (BRONZE_GOLD) comparability and scope

- `ForecastQty` (measure) reconciles `DemandForecastSnapshotDaily` → `FactForecastActual`. The Bronze source is treated as a **contractually immutable completed-month partition** (DQ_SYSTEM_STANDARD.md §5 path #1): once a UTC month closes it is never backfilled. Verified live over the bounded window (948M rows): `0` post-close mutation and `dtec == dtea` for every row. This authorizes PASS/FAIL instead of NOT_COMPARABLE.
- `CustomerGroupCoverage` (key) reconciles Bronze `Wholesale_ProductSourcing_AFI.CustomerGrouping` → Gold `DimCustomerGrouping` (lineage via `ReferenceMaster_Enh_Wrk.v_CustomerGrouping`). Both sides are small current-state references, bracketed before/after the run for the common-cut proof.
- `ActualDemandQty` uses the approved tolerance adapter: Bronze `SalesHistory_AFI_Enh.InvoiceDetail.QuantityShipped` by `InvoiceDate`; Gold `FactForecastActual.Qty` where `StatusCode='Invoice'` by `FSCMonthLast`. Its independently normalized aggregate passes with the configured `5%` tolerance. `NaiveForecastQty` remains nonblocking `SKIPPED` because no Bronze counterpart exists.
- Template principle: a flow is reconciled only when it has a direct counterpart in both layers. Custom/derived measures are not forced into the template.

### 5. DataCutId and cut stability

`DataCutId = sha256(flow | window_start | window_end_exclusive | source/target identity)[:32]`. A reconciliation PASS/FAIL is publishable only when the per-flow source/target identity is unchanged across the run (before == after). If either side moved mid-run, the result is demoted to `NOT_COMPARABLE` even on a numeric match.

### 6. Dual-track runtime

- **Live runtime (deployed 2026-07-22, DEV only):** two T-SQL SPs in `SupplyChain_Processing_Warehouse.DataQuality`: `usp_RunForecastAccuracyDQ` runs the three gates and (with `@Persist=1`) writes to `DataQuality.DQForecastAccuracyGate`; `usp_GateForecastAccuracyPublish` reads a persisted run and returns the publish decision. Deployed under `*Gate` names (not the legacy `DataQuality.DQForecastAccuracy`) to coexist non-destructively with the legacy 6-column table — Option A. Legacy objects left untouched.
- **Diagnostic harness:** the Python runner may be used for bounded exploratory
  comparison, but it is not the v1.7 release authority. The T-SQL procedures,
  persisted table, and exact-run gate own the production decision. T-SQL
  compensates for the missing REST workspace guard with scoped object names and
  a `DB_NAME()` assertion.
- **Fabric T-SQL constraints (verified live 2026-07-22):** no table variables / `INSERT..EXEC`; `INSERT <real> SELECT FROM #temp` is rejected inside a proc (distributed-mode compile, error 15816) so persistence walks `#results` row-by-row with `INSERT..VALUES`; cross-DB aggregates assign to scalar `@vars` (dynamic `sp_executesql` with OUTPUT for the Bronze loop); `HASHBYTES('SHA2_256')` reproduces the Python `DataCutId` byte-for-byte.

### 7. Publish decision

`PASS` only when every blocking result passes and all required reconciliations are comparable. `ERROR` and blocking `NOT_COMPARABLE` prevent publish. `SKIPPED` is allowed only for explicitly nonblocking checks with evidence.

### 8. Exact-run orchestration and fail-fast scheduler contract

Schedulers call `DataQuality.usp_RunAndGateForecastAccuracyPublish` immediately
after Forecast Gold. The procedure persists one run, captures its `DQRunId`, and
gates that exact run. It raises SQL error `50003` for `FAIL`, `ERROR`, blocking
`NOT_COMPARABLE`, or a missing persisted run.

SQL Agent, Fabric Data Pipeline, and local manifest execution must stop on that
error. They must not continue to Inventory or publication. Gating an unqualified
"latest" run from a separate session is not an approved orchestration pattern.

### 9. Mutable-Actual invariant and KPI load contract

`ForecastAccuracy_DW.FactForecastKpi` combines forecast snapshots with
`QtyActual` from mutable `ActualDemandMonthly` at target-month grain. A rolling
predicate on snapshot age cannot restate old lags when Actual changes and is
therefore invalid for this fact.

The approved immediate contract is overwrite/full restatement of
`FactForecastKpi`; `TableDictionary.UpdateMethod` must be `overwrite`, with no
`DateKey` or `DateRangeDays`. The generic DateRange loader is not changed because
other immutable snapshot facts may validly use it. A future target-month
restatement loader is allowed only after it refreshes every horizon/snapshot for
each impacted target month and passes the same invariants.

v1.7 adds two blocking controls:

- `ActualEqualityAcrossLags` requires one `QtyActual` value across Lag0-Lag4 for
  each item, warehouse, and target month.
- `CurrentViewParity` compares persisted KPI data with the current work view
  over the bounded impact window.

## Consequences

- Full-history scan risk is eliminated by a fail-fast guard, not convention.
- Gate 3 produces real PASS/FAIL for the two flows that have Bronze counterparts; it no longer emits misleading blocking NOT_COMPARABLE on matching data.
- The current decision is `FAIL` due to four blocking rule failures: InvoiceHeader has 34 in-window grain/full-row duplicates (two checks), DimCustomerGrouping has 35,728 grain duplicates, and FactForecastActual has 19,426 blank customer-group reference misses. These are business/Gold-contract issues, not framework bugs, and the gate correctly keeps reporting them.
- v1.2 hardening fixed the generic full-row duplicate SQL list to use `nvarchar(max)` `STRING_AGG`; this prevents column-list truncation at `DimItemMaster.Series`. Gold operational freshness now evaluates the target-wide `LoadDT`, independently of the bounded fact business window, with future-date exclusion.
- ADR-005 promote checklist ("0 critical failures for 30+ days") is not met while these findings stand, so this mart stays in DEV; no promote to the Enterprise hub.
- Porting to T-SQL requires rewriting the reconciliation CTEs in T-SQL and accepting loss of the REST environment guard.
- Production promotion requires both code deployment and a one-time controlled
  `FactForecastKpi` rebuild. Either action alone is insufficient.
- SQL Agent owners must add the exact-run gate step and configure error `50003`
  as a job failure with stop/retry/alert behavior.
- `TableDictionary.RowCount` is not overwrite-load proof because the current
  generic overwrite procedure does not maintain it; direct counts and DQ parity
  are authoritative.

## Evidence

- Rerun `02_marts/forecast_accuracy/04_quality/runs/20260722T030611Z_forecast_dq_dev.{json,csv}`: decision `FAIL`, 127 checks (`PASS=97`, `SKIPPED=27`, `FAIL=3`).
- Gate 3: `ForecastQty` PASS (cut_stable, DataCutId `c46fa842…`, 21,304,464 = 21,304,464, measure 134,113,588 = 134,113,588, missing/extra 0); `CustomerGroupCoverage` PASS (DataCutId `dfc4d443…`); `ActualDemandQty`/`NaiveForecastQty` SKIPPED nonblocking.
- Bounding verified: InvoiceDetail `three_completed_months` 5,695,965 rows; InvoiceHeader 1,947,875 rows.
- Immutability verified live: 948,863,412 rows over the bounded window, `changed_after_close=0`, `dtec<>dtea=0`.
- TableDictionary registry verified 21/21 grain match with the runner contract.
- Live T-SQL runtime deployed 2026-07-22 and verified against the oracle: dry-run `EXEC usp_RunForecastAccuracyDQ @Persist=0` returned 127 checks (97 PASS / 27 SKIPPED / 3 FAIL), decision `FAIL`, DataCutIds `c46fa842…` and `dfc4d443…` — identical to the oracle. `@Persist=1` wrote 127 rows to `DQForecastAccuracyGate`; `usp_GateForecastAccuracyPublish` returned `FAIL`/`PublishAllowed=0` (100 blocking = 97 pass + 3 fail).
- v1.2 DEV acceptance, `@AsOfDate='2026-07-23'`: dry-run returned `155` checks (`135 PASS / 7 FAIL / 13 SKIPPED / 0 ERROR`) in `290.23s`. Persisted run `2F128108-1C9E-4FBE-A6EA-85EAC8177358` returned the same counts in `390.66s`; `usp_GateForecastAccuracyPublish` returned `FAIL`, `PublishAllowed=0`, `155` results, `136` blocking (`132 PASS / 4 FAIL / 0 ERROR / 0 NOT_COMPARABLE`). All seven Gold targets had a `2026-07-23` operational `LoadDT` and passed the one-day SLA.
- v1.7 positive exact-run evidence, `@AsOfDate='2026-08-24'`: run
  `4A6B4CA0-7CFB-4946-BB3D-7767067D0B63` returned `PASS`, 111 results, and
  107/107 blocking `PASS`. One `NaiveForecastQty` result was intentionally
  nonblocking `SKIPPED`; one stale Bronze snapshot freshness observation was a
  truthful nonblocking `FAIL`. The negative path raised expected error `50003`.

## References

- `01_docs/architecture/current/DQ_SYSTEM_STANDARD.md`
- `01_docs/decisions/ADR-005-enterprise-promote-pathway.md`
- `01_docs/decisions/ADR-010-enterprise-etl-wrapper-runtime-handoff.md`
- `02_marts/forecast_accuracy/04_quality/usp_RunForecastAccuracyDQ.sql`
- `02_marts/forecast_accuracy/04_quality/usp_GateForecastAccuracyPublish.sql`
- `02_marts/forecast_accuracy/04_quality/usp_RunAndGateForecastAccuracyPublish.sql`
- `02_marts/forecast_accuracy/04_quality/DQForecastAccuracyGate.table.sql`
- `02_marts/forecast_accuracy/04_quality/DQForecastAccuracy.table.sql` (superseded repo artifact; do not deploy)
- `00_CONTEXT/current.md`
