# ETL Framework Alignment — Bob's Pattern vs VN Approach

> Detailed comparison + integration plan. **Audience**: VN team + Bob's team review.
>
> **Status**: Proposal · **Author**: Aric Nguyen · **Date**: 2026-05-10

## Executive summary

VN team built an ETL control plane in `Enterprise SupplyChain-Dev` workspace **independently** before fully understanding Bob's `ETL_Framework` pattern. After scan + ADR-008 alignment work (executed 2026-05-10), the two patterns are **logically equivalent** but differ in implementation philosophy:

- **Bob's pattern**: 35 specialized procs, per-table parameter calls, sequential per-domain SP wrappers
- **VN's pattern**: 1 generic SP (`usp_GenericLoad`) covering 8 load patterns, registry-driven dispatch, parallel DAG waves

VN's approach is **arguably more modern and maintainable**, but needs to **integrate with Bob's TableDictionary + AuditLog** at the cross-DB sync layer so domain governance + observability work uniformly across the enterprise.

This doc maps every Bob pattern to VN's equivalent + identifies integration points.

---

## §1. Side-by-side architecture

| Layer | Bob's `ETL_Framework` (`EnterpriseData-Dev`) | VN's `Meta` (`Enterprise SupplyChain-Dev`) |
|-------|------------------------------------------------|---------------------------------------------|
| **Master registry** | `DW_Developer.TableDictionary` (table, 65 cols, manually seeded + per-load updates) | `Meta.TableDictionary` (table, 69 cols = 63 Bob compat + 6 VN ext, seeded from AssetRegistry, auto-updated) |
| **Operational config** | (mixed into TableDictionary) | `Meta.AssetRegistry` (38 cols — separate operational state from descriptive metadata) |
| **Update event log** | `DW_Developer.TableDictionary_UpdateLog` (5 cols) + `_RadarSync` variant | `Meta.TableDictionary_UpdateLog` (9 cols superset) |
| **Audit trail** | `DW_Developer.AuditLog` (4 cols: Description/DateTime/User/Command) | `Meta.AuditLog` (10 cols superset, adds AssetID/RunID/Severity/ErrorMessage/LoadDT) |
| **Run-level audit** | (mixed into AuditLog) | `Meta.RunLog` (separate run-instance log for cross-ref to AssetRegistry) |
| **Time conversion** | `DW_Developer.fn_GetDate(@dt)` returns CSTDateValue | `Meta.ufn_utc_to_cst(@dt)` (equivalent) |
| **Loader procs** | 35 procs in 10 families (12 parquet variants, 6 refresh, 5 alert, etc.) | **1 generic** `Meta.usp_GenericLoad` covering 8 load patterns (overwrite/incremental/upsert/datekey/daterange/identity/cdc/scd2) |
| **Dispatcher pattern** | Per-table `EXEC usp_RefreshCuratedTableFromView 'WH','Schema','Table'` from pipeline | ForEach asset_id from registry → `EXEC usp_GenericLoad` (registry-driven) |
| **Concurrency model** | Sequential within per-domain SP (e.g., `Usp_Refresh_Wholesale_Warehouse` chains 100+ sequential EXECs) | **Parallel** — DAG waves (3 waves), batch=8 within each wave |
| **Dependency tracking** | Manual ordering inside SP body | **Auto** — DAG computed from `depends_on` col in AssetRegistry, materialized in `Meta.SilverDagWaveRuntime` |
| **Smart skip** | None — full refresh every run | `next_run_time` filter in pipeline Lookup → skips assets not due |
| **Scheduling** | Pipeline schedule per wrapper proc | `pl_sc_master` daily 02:00 UTC + cron logic in `Meta.AssetRegistry.cron_expression` |
| **Multi-mart** | Per-domain wrapper procs (sequential) | `pl_sc_mart` ForEach DISTINCT project from registry |
| **Modified deferred sync** | `usp_UpdateTableDictionaryModified` runs on demand to UPDATE Modified from MAX(LastUpdated) of UpdateLog | `Meta.usp_UpdateTableDictionaryModified` (ported, identical pattern) |

## §2. The "1 generic vs 35 specialized" decision

### Bob's approach: 35 specialized procs

```sql
-- Per parquet loader variant (12 of these):
EXEC ETL_Framework.DW_Developer.Usp_CreateTableFromParquet
    @DestinationDatabase='Source_Data',
    @SchemaName='Wholesale_SalesHistory_AFI',
    @TableName='InvoiceDetail',
    @ParquetPath='abfss://...';

-- Per refresh variant (6 of these):
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
    'Wholesale_Warehouse', 'SalesHistory_AFI', 'InvoiceDetail';
```

**Pros**: explicit, debuggable, each proc has clear contract.
**Cons**: 35 procs to maintain; 12 parquet variants are tech debt; per-table calls verbose.

### VN's approach: 1 generic + 8 load patterns

```sql
-- Single proc, registry-driven:
EXEC Meta.usp_GenericLoad
    @target_schema='SalesHistory_Enh',
    @target_table='InvoiceDetailLineLevel';

-- Inside the proc, looks up:
--   AssetRegistry.load_type → dispatches to overwrite/incremental/upsert/cdc/...
--   AssetRegistry.legacy_view_name → SELECT FROM
--   AssetRegistry.primary_key → for upsert/incremental
--   AssetRegistry.watermark_column → for incremental
```

**Pros**: 1 proc to maintain; dispatch logic centralized; new load patterns added once benefit all tables.
**Cons**: dynamic SQL inside proc (harder to debug); single point of failure.

### Verdict
VN's approach scales better for VN team's 33-asset registry. Bob's approach scales better for 1,165 tables across 5 domain teams (each owns slice). **Both legitimate**.

## §3. Integration points (cross-DB sync)

For Bob's team to see VN's load activity in their hub-side tooling (queries against `ETL_Framework.DW_Developer.TableDictionary`), VN must sync:

### Sync direction A: VN → Bob
```sql
-- Inside Meta.usp_LogRun v2 (after load success):
-- Step 1: Local update (already done)
EXEC Meta.usp_UpdateTableDictionary_ModifiedDate ...

-- Step 2 (NEW after Bob unblocks Q1): cross-DB sync to Bob hub
INSERT INTO EnterpriseData-Dev.ETL_Framework.DW_Developer.TableDictionary_UpdateLog
    (DatabaseName, SchemaName, TableName, LastUpdated, UpdateQuery)
VALUES (...);

INSERT INTO EnterpriseData-Dev.ETL_Framework.DW_Developer.AuditLog
    (Description, DateTime, [User], Command)
VALUES (...);
```

**Permission needed** (Bob Q1):
- `INSERT` on `ETL_Framework.DW_Developer.TableDictionary_UpdateLog`
- `INSERT` on `ETL_Framework.DW_Developer.AuditLog`
- `UPDATE` on `ETL_Framework.DW_Developer.TableDictionary` (for Modified col only — or rely on `usp_UpdateTableDictionaryModified` deferred batch sync running periodically)

### Sync direction B: Bob → VN (optional)
If VN wants to see hub-side Modified state for shared masters (Calendar, ItemMaster), can:
- Schedule periodic SELECT FROM Bob's `TableDictionary` → INSERT into VN's `Meta.TableDictionary` shadow
- OR query directly via cross-DB 3-part name when needed

## §4. Naming alignment (already done per ADR-008)

Schema casing: `_ENH`/`_WRK` → `_Enh`/`_Wrk` ✅
View prefix: `vw_*` → `v_*` ✅
Gold suffix: `_DW` ALL CAPS (kept) ✅

Naming for proposed `SupplyChain_Warehouse.<schema>` (TBC by Bob):
- Option A (Retail-pattern): `Forecast_Enh` containing all forecast Silver
- Option B (split): `Forecast_Enh` (facts) + `MasterData_DW` extension (DimForecastCycle/Horizon)

See [`03_naming_conventions.md`](03_naming_conventions.md) for evidence-based pattern.

## §5. Domain team workflow alignment

Bob expects each domain team to:
1. Self-register tables in `ETL_Framework.TableDictionary`
2. Write `_Wrk` views with curated logic
3. Call `usp_RefreshCuratedTableFromView` (or family variant) from a domain-owned pipeline

VN team's workflow today:
1. Register asset in `Meta.AssetRegistry` (richer schema than Bob's TableDictionary)
2. Write `_Enh` views with curated logic
3. Call `Meta.usp_GenericLoad` (registry-driven) from `pl_sc_master`

After full alignment + cross-DB sync:
1. Register asset in `Meta.AssetRegistry` AND auto-replicate to Bob's `TableDictionary` (via `usp_UpdateTableDictionary_ModifiedDate`)
2. Write `_Enh` views
3. Call `Meta.usp_GenericLoad` — Bob's team sees execution via shared `TableDictionary.Modified` + `AuditLog`

→ VN keeps registry-driven advantage, Bob keeps governance visibility.

## §6. What VN must NOT change

- Don't replace `usp_GenericLoad` with Bob's per-table EXEC pattern — that's a regression.
- Don't drop `Meta.RunLog` — Bob's AuditLog mixes run-level + audit messages, ours is cleaner.
- Don't drop DAG waves / parallel batch=8 — Bob's sequential SP is slower.

## §7. What VN should adopt from Bob

- ✅ TableDictionary 65-col schema (done — ADR-008)
- ✅ TableDictionary_UpdateLog event-log pattern (done)
- ✅ AuditLog Description/DateTime/User/Command base (done — superset)
- ✅ Deferred Modified sync via `usp_UpdateTableDictionaryModified` (done)
- ⏳ Cross-DB sync to Bob's hub (pending Bob Q1 permission)
- ⏳ Code review process via ADO `Enterprise Data Services` PRs (pending Q4 access)

## §8. Open questions for Bob

| # | Question | Status |
|---|----------|--------|
| Q1 | Grant write permission on `ETL_Framework.DW_Developer.TableDictionary_UpdateLog` + `AuditLog`? | **Pending Bob** |
| Q2 | DDL spec for `AuditLog` (Bob's actual cols + types)? Want to match exactly | **Pending Bob** |
| Q3 | Owner of `TableDictionary` rows for VN tables — VN seeds? Bob's team seeds? | **Pending Bob** |
| Q4 | Should VN tables be registered with `RefreshRate` from VN's `frequency` col, or with Bob-defined rates? | **Pending Bob** |

## §9. Cross-refs

- Full ETL framework synthesis: [`../projects/etl_framework/SYNTHESIS.md`](../projects/etl_framework/SYNTHESIS.md)
- ADR-008 (executed): [`../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md`](../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md)
- VN execution artifacts: [`../../Enterprise_SupplyChain_Dev_architect/artifacts/bob_alignment_2026-05-10/`](../../Enterprise_SupplyChain_Dev_architect/artifacts/bob_alignment_2026-05-10/)
- VN Meta SPs source: [`../../Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/meta_sps.sql`](../../Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/meta_sps.sql)
