# forecast — Forecast Accuracy Mart

> **Status:** LIVE · **Gold schema:** `ForecastAccuracy_DW` + shared `Shared_DW` dims · **Last verified:** 2026-06-02 (v10 audit 2026-06-01 + legacy v8 recovery/schedule 2026-06-02)

> Latest cross-mart audit: [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). That file is the source-of-truth for shared dimension cutover, live row counts, pipeline status, and residual cleanup candidates.
>
> **2026-06-15 drift note:** the current live v10 core-stack audit is now [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md). Live workspace naming/report binding has moved beyond the earlier `sc_forecast_control_tower`-only view documented below.

## What

End-to-end Forecast Accuracy analytics mart on Microsoft Fabric. Combines actual sales demand, forecast demand, and naive forecast into a unified Gold serving layer for Power BI Direct Lake reporting via the `sc_forecast_control_tower` semantic model.

## Live infrastructure snapshot

| Item | Value |
|------|-------|
| Workspace DEV | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Processing WH | `c0262cef-b8a7-495f-bccc-53b098c7948c` |
| Gold WH | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` |
| SQL Endpoint | `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com` |
| Schemas | Processing: `Staging_Wrk`, `ProcessingSeed`, `ReferenceMaster_Enh`, `SalesHistory_Enh`, `ForecastHistory_Enh`, `OpenOrderHistory_Enh`, `Meta`; Gold: `ForecastAccuracy_DW`, `Shared_DW` |
| Total tables | **52** (45 Processing: 22 data + 23 Meta; 7 Gold: 2 Fact + 5 Dim) |
| Total views | **34** (27 Processing: 23 data + 4 Meta; 7 Gold) |
| Total SPs / functions | **21** (18 SPs: 17 Meta + 1 Staging_Wrk; 3 Meta functions) |
| Registry assets (active) | **33** (4 LogicalBronze + 4 Staging + 10 ReferenceMaster + 8 DomainSilver + 7 Gold) |
| Lineage edges | See [60_lineage.md](60_lineage.md) and [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md); semantic edges now include shared `DimCalendar`, `DimProduct`, `DimWarehouse`. |
| DQ rules | **30 active** (17 completeness + 13 row_count) / 54 total (12 freshness + 12 uniqueness deactivated) |
| Source contracts | 674 across 52 source feeds |
| Reconciliation rules | 6 (scaffolded) |
| DAG waves | 3 (Wave 0 / Wave 1 / Wave 2 — 8 entries in SilverDagWaveRuntime) |
| Pipelines | 7 v10 pipelines (pl_sc_master, pl_sc_mart, pl_sc_staging, pl_sc_silver, pl_sc_silver_wave, pl_sc_gold, pl_dq_check) |
| Semantic model | `sc_forecast_control_tower` (`f06a2361-15fd-4f91-9d37-941fefe62aaf`) |
| Naming convention | Enterprise ETL-aligned per ADR-008: `_Enh`/`_Wrk` (PascalCase casing), `v_*` view prefix, `_DW` ALL CAPS for Gold |
| Control plane (Enterprise ETL-pattern) | `Meta.TableDictionary` (table, 33 rows, 69 cols ≈ 60% cell fill) + `Meta.TableDictionary_UpdateLog` (event log) + `Meta.AuditLog` (10-col superset of Enterprise ETL's 4-col) |

## Live row counts (2026-06-01 verified)

| Object | Rows | Notes |
|---|---:|---|
| `ForecastAccuracy_DW.FactForecastActual` | 138,509,914 | Direct Lake fact. |
| `ForecastAccuracy_DW.FactForecastKpi` | 115,757,696 | Direct Lake fact. |
| `ForecastAccuracy_DW.DimCustomerGrouping` | 35,617 | Mart-specific dim. |
| `ForecastAccuracy_DW.DimForecastHorizon` | 8 | Mart-specific dim. |
| `Shared_DW.DimCalendar` | 21,551 | Shared dim consumed by forecast semantic. |
| `Shared_DW.DimProduct` | 383,883 | Shared canonical product dim, 218 columns. |
| `Shared_DW.DimWarehouse` | 53 | Shared warehouse dim, display label contract restored. |

Semantic DAX smoke on `sc_forecast_control_tower`:

```text
DimProductRows   = 383,883
DimWarehouseRows = 53
DimCalendarRows  = 21,551
FactKpiRows      = 115,757,696
FactActualRows   = 138,509,914
```

## Historical row counts (2026-05-12, retained for comparison)

### Processing WH (Silver) — 339,034,150 rows

| Schema | Rows | Tables |
|--------|-----:|-------:|
| `Staging_Wrk` | 156,641,390 | 4 |
| `ReferenceMaster_Enh` | 637,360 | 10 |
| `SalesHistory_Enh` | 137,045,519 | 4 |
| `ForecastHistory_Enh` | 44,460,412 | 2 |
| `OpenOrderHistory_Enh` | 249,469 | 2 |

### Gold WH (`ForecastAccuracy_DW`) — 83,973,234 rows

| Type | Rows | Tables |
|------|-----:|-------:|
| Fact (FactForecastActual 47.1M + FactForecastKpi 36.4M) | 83,536,698 | 2 |
| Dim (DimCalendar 21.5K · DimCustomerGrouping 35.6K · DimProduct 379K · DimWarehouse 55 · DimForecastHorizon 8) | 436,536 | 5 |

**Grand total: 423,007,384 rows** across both warehouses.

## Quick links

| Section | Doc |
|---------|-----|
| Workspace + IDs | [00_workspace.md](00_workspace.md) |
| Bronze layer | [10_bronze.md](10_bronze.md) |
| Silver layer (per schema) | [20_silver.md](20_silver.md) |
| Gold layer | [30_gold.md](30_gold.md) |
| Pipelines (IDs + DAG) | [40_pipelines.md](40_pipelines.md) |
| Semantic model | [50_semantic.md](50_semantic.md) |
| Lineage | [60_lineage.md](60_lineage.md) |
| ETL DDL | [etl/](etl/) |

## Known operational state (live 2026-06-01)

| Item | Status |
|------|--------|
| Pipeline schedule | [Need-verify] Fabric item schedule state is not documented as active; latest proof is manual Fabric job history. |
| Last full successful run | `pl_sc_master` run `24942a8b-1750-4f96-9bfc-23fecac90952`, 2026-05-29 16:15:29→17:27:22 UTC, `12 succeeded, 0 failed`. |
| Most recent master job samples | Latest Fabric job instances include `Completed`; older `Failed`/`Cancelled` runs are retained in history and documented in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). |
| Shared dim cutover | [Verified] `DimCalendar`, `DimProduct`, `DimWarehouse` are served from `Shared_DW` in the semantic model. |
| Legacy physical dims | [Need-verify cleanup] `ForecastAccuracy_DW.DimProduct` remains as stale/inactive physical table; do not drop without explicit approval. |
| Alerting | BLOCKED — Mail.Send / Teams permissions not granted (Q4 with Enterprise ETL) |
| CI/CD | BLOCKED — Azure DevOps access not granted (Q4) |
| Schedule trigger auto-deploy | [Need-verify] enable only after schedule ownership is confirmed. |
| DQ history | Latest `pl_dq_check` Fabric job instances include `Completed`; older failures remain in Fabric history and are documented. |

## Legacy v8 operational state (verified 2026-06-02)

The old `Forecast Accuracy Gold` report is still backed by Cherry/BCherry's v8 `Supply Chain Control Tower` semantic model, not the v10 `sc_forecast_control_tower` model. Its recovery and schedule are documented separately in [../../30_runbook/19_legacy_v8_daily_refresh_recovery.md](../../30_runbook/19_legacy_v8_daily_refresh_recovery.md).

| Item | Status |
|---|---|
| Legacy master pipeline | `pl_master_daily` (`4214332e-392f-4d2e-ac11-99094ac33aa7`) |
| Latest full v8 run | [Verified] `Completed`, `2026-06-02T08:49:26.8178242`→`2026-06-02T09:13:06.7218901` UTC |
| Daily schedule | [Verified] enabled, schedule `8667733d-625c-4b7f-8dca-19816c7b0775`, `02:00` `SE Asia Standard Time` |
| Legacy semantic refresh | [Verified] latest `DataFactory` refresh completed `2026-06-02T09:12:33.257Z`; latest `DirectLakeFraming` completed `2026-06-02T09:09:55.097Z` |
| DAX smoke | [Verified] `fact_forecast_kpi` = 37,225,012 rows; `fact_flat_forecast_actual` = 51,015,312 rows; max fiscal month = `2027-04-25` |
| v10 impact | None; no v10 pipeline, warehouse, or semantic model was changed during v8 recovery. |

## Enterprise ETL alignment (2026-05-10) — what changed

Per Enterprise ETL's reply email 2026-05-09 + scan of `EnterpriseData-Dev` workspace (see `_external_refs/enterprisedata-dev-01_docs/`), the following changes were made unilaterally (no Enterprise ETL block needed) — see [ADR-008](../../../docs/decisions/ADR-008-enterprise_etl-alignment-naming-and-integration.md):

### Naming alignment
- Schema casing `_ENH` → `_Enh`, `_WRK` → `_Wrk` (5 schemas renamed via `ALTER SCHEMA TRANSFER`, data preserved)
- View prefix `vw_*` → `v_*` (35 views recreated)
- `_DW` Gold suffix kept ALL CAPS (matches Enterprise ETL's `MasterData_DW`/`SupplyChain_DW` precedent)

### Control plane port (Mức B per ADR-008)
- `Meta.vw_TableDictionary` (view) → `Meta.TableDictionary` (real table, 69 cols = 63 Enterprise ETL-compatible + 6 VN extensions, 60.3% cell fill)
- New `Meta.TableDictionary_UpdateLog` table (mirror Enterprise ETL's append-only event log)
- New `Meta.AuditLog` table (10 cols — superset of Enterprise ETL's 4-col schema)
- 3 new SPs ported from Enterprise ETL's pattern:
  - `Meta.usp_UpdateTableDictionary_ModifiedDate` — per-load INSERT/UPDATE
  - `Meta.usp_UpdateTableDictionaryModified` — batch sync `Modified` from UpdateLog
  - `Meta.usp_RefreshTableStats` — probe `INFORMATION_SCHEMA` for ColumnCount/Fabric defaults
- `Meta.usp_LogRun` v2 — auto-calls `usp_UpdateTableDictionary_ModifiedDate` on every load → TableDictionary stays in sync without manual triggers

### Pipelines patched
- 2 of 7 pipelines had hardcoded refs to old schema/view names (`pl_sc_staging`, `pl_sc_silver_wave`) — patched via Fabric REST API.

### Pending Enterprise ETL (4 questions in `_open_questions_for_enterprise_etl.md`)
- Cross-DB write to `EnterpriseData-Dev.ETL_Framework.DW_Developer.TableDictionary` (Q1)
- `MasterData_DW.DimDate/DimItemMaster` MERGE plan (Q2)
- `SupplyChain_Warehouse` in EnterpriseData hub creation (Q3)
- IT unblock: Mail.Send + Azure DevOps + read access (Q4)

### Artifacts
- `Enterprise_SupplyChain_Dev_architect/artifacts/enterprise_etl_alignment_2026-05-10/` — execution scripts, generator, run logs, backup snapshot
