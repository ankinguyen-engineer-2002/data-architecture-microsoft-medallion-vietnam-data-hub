# Canonical DQ System Standard

> Status: canonical and mandatory
> Effective: 2026-07-23 ICT
> Initial implementation scope: Mart A `forecast_accuracy`

This file is the only architecture source of truth for the SupplyChain DQ system. Any older DQ table, view, procedure, config model, generated rule package, result artifact, audit script, lineage node, or archived implementation is superseded and must not be reused.

## 1. Fixed Architecture

Each mart owns exactly:

1. One persisted DQ result table in schema `DataQuality`.
2. One mart-specific runner stored procedure or equivalent runner source.
3. Exactly three gates: `BRONZE_TECH`, `GOLD_TECH`, and `BRONZE_GOLD`.

Mart A uses `DataQuality.DQForecastAccuracyGate`. A future mart uses the same column contract in its own table, for example `DataQuality.DQInventoryHealthGate`. Inventory Health DQ is not part of the current implementation scope.

Do not create separate persisted DQ config, run, asset, policy, control-point, exception, or detail-result tables. In particular, `DQAsset`, `DQPolicySet`, `DQControlPoint`, `DQRun`, free-form `RuleConfig`, and per-layer DQ history tables are not part of this standard.

Silver is not a fourth gate. Silver can only be queried as a diagnostic checkpoint after a failed `BRONZE_GOLD` control to locate whether divergence first appears in Bronze-to-Silver, Silver aggregation, or Silver-to-Gold processing. Weekly Silver outputs are nonblocking unless an approved semantic consumer contract explicitly makes them blocking.

## 2. Fixed Taxonomy

`GateCode` is closed and has exactly these values:

| GateCode | Purpose |
|---|---|
| `BRONZE_TECH` | Validate the approved source object contract before downstream publication. |
| `GOLD_TECH` | Validate the final serving object contract and mart invariants. |
| `BRONZE_GOLD` | Reconcile selected business measures and key coverage from source to serving layer. |

`CheckType` is template-owned and closed:

| GateCode | Allowed CheckType |
|---|---|
| `BRONZE_TECH` | `OBJECT`, `KEY`, `GRAIN`, `FRESHNESS` |
| `GOLD_TECH` | `KEY`, `GRAIN`, `REFERENCE`, `INVARIANT`, `FRESHNESS` |
| `BRONZE_GOLD` | `RECONCILIATION` |

Mart-specific business checks must be expressed as `GOLD_TECH.INVARIANT`. A mart must not invent another `GateCode` or `CheckType` without first changing this shared standard.

`RuleCode` is a deterministic instance identifier, not another taxonomy. Its required format is:

```text
<GateCode>.<ObjectOrFlow>.<CheckType>
```

If an approved on-demand diagnostic is persisted, it sets `ParentRuleCode` to the failed parent `RECONCILIATION` rule. `HASH`, `FULL OUTER JOIN`, and two-way `EXCEPT` are investigation evidence techniques, not check types or automatic gates.

## 3. Mart Declaration

A mart runner declares only the information needed to instantiate the fixed template:

- Bronze and Gold object names.
- Natural key and expected grain.
- Freshness mode, ownership, and approved recency signal.
- Business measure expression.
- Approved common reconciliation grain.
- Numeric tolerance and blocking severity.
- Approved `INVARIANT` expressions where required.

Declarations must be concise, allow-listed SQL in the mart runner source. Do not store arbitrary executable SQL in JSON or a metadata table. The DQ runner must not replay the full Silver/Gold business transformation merely to prove itself.

For Forecast Accuracy, the direct source path from `SupplyChain_Enh.DemandForecastSnapshotDaily` uses the DA-defined five-column grain:

```text
dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups
```

### Bronze grain contract

Bronze shortcuts have no native primary-key constraint, so Bronze grain is not self-describing. It is established by an explicit Data Architecture (DA) contract, not inferred. A Bronze grain is verified when both hold:

1. The DA-defined natural key is recorded for the source object.
2. Every key column is confirmed to exist live (read-only) before the contract is wired.

Once verified, the Bronze grain contract lives in two mutually consistent places:

- **Runner source (canonical):** the mart runner declares each Bronze object with its DA key as concise, allow-listed data (for example `BRONZE_CONTRACTS` in `run_forecast_dq_dev.py`). This is the executable source of truth for `BRONZE_TECH.KEY/GRAIN/FRESHNESS`.
- **`ETL_Framework.DW_Developer.TableDictionary` (registry mirror):** Bronze objects are registered with `DatabaseName='Enterprise_Lakehouse'` and the same DA key in `PrimaryKey`, so Bronze grain is discoverable alongside Silver and Gold registrations. The runner declaration and the registry row must agree; the registry does not, by itself, authorize a key that the runner has not verified live.

A declared Bronze key that is currently violated (known duplicates) still stays declared so `BRONZE_TECH.GRAIN` reports the real `FAIL` rather than hiding it. `TableDictionary.PrimaryKey` seeds Silver and Gold technical declarations and now also mirrors the DA-verified Bronze grain; it never substitutes for live verification. For Gold, a runner keeps an allow-listed copy of the governed key only to construct safe SQL, and must fail closed before its `KEY` or `GRAIN` query if that copy does not exactly match the active `TableDictionary.PrimaryKey`. A runner must never silently continue with a stale hard-coded Gold key.

### Copy-and-fill mart template

Every new mart must provide this declaration in its runner source before any DQ query or live deployment. Identifiers and expressions are allow-listed source code, never free-form metadata SQL.

```text
mart_code:                 <stable ID, e.g. inventory_health>
result_table:              DataQuality.DQ<Mart>Gate
runner:                    DataQuality.usp_Run<Mart>DQ
publish_gate:              DataQuality.usp_Gate<Mart>Publish
rule_version:              <version>
as_of_date:                <UTC run anchor>
business_window:           latest three fully completed UTC months
freshness_sla_days:        1 unless an approved asset contract says otherwise
freshness_lookback_days:   7 for large transactional sources

bronze_contracts:
  - object:                <Enterprise_Lakehouse.schema.table>
    grain:                 [<DA-verified key columns>]
    date_column:           <required for large transactional source, otherwise null>
    freshness_column:      <approved arrival/effective timestamp, or null>
    freshness_ownership:   upstream_observation
    large_transactional:   <true|false>

gold_contracts:
  - object:                <SupplyChain_Gold_Warehouse.schema.table>
    grain:                 [<governed target key columns>]
    business_window_kind:  <dimension|snapshot_fact|mixed_fact|mart-defined bounded predicate>
    freshness_mode:        <RECENCY_POOL|PIPELINE_HEARTBEAT>
    references:            [<approved dimension/key checks>]
    invariants:            [<approved business formula/domain expressions>]

reconciliation_adapters:
  - <one adapter per direct Bronze-to-Gold business control; section 5 contract>
```

The declaration is incomplete, and the mart cannot enter DQ implementation, if any of the following is missing: DA-verified Bronze grain, temporal bound for a large source, governed Gold grain, a Gold `LoadDT`/approved recency signal, or a comparability strategy for every blocking reconciliation.

### Gate instantiation matrix

| Gate | Unit of application | Required template behavior | Typical blocking policy |
|---|---|---|---|
| `BRONZE_TECH` | Every declared Bronze dependency | Emit `OBJECT`, `KEY`, and `GRAIN`. Emit `FRESHNESS` only when the contract explicitly declares `freshness_column`. | `OBJECT`, `KEY`, `GRAIN` blocking. Declared Bronze freshness is upstream observation and always nonblocking. |
| `GOLD_TECH` | Every declared final Gold target | Run `KEY` and `GRAIN`; emit target-wide `FRESHNESS` only when the Gold contract declares a mart-owned freshness mode. Add applicable approved `REFERENCE` and `INVARIANT` checks. | All emitted Gold technical checks are blocking unless an explicitly approved nonblocking check has evidence. |
| `BRONZE_GOLD` | Each approved direct business control | Run exactly one `RECONCILIATION` row per adapter, with source/target count, distinct-key count, measure, difference, tolerance, missing/extra coverage, and `DataCutId`. | Blocking unless the adapter declaration explicitly marks the flow nonblocking. |

Silver may be queried only after a failed reconciliation to identify where divergence begins. It does not receive a result row merely for being queried and it never becomes a fourth gate.

### Cross-collation key comparisons

Every `REFERENCE` or `RECONCILIATION` join on textual business keys must use an explicit common collation whenever participating Warehouse columns do not share one. The runner source and deployed procedure must use the same expression. For the current Fabric DEV Forecast contract, fact-side key expressions are normalized to `Latin1_General_100_BIN2_UTF8` before comparison with Gold dimensions. This prevents a SQL collation error from being reported as a data-quality `ERROR`; it does not relax case-sensitive business-key matching or convert a genuine unmatched reference into `PASS`.

## 4. One Result Table Contract

Every mart DQ table must expose the following common columns. Compatible Fabric Warehouse types and lengths are selected in implementation, but names and meanings are fixed.

| Column | Required meaning |
|---|---|
| `DQRunId` | Identifier shared by all rows emitted by one mart DQ execution. |
| `DQRunAtUTC` | UTC start timestamp for that execution. |
| `LoadDT` | UTC timestamp when the result row is persisted. |
| `MartCode` | Stable mart identifier, such as `forecast_accuracy`. |
| `PipelineRunId` | Calling orchestration run identifier when available. |
| `DataCutId` | Stable identifier for the exact comparable source/target cut. |
| `RuleVersion` | Version of the runner declaration that produced the row. |
| `GateCode` | One of the three fixed gate codes. |
| `CheckType` | One allowed fixed check type. |
| `Tier` | `1` summary, `2` partition drill, or `3` key/value drill. |
| `RuleCode` | Deterministic rule instance identifier. |
| `ParentRuleCode` | Parent reconciliation rule for diagnostic rows; otherwise null. |
| `ObjectOrFlow` | Stable source, target, or reconciliation-flow identifier. |
| `IsBlocking` | Whether this result participates in the publish decision. |
| `Status` | `PASS`, `FAIL`, `ERROR`, `NOT_COMPARABLE`, or `SKIPPED`. |
| `SourceObject` | Source object or approved upstream anchor, when applicable. |
| `TargetObject` | Target object, when applicable. |
| `WindowStart` | Inclusive beginning of the checked data window, when applicable. |
| `WindowEnd` | Inclusive end of the checked data window, when applicable. |
| `SourceCount` | Source row/group count for reconciliation. |
| `TargetCount` | Target row/group count for reconciliation. |
| `SourceDistinctKeyCount` | Source distinct-key count. |
| `TargetDistinctKeyCount` | Target distinct-key count. |
| `SourceMeasure` | Source measure value. |
| `TargetMeasure` | Target measure value. |
| `Difference` | Observed source-target or actual-expected difference. |
| `Tolerance` | Approved tolerance used by the result. |
| `MissingInGold` | Keys or rows present upstream but absent in Gold. |
| `ExtraInGold` | Keys or rows present in Gold but absent upstream. |
| `ObservedValue` | Compact observed value for technical and diagnostic checks. |
| `ExpectedValue` | Compact expected value or contract. |
| `Evidence` | Bounded JSON/text evidence sufficient to investigate the result. |
| `ErrorMessage` | Bounded execution error detail, otherwise null. |

Summary and diagnostic rows are written to this same table. Do not create another detail table. Evidence must be bounded; do not persist unrestricted row dumps or sensitive payloads.

## 5. Reconciliation Contract

Every Tier 1 `BRONZE_GOLD.RECONCILIATION` result reports the same metric family:

- Source and target count.
- Source and target distinct-key count.
- Source and target business measure.
- Difference and approved tolerance.
- `MissingInGold`.
- `ExtraInGold`.

Reconciliation compares independently normalized Bronze and Gold aggregates at an approved common grain. Normalization is limited to names, types, required filter/window, and aggregation. An intersection-only join is prohibited because it can hide missing data; coverage must be tested in both directions.

Offsetting count or measure errors are not sufficient proof of equality. On failure, the team investigates with AI assistance using the persisted evidence (counts, differences, DataCutId, window metadata).

### Reconciliation Adapter Template

Each reconciliation flow is declared as a structured adapter with exactly these fields:

```text
flow_name:        <stable identifier, e.g. ForecastQty, ActualDemandQty>
bronze_source:    <3-part object name>
bronze_metric:    <aggregate expression, e.g. SUM(ShipQty)>
bronze_filter:    <temporal predicate using the bounded window>
gold_target:      <3-part object name>
gold_metric:      <aggregate expression, e.g. SUM(ActualDemandQty)>
gold_filter:      <temporal predicate using the bounded window>
common_grain:     <approved grain columns for GROUP BY, or NULL for scalar>
tolerance:        <numeric %, default 0 for exact match>
blocking:         <true|false>
comparability:    <immutable_partition | version_pin | watermark | none>
```

The runner template engine executes each adapter identically:

1. Compute `source_value` = bronze_metric with bronze_filter over the bounded window.
2. Compute `target_value` = gold_metric with gold_filter over the bounded window.
3. `difference = ABS(source_value - target_value)`.
4. If `tolerance = 0`: PASS only when `difference = 0`.
5. If `tolerance > 0`: PASS when `difference / NULLIF(source_value, 0) <= tolerance`.
6. If comparability cannot be proven → `NOT_COMPARABLE` (not PASS/FAIL).

Adapters are mart-specific but must follow this template exactly. A mart may not invent free-form SQL inside the adapter; only the declared fields are permitted. New flows require architecture review of the tolerance and comparability strategy.

### Tolerance guidelines

| Scenario | Recommended tolerance |
|---|---|
| Direct pass-through (no transform between layers) | `0` (exact match) |
| Aggregation with filter/dedup in Silver | `5%` (catches major bugs, accepts minor business logic drift) |
| Complex multi-source derivation | `10%` or nonblocking with evidence |

## 6. Data Cut Contract

Bronze and Gold are comparable only when both represent the same `DataCutId`. The runner must record enough identity to reproduce the cut, including the applicable source version/watermark or immutable partition, target load/run identity, and checked window.

Preferred cut anchors, in order, are:

1. Immutable settled partition.
2. Source Delta version/time travel plus target load/run identity.
3. Reproducible source watermark or as-of cutoff.
4. Compact source control aggregate captured before ETL.

If the runner cannot prove a common cut, it returns `NOT_COMPARABLE`. It must not return `PASS` or `FAIL` for data from different cuts.

### Forecast DEV/test window

Forecast Accuracy DEV/test runs are restricted to the latest three fully completed UTC calendar months. The runner computes the half-open interval `[WindowStart, WindowEndExclusive)` once at run start, persists the inclusive `WindowEnd`, and excludes the current incomplete month. Snapshot-bearing Forecast controls apply the interval to `Snapshot` or its exact version representation; actual-demand controls apply it to `FSCMonthLast`. Current-state dimensions may be checked in full because they are not historical fact scans.

For the current Forecast contract, Bronze `dfcSnapshot` is day-level while Gold `FactForecastActual.VersionName` is month-level (`V YYYY.MM`). Reconciliation therefore normalizes both to `SnapshotVersionMonth` and applies the mart's governed fiscal-month eligibility range before aggregation. Comparing the Bronze day directly with the first day parsed from `VersionName`, or omitting the fiscal eligibility filter, creates false missing/extra results and is prohibited.

Every fact or source data query must apply its temporal predicate before grouping, joining, duplicate detection, reconciliation, or diagnostics. A DEV/test runner must not fall back to an unbounded or full-history scan when a temporal column, version, or business window cannot be resolved; the affected rule returns `ERROR`, `NOT_COMPARABLE`, or nonblocking `SKIPPED` as appropriate.

The three-month limit does not by itself prove comparability. A reconciliation may return `PASS` or `FAIL` only when the source partition is contractually immutable or a source version/watermark/control aggregate is pinned and the target load identity remains unchanged for the run. The runner records pre/post target load identity. If either side changes during execution, or source version identity is unavailable, the result is `NOT_COMPARABLE` even when observed measures match.

## 7. FRESHNESS Operational SLA And Ownership

Freshness proves only the observation the runner can actually support with evidence. It does **not** mean every table must contain a record whose business/update date is today. A low-churn Product, Warehouse, category, or reference table remains fresh when its approved refresh path ran successfully and found no source change.

The Forecast mart does not own upstream source schedules or Bronze-ingestion SLAs. Therefore, Bronze freshness is an **upstream observation**, never a publish-blocking assertion. Gold freshness is a **mart operational control**, because the SupplyChain Gold refresh path is in scope.

Gold objects use one explicit, allow-listed freshness mode in their mart runner. Bronze freshness uses one deliberately simpler contract: a Bronze object emits a freshness result only when its declaration names an approved `freshness_column`; do not create a separate DQ policy/config table.

| Freshness mode | Use when | Required evidence and result |
|---|---|---|
| `RECENCY_POOL` | Transactional, snapshot, or target objects where an approved load/effective/event timestamp proves arrival cadence. | Evaluate the curated recency pool below. A missed SLA is raw `FAIL`. On Bronze it is nonblocking upstream observation; on Gold it is blocking. |
| `PIPELINE_HEARTBEAT` | Curated Gold reference/dimension targets that may legitimately have no changed rows, but whose refresh wrapper is expected to run. | Read the latest successful `Process Complete` for the exact target from `ETL_Framework.DW_Developer.AuditLog`. `PASS` means that refresh completed within the target SLA; no new rows is not a failure. Missing/stale completion is a blocking `FAIL`. |
| `NOT_APPLICABLE` | An explicitly approved, low-churn Gold dimension where this mart intentionally does not assert a refresh SLA. | Emit no `GOLD_TECH.FRESHNESS` row. `KEY` and `GRAIN` remain mandatory. The runner contract must name the exception and rationale; it must not be inferred from a table name. |

`PIPELINE_HEARTBEAT` is not a substitute for source-to-target lag proof. Where both source and target watermarks are contractually available, a mart may add an allow-listed `RECENCY_POOL`/watermark comparison under the same `FRESHNESS` check: it passes only when all known source changes are processed within the approved SLA. If that evidence is unavailable, the runner must state the narrower heartbeat claim rather than fabricate synchronization evidence.

### Bronze observation rule

Only Bronze contracts with an explicit approved `freshness_column` emit `BRONZE_TECH.FRESHNESS`. Metadata, master, category, product, warehouse, and other low-churn/reference objects without that declaration emit **no freshness row**. They are still covered by `OBJECT`, `KEY`, and `GRAIN`.

For every emitted Bronze `FRESHNESS` result, retain the truthful raw status:

- `PASS` when the observed timestamp meets the stated threshold.
- `FAIL` when it is older than the threshold or absent from the bounded tail.

Set `IsBlocking = 0` in both cases. The persisted result must include `freshness_scope=upstream_observation` and `ownership=upstream` in `Evidence`. A dashboard may render raw `FAIL` plus `IsBlocking=0` as **WARN — upstream input stale**; `WARN` is a presentation severity, not a new persisted `Status` value.

Do not convert an observed stale input to `PASS`: that would conceal evidence. Do not make it publish-blocking unless the owning source team provides an explicit, approved cross-team SLA and the mart contract is amended.

`RECENCY_POOL` freshness is measured against a curated **recency pool** of column names that represent actual load/effective/event timestamps, not calendar spines or business lifecycle dates. It is never "any column with a date type".

### Recency pool (append-only, standard-level)

```text
dtea, dtec, LoadDT, GoldLoadDT, dfcSnapshot, InvoiceDate, Snapshot
```

New mart onboarding may append entries after architecture review. Calendar spine columns (`DateID`, `FSCMonthLast`, `CalendarDate`, etc.) and lifecycle columns (`DiscontinuedDate`, `MarketEndDate`, etc.) are explicitly excluded — they do not express load recency.

### Algorithm

1. Bronze: emit the check only for a contract with `freshness_column`; use that one declared column. Gold `RECENCY_POOL`: discover date/datetime columns from `INFORMATION_SCHEMA.COLUMNS` and intersect with the recency pool.
2. Reject a declared Bronze freshness column that is not a date/datetime member of the recency pool; this is a runner declaration error, not a reason to invent a substitute column.
3. For each applicable candidate: `MAX(CAST(col AS date)) WHERE col <= @AsOfDate` (excludes future values). Operational freshness is independent of a fact's three-month business-data predicate: it measures the latest successful target/source load, while `KEY`, `GRAIN`, and reconciliation retain their governed business window.
4. Gold `RECENCY_POOL` uses the greatest result across candidates. Bronze has exactly one declared candidate.
5. `PASS` if `observed_freshness >= @AsOfDate - @FreshnessSLADays` (default 1). `FAIL` otherwise.

### Scan cost control

- **Large transactional tables** (those in `KNOWN_LARGE_TRANSACTIONAL` or with a contracted `date_column`): freshness scan is bounded to a recent tail (`WHERE col >= @AsOfDate - @FreshnessLookbackDays`, default 7). If the tail is empty, MAX returns NULL → FAIL (data is stale beyond the lookback).
- **Small/reference tables**: unbounded MAX is acceptable.

### Blocking semantics

- All Bronze `RECENCY_POOL` outcomes → **nonblocking** upstream observation. A stale input is persisted as raw `FAIL` and presented as `WARN`; it cannot fail the mart publish decision.
- Bronze contracts without `freshness_column` → do **not emit** a `FRESHNESS` row. Do not substitute calendar or lifecycle columns merely to create a result.
- Gold `RECENCY_POOL` targets → **blocking** (Gold should reflect the latest refresh).
- Gold `PIPELINE_HEARTBEAT` targets → **blocking**; a successful no-change refresh is `PASS`.
- Gold `NOT_APPLICABLE` targets → do **not emit** a `FRESHNESS` row. This is an explicit mart-contract exception, not a `PASS` and not a missing rule. It does not weaken mandatory Gold `KEY` or `GRAIN` checks.

### Zero-config for new tables

When a new Bronze or Gold target is registered in the runner contract, the author must declare freshness explicitly. Bronze either declares one approved `freshness_column` plus `freshness_ownership=upstream_observation`, or declares none and emits no freshness row. Gold must declare a mart-owned mode (`RECENCY_POOL`, `PIPELINE_HEARTBEAT`, or explicitly approved `NOT_APPLICABLE`). `RECENCY_POOL` activates only when the declared column is in the recency pool; `PIPELINE_HEARTBEAT` requires its explicit evidence rationale in source code; `NOT_APPLICABLE` requires an exact allow-list and rationale in source code. No separate per-table DQ configuration table is permitted.

## 8. Investigation After Failure

When a gate check returns `FAIL`, the DQ system does not automatically drill down to identify root cause. Investigation is performed on-demand by the team (with AI assistance) using the persisted evidence: source/target counts, difference, missing/extra keys, DataCutId, and window metadata.

Silver checkpoint queries may be used during investigation but never create a new gate or persisted DQ surface.

## 9. Execution And Publish Contract

DQ is a mart-specific pipeline activity or procedure after the mart Gold wrapper. It is not embedded inside `ETL_Framework` loader procedures and must not be a synchronous monolithic view scan at the tail of a business refresh wrapper.

The runner returns one latest-run aggregate decision to orchestration:

- `PASS` only when every blocking result passes and all required reconciliations are comparable.
- `FAIL` when at least one blocking rule fails.
- `ERROR` when a required check cannot execute reliably.
- `NOT_COMPARABLE` when a required source/target cut cannot be proven equal.

`ERROR` and blocking `NOT_COMPARABLE` prevent publish. `SKIPPED` is allowed only for explicitly nonblocking checks and must include evidence. Semantic/report refresh occurs only after the approved publish decision passes.

The full Shared -> Forecast -> Inventory flow may run mart gates after each Gold wrapper and a final publish decision after all shared objects stop changing. This does not authorize Inventory DQ implementation in the Forecast-first phase.

### Mandatory runtime workflow

```text
1. Capture UTC @AsOfDate, PipelineRunId, RuleVersion and bounded business window.
2. Validate runner environment and enumerate the declared Bronze/Gold objects.
3. Run BRONZE_TECH for every declared Bronze object.
4. Run GOLD_TECH for every declared final Gold object.
5. Capture source/target identity before each BRONZE_GOLD adapter.
6. Run each bounded, independently normalized BRONZE_GOLD adapter.
7. Recapture identity; emit NOT_COMPARABLE if the cut changed.
8. Persist all detail rows under one DQRunId when @Persist=1.
9. Return one aggregate decision for that exact DQRunId.
10. Publish gate reads that persisted DQRunId; semantic/report refresh runs only on PASS.
```

The runner must return detail rows and the aggregate decision in the same execution. A publish gate must never silently select an unrelated run; orchestration passes the just-returned `DQRunId` whenever possible. A latest-run fallback is allowed only for manual operations.

### Pipeline placement and branch

```text
Gold wrapper for mart
  -> mart DQ runner (@Persist=1)
  -> mart publish gate (explicit DQRunId)
  -> IF PublishAllowed = true: semantic/report refresh
  -> ELSE: stop publication, retain persisted evidence, investigate
```

When shared Gold objects can still be altered by a later mart wrapper, execute the per-mart DQ runner after its wrapper for early evidence and execute one final publish-gate decision only after all shared mutations complete. No DQ runner belongs inside an ETL loader procedure.

### Status and operator action

| Aggregate decision | Meaning | Required workflow action |
|---|---|---|
| `PASS` | All blocking checks pass and required adapters are comparable. | Authorize downstream semantic/report refresh. |
| `FAIL` | At least one blocking business or technical contract failed. | Block publish; investigate persisted evidence. Do not weaken a rule to turn the run green. |
| `ERROR` | A required check or runtime could not execute reliably. | Block publish; repair engine/configuration, then rerun. |
| `NOT_COMPARABLE` | A required source/target cut cannot be proven equal. | Block publish; establish immutable/version/watermark evidence, then rerun. |

### New-mart implementation and acceptance workflow

1. Discover live Bronze dependencies, Gold targets, lineage, row scale, keys, date/load columns, and refresh cadence read-only.
2. Obtain DA-approved Bronze grain and a bounded date column for every large transactional source; verify every declared column exists live.
3. Define governed Gold grains, references, invariants, and target-wide recency signals from active target contracts.
4. Define only direct Bronze-to-Gold adapters. For each blocking adapter, approve common grain, measure/filter, tolerance, and common-cut strategy. Mark unsupported/no-counterpart measures `SKIPPED` nonblocking with a reason.
5. Implement the mart declaration, result table, runner, and publish gate using this fixed template. Do not copy another mart's business expressions.
6. Run a read-only oracle against DEV. Verify bounded scans, expected rule inventory, no `ERROR`, and truthful data findings.
7. Deploy to DEV only after explicit approval. Run live dry smoke, then a persisted run; compare rule inventory/statuses to the oracle.
8. Call the publish gate with the persisted `DQRunId`; verify its decision and `PublishAllowed` match the runner aggregation.
9. Record measured runtime, evidence, known data/contract defects, and rollback/deployment status in the mart ADR/runbook and `CONTEXT.md`.
10. Only then mark the template instantiated for the new mart. A `FAIL` caused by genuine data defects is an accepted fail-closed operational state; an `ERROR` is not acceptance.

## 10. Current Scope And Change Control

The first implementation is Mart A Forecast Accuracy only. The last verified physical Forecast closure contains 21 Bronze sources, 19 Silver curated tables, and 7 Gold serving tables; implementation must re-verify live scope before deployment because repo and live state can drift.

The Forecast DEV/test implementation must enumerate those objects explicitly. Every Bronze dependency receives an `OBJECT` result, but `KEY`, `GRAIN`, and `FRESHNESS` may run only where a source contract has been verified. Silver objects remain diagnostic-only. Every Gold serving table receives key/grain coverage using its governed `TableDictionary.PrimaryKey`; fact checks use the three-month window above.

This standard is repo-only until explicit approval is given for live DDL/DML, procedure deployment, pipeline changes, or replacement of the existing live DQ surface. A live schema migration must account for the existing six-column `DataQuality.DQForecastAccuracy` contract; this document alone does not authorize dropping or altering it.

Changes to the shared taxonomy, one-table-per-mart rule, three-gate rule, data-cut semantics, or publish behavior require architecture review and an update to this file before implementation.
