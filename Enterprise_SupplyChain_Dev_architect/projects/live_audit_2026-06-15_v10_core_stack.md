# Live Audit — 2026-06-15 (v10 Core Stack)

> Scope locked to the live v10 architecture in workspace `Enterprise SupplyChain-Dev` (`c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`): `Enterprise_Lakehouse`, `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse`, the `pl_sc_*` orchestration chain, and the live semantic/report layer.
>
> Evidence source mix:
> - [Verified] live Fabric REST item scans, pipeline definitions, pipeline schedules, and job history
> - [Verified] live Warehouse SQL endpoint queries against `Meta.*`, schema inventory, and object inventory
> - [Verified] live semantic model TMDL exports via Fabric `getDefinition`
> - [Verified] live Power BI REST dataset/report binding checks

## Executive Verdict

| Area | Verdict | Evidence |
|---|---|---|
| v10 core stack | [Verified] live and coherent | `Enterprise_Lakehouse` -> `SupplyChain_Processing_Warehouse` -> `SupplyChain_Gold_Warehouse` is the active serving path. |
| Active marts on v10 control plane | [Verified] 2 marts + shared support tag | After the 2026-06-15 cleanup, active `project` values are `forecast_accuracy`, `inventory_health`, and `shared`. |
| Master scheduling | [Verified] configured but disabled | `pl_sc_master` has 2 Fabric schedules; both `enabled=false`. Recent successful runs are manual. |
| Latest master success | [Verified] 2026-06-04 | `Meta.PipelineRunLog` and Fabric job history both show `pl_sc_master` success on 2026-06-04. |
| Semantic naming | [Verified] docs are behind live state | Live current v10 semantic model is `sc_control_tower`; repo still widely says `sc_forecast_control_tower` and `sc_inventory_health_control_tower`. |
| Report binding | [Verified] stale/legacy | `Forecast Accuracy Gold` report still binds to dataset `Supply Chain Control Tower` (`3eecf594-...`), not `sc_control_tower` (`f06a2361-...`). |
| Control-plane phase 3 docs | [Verified] naming/state drift exists | Live tables are `SourceContract`, `PerformanceBaseline`, `PipelineCostLog`; docs still often use old snake_case names. |

## 1) Live v10 Core Items

| Item | ID | Status |
|---|---|---|
| `Enterprise_Lakehouse` | `584e7d2c-46ca-49dc-bb6c-68df6ef4f424` | [Verified] active source lakehouse / shortcut hub |
| `SupplyChain_Processing_Warehouse` | `c0262cef-b8a7-495f-bccc-53b098c7948c` | [Verified] active staging + silver + meta control plane |
| `SupplyChain_Gold_Warehouse` | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` | [Verified] active Direct Lake serving warehouse |
| `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | [Verified] active top-level orchestrator |
| `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | [Verified] active per-project router |
| `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | [Verified] active staging / reference load |
| `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | [Verified] active silver dispatcher |
| `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | [Verified] active wave executor |
| `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | [Verified] active gold CTAS publish |
| `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | [Verified] active on-demand DQ pipeline |

## 2) How many projects currently use this architecture?

### Business-mart answer

- [Verified] **2 live marts** are using the v10 architecture:
  - `forecast_accuracy`
  - `inventory_health`

### Runtime/control-plane answer

- [Verified] `pl_sc_master` now loops over **3 active project tags** from `Meta.AssetRegistry`:
  - `forecast_accuracy`
  - `inventory_health`
  - `shared`

Interpretation:
- [Verified] `forecast_accuracy` and `inventory_health` are the real consumer-facing marts.
- [Verified] `shared` is the shared dimension/service layer on the same control plane.
- [Verified] `InventoryHistory_Enh` remains a physical Processing schema, but it is no longer used as a live `project` tag.

## 3) Enterprise_Lakehouse Reality Check

### Top-level source domains observed in OneLake

[Verified] `Enterprise_Lakehouse` currently exposes source folders that matter to v10, including:

- `CustomerOrders_AFI`
- `Customers`
- `DemandPlanning_AFI`
- `ItemMaster_AFI`
- `MasterData_DW`
- `Purchasing_AFI`
- `SalesHistory_AFI`
- `SupplyChain_DW`
- `SupplyChain_Enh`
- `SupplyChain_Enh_1`
- `Wholesale_Codis_AFI`
- `Wholesale_DemandPlanning_AFI`
- `Wholesale_ProductSourcing_AFI`
- `Wholesale_Purchasing_AFI`
- `Wholesale_SalesHistory_AFI`

### What active registry lineage says the lakehouse is feeding

[Verified] Active source groups referenced by `Meta.AssetRegistry.source_objects` include:

- `forecast_accuracy`: `Wholesale_Codis_AFI`, `MasterData_DW`, `Customers`, `SalesHistory_AFI`, `CustomerOrders_AFI`, `Wholesale_ProductSourcing_AFI`
- `inventory_health`: `ItemMaster_AFI`, `Purchasing_AFI`, `Wholesale_DemandPlanning_AFI`, `CustomerOrders_AFI`
- `shared`: `Purchasing_AFI`, `Wholesale_Codis_AFI`, `MasterData_DW`, `ItemMaster_AFI`, `SupplyChain_Enh`

## 4) Processing Warehouse Reality Check

### Live schema inventory

| Schema | Tables | Views | Procs | Functions |
|---|---:|---:|---:|---:|
| `ReferenceMaster_Enh` | 11 | 11 | 0 | 0 |
| `SalesHistory_Enh` | 4 | 4 | 0 | 0 |
| `ForecastHistory_Enh` | 2 | 2 | 0 | 0 |
| `OpenOrderHistory_Enh` | 2 | 2 | 0 | 0 |
| `InventoryHistory_Enh` | 12 | 12 | 0 | 0 |
| `ProcessingSeed` | 2 | 0 | 0 | 0 |
| `Staging_Wrk` | 1 | 6 | 1 | 0 |
| `Meta` | 23 | 4 | 17 | 3 |

### Control-plane table state

| Table | Live state |
|---|---|
| `Meta.AssetRegistry` | [Verified] active and central source of orchestration truth |
| `Meta.SilverDagWaveRuntime` | [Verified] active and project-aware |
| `Meta.TableDictionary` | [Verified] 66 rows |
| `Meta.SourceFeed` | [Verified] 52 rows |
| `Meta.SourceContract` | [Verified] 674 rows |
| `Meta.SourceContractRun` | [Verified] 0 rows |
| `Meta.PerformanceBaseline` | [Verified] 0 rows |
| `Meta.PipelineCostLog` | [Verified] 0 rows |

Important drift:
- [Verified] live control-plane table names are **CamelCase**, not snake_case.
- [Verified] docs that still say `schema_contracts`, `performance_baseline`, `pipeline_cost_log` are naming-drifted relative to current warehouse.

## 5) Gold Warehouse Reality Check

### Live serving schemas

| Schema | Tables | Views |
|---|---:|---:|
| `ForecastAccuracy_DW` | 4 | 4 |
| `InventoryHealth_DW` | 4 | 4 |
| `Shared_DW` | 3 | 3 |

### Current physical Gold tables

- `ForecastAccuracy_DW.DimCustomerGrouping`
- `ForecastAccuracy_DW.DimForecastHorizon`
- `ForecastAccuracy_DW.FactForecastActual`
- `ForecastAccuracy_DW.FactForecastKpi`
- `InventoryHealth_DW.DimVendor`
- `InventoryHealth_DW.FactInventoryHealthSnapshot`
- `InventoryHealth_DW.InventoryClassificationQtyWeekly`
- `InventoryHealth_DW.InventoryHealthSubStatusWeekly`
- `Shared_DW.DimCalendar`
- `Shared_DW.DimProduct`
- `Shared_DW.DimWarehouse`

## 6) Pipeline Setup Today

### Actual master flow

[Verified] `pl_sc_master`:
1. Logs start via `Meta.usp_LogPipelineRun`
2. Reads ordered active projects from `Meta.AssetRegistry` with `shared` first, then `forecast_accuracy`, then `inventory_health`
3. Runs `pl_sc_mart(project_name)` sequentially
4. Finalizes via `Meta.usp_FinalizePipeline`

### Actual silver flow

[Verified] `pl_sc_silver` is project-aware:
- computes waves via `Meta.usp_ComputeSilverWaves(project)`
- reads `Meta.SilverDagWaveRuntime WHERE project = @project_name`
- invokes `pl_sc_silver_wave` per wave

### Actual staging flow

[Verified] `pl_sc_staging` is now project-filtered in its ReferenceMaster lookup:
- it loads from `Meta.v_sp_registry`
- current SQL filters on `layer IN ('ReferenceMaster')`, `is_active`, and explicit `@project_name`

### Actual gold flow

[Verified] `pl_sc_gold` now looks up:

```sql
SELECT r.physical_schema, r.physical_object, REPLACE(r.legacy_view_name, r.physical_schema + '.', '') AS view_name
FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry r
WHERE r.canonical_layer = 'Gold' AND r.is_active = 1
  AND r.project = '@{pipeline().parameters.project_name}'
ORDER BY CASE WHEN r.physical_object LIKE 'Dim%' THEN 0 ELSE 1 END, r.physical_object
```

This means:
- [Verified] the live `pl_sc_gold` definition is project-filtered again
- [Verified] Gold publish remains pipeline CTAS, not the Silver generic-SP path

### Schedule state

[Verified] `pl_sc_master` has **2 Fabric schedules**, both disabled:

- schedule `6abfdfcf-32ca-41cc-a161-0428c76d49c0` -> `enabled=false`
- schedule `8fd92d70-5c42-4e25-8e25-252d0a4e7ecc` -> `enabled=false`

Both are `Cron` schedules in `SE Asia Standard Time`.

### Latest run evidence

- [Verified] latest successful `pl_sc_master` run: **2026-06-04 02:07:47 UTC -> 03:20:36 UTC**
- [Verified] `Meta.PipelineRunLog` records the same date as `2026-06-04 02:08:18 -> 03:20:28`, `trigger_type='Manual'`, `17 succeeded, 0 failed`
- [Verified] `Meta.PipelineRunLog.project` remains null for historical rows; mart-level logging is still a follow-up item

## 6.1) 2026-06-15 taxonomy fix

[Verified] Live cleanup executed on 2026-06-15:

- `Meta.AssetRegistry.project`: all active `inventoryHistory_Enh` rows normalized to `inventory_health`
- `Meta.SilverDagWaveRuntime`: legacy `inventoryHistory_Enh` runtime rows removed; active runtime now contains only `forecast_accuracy` and `inventory_health`
- `Meta.AssetRegistry.frequency`: inventory `Daily` values normalized to `daily`
- `pl_sc_master`: deterministic project ordering applied
- `pl_sc_staging`: ReferenceMaster lookup re-filtered by `@project_name`
- `pl_sc_gold`: Gold lookup re-filtered by `@project_name`

[Verified] Two metadata hygiene gaps remain after this fix:

- `Meta.AssetRegistry.frequency` still has 2 active `NULL` rows under `inventory_health`
- `Meta.PipelineRunLog.project` is still unpopulated

## 7) Semantic / Report State Today

### Semantic models in workspace

| Model | ID | Current relevance |
|---|---|---|
| `sc_control_tower` | `f06a2361-15fd-4f91-9d37-941fefe62aaf` | [Verified] current v10 semantic model candidate |
| `Supply Chain Control Tower` | `3eecf594-a75e-46ab-9162-63c95ee68e45` | [Verified] legacy/older combined model still present |
| `SupplyChain_Gold` | `b4b302e7-65d7-464d-9083-aaef9d88dfc2` | [Verified] auto/default semantic model |
| `temp_SCPModel`, `test`, `GitTest2` | various | [Verified] non-core clutter / experiment items |

### `sc_control_tower` live shape

[Verified] `sc_control_tower` currently contains:
- 17 tables
- 183 measures
- 20 relationships

Live source bindings include both marts:

- Forecast side:
  - `ForecastAccuracy_DW.DimCustomerGrouping`
  - `ForecastAccuracy_DW.DimForecastHorizon`
  - `ForecastAccuracy_DW.FactForecastActual`
  - `ForecastAccuracy_DW.FactForecastKpi`
- Shared dims:
  - `Shared_DW.DimCalendar`
  - `Shared_DW.DimProduct`
  - `Shared_DW.DimWarehouse`
- Inventory side:
  - `InventoryHealth_DW.DimVendor`
  - `InventoryHealth_DW.InventoryHealthSubStatusWeekly`
  - `InventoryHealth_DW.InventoryClassificationQtyWeekly`
  - `InventoryHealth_DW.FactInventoryHealthSnapshot`

Implication:
- [Verified] the current v10 semantic state is **not** "forecast-only"
- [Verified] it is already a **mixed forecast + inventory** model
- [Verified] repo docs that describe two separate live semantic models are stale relative to the workspace

### Legacy `Supply Chain Control Tower`

[Verified] the older model still contains 19 tables, including both forecast-era and inventory-era content. It remains important because:
- the only report in the workspace still binds to it
- it is a likely source of documentation confusion

### Report binding

[Verified] workspace report `Forecast Accuracy Gold` (`23718231-b394-4b84-a215-50c302043ed0`) is still bound to:

- dataset `Supply Chain Control Tower`
- dataset id `3eecf594-a75e-46ab-9162-63c95ee68e45`

It is **not** currently bound to:

- `sc_control_tower` (`f06a2361-15fd-4f91-9d37-941fefe62aaf`)

## 8) Documentation Drift Found

### Clearly stale now

- [Verified] top-level `README.md` still says live semantic models are `sc_forecast_control_tower` + `sc_inventory_health_control_tower`
- [Verified] `projects/live_audit_2026-06-01.md` still says the same
- [Verified] `projects/forecast/50_semantic.md` still centers `sc_forecast_control_tower`
- [Verified] `projects/inventory_health/50_semantic.md` still centers `sc_inventory_health_control_tower`
- [Verified] multiple docs still use old snake_case phase-3 names instead of live `SourceContract`, `PerformanceBaseline`, `PipelineCostLog`
- [Verified] older docs still cite latest master success as 2026-05-29; current latest success is 2026-06-04

### Core truth to propagate

1. v10 live core stack is `Enterprise_Lakehouse` -> `SupplyChain_Processing_Warehouse` -> `SupplyChain_Gold_Warehouse`
2. live master schedules exist but are disabled
3. latest confirmed master success is 2026-06-04 and manual
4. live current semantic state is centered on `sc_control_tower`, while the report still points to legacy `Supply Chain Control Tower`

## 9) Cleanup Candidates (not deleted in this audit)

### Repo candidates

- `02_Architect_v10_May/` — [Likely] historical duplicate/archive tree
- `serious-check/` — [Likely] investigation workspace, not core architecture docs
- stale per-project semantic docs that still claim separate live semantic models

### Workspace candidates

- semantic models: `temp_SCPModel`, `test`, `GitTest2`
- pipelines: `pipeline1`, `test`, `pl_forecast`, older `pl_*_daily` chain if legacy support is intentionally retired
- notebooks/dataflows prefixed `remove_` or obviously temporary

### Safety

- [Verified] no delete/drop action was executed in this audit
- [Verified] destructive cleanup still needs exact scope confirmation before removal
