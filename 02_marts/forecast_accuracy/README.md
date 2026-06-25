# Forecast Accuracy Mart

Project tag: `forecast_accuracy`  
Serving schema: `SupplyChain_Gold_Warehouse.ForecastAccuracy_DW`  
Shared dimensions: `SupplyChain_Gold_Warehouse.Shared_DW`

## Purpose

Forecast Accuracy compares forecast demand against actual demand at the planning grain used by SupplyChain analytics. It is the first live v10 mart and remains the reference implementation for how source shortcuts, Processing Warehouse Silver, Gold facts, and semantic consumption fit together.

## Layer Map

| Layer | Location | Notes |
|---|---|---|
| Source/Bronze | `Enterprise_Lakehouse` + `ProcessingSeed` | Reads enterprise source domains such as `MasterData_DW`, `Customers`, `SalesHistory_AFI`, `CustomerOrders_AFI`, `Wholesale_Codis_AFI`, and `Wholesale_ProductSourcing_AFI`; `ForecastCycle` and `ForecastHorizon` are Processing-owned seed refs. |
| Silver | `SupplyChain_Processing_Warehouse` | Final tables live in base schemas; work/source views live in matching `_Wrk` schemas. |
| Gold | `SupplyChain_Gold_Warehouse.ForecastAccuracy_DW` | Final serving tables live in base schema; work/source views live in `ForecastAccuracy_DW_Wrk`. |
| Shared Gold | `SupplyChain_Gold_Warehouse.Shared_DW` | Final shared dimensions live in base schema; work/source views live in `Shared_DW_Wrk`. |
| Semantic | `sc_control_tower` direction | Semantic/report objects are shared; Phase 1 did not mutate report bindings. |

## Key Business Outputs

| Object | Role |
|---|---|
| `ForecastAccuracy_DW.FactForecastActual` | Actual demand aligned to forecast comparison grain. |
| `ForecastAccuracy_DW.FactForecastKpi` | Forecast KPI fact. |
| `ForecastAccuracy_DW.DimCustomerGrouping` | Customer group dimension. |
| `ForecastAccuracy_DW.DimForecastHorizon` | Forecast horizon dimension. |
| `Shared_DW.DimCalendar` | Shared date dimension. |
| `Shared_DW.DimProduct` | Shared product dimension. |
| `Shared_DW.DimWarehouse` | Shared warehouse dimension. |

## Source Reality Check

[Verified] Live check on 2026-06-23 found no active Forecast Accuracy runtime/view/registry references to `SupplyChain_Lakehouse`.

Current exceptions to the simple "all source comes from Enterprise_Lakehouse" wording:

- `ReferenceMaster_Enh.ForecastCycle` reads `ProcessingSeed.ForecastCycle`.
- `ReferenceMaster_Enh.ForecastHorizon` reads `ProcessingSeed.ForecastHorizon`.

Known drift:

- `ETL_Framework.DW_Developer.TableDictionary` had one stale metadata row for `ReferenceMaster_Enh.ForecastCycle` pointing to an old SupplyChain Lakehouse seed.
- That row was corrected on 2026-06-23 after approval; current metadata points to `ProcessingSeed.ForecastCycle`.

## Operational Run Order

Do not run alphabetically. Use the manifest in `03_operations/orchestration/forecast_accuracy/`.

Logical order:

1. Shared/reference inputs:
   - calendar
   - product
   - warehouse
   - customer grouping
   - forecast cycle/horizon seeds
2. Silver dependencies:
   - invoice/detail and order source projections
   - `SalesHistory_Enh` outputs
   - `OpenOrderHistory_Enh` outputs
   - `ForecastHistory_Enh` outputs
3. Gold dimensions:
   - `DimCustomerGrouping`
   - `DimForecastHorizon`
   - shared dimensions already ready
4. Gold facts:
   - `FactForecastActual`
   - `FactForecastKpi`
5. Smoke:
   - row count/freshness
   - grain duplicates where applicable
   - 04_semantic/DAX smoke after report-facing changes

## Folder Contract

Current mart SQL is split by operational layer and follows ADR-009.

- [00_source_wrk/](00_source_wrk/) — Processing seed refs and `Staging_Wrk` wrappers.
- [01_bronze/01_enterprise_lakehouse/](01_bronze/01_enterprise_lakehouse/) — active Enterprise Lakehouse shortcut/source objects.
- [01_bronze/02_supplychain_lakehouse/](01_bronze/02_supplychain_lakehouse/) — no active Forecast source; folder exists to make the source split explicit.
- [02_silver/](02_silver/) — active Silver final table contracts and `_Wrk.v_<TableName>` source views.
- [03_gold/](03_gold/) — active Gold/shared final table contracts and `_Wrk.v_<TableName>` source views.
- [04_dq/](04_dq/) — Bronze DQ contracts, exceptions, latest run summary, source evidence, and rerun SQL.
- [05_catalog/](05_catalog/) — machine-readable asset registry, lineage edges, run order, and semantic bindings.

## History

- [99_history/source_project_readme_pre_restructure.md](99_history/source_project_readme_pre_restructure.md) preserves the previous project README.
- [99_history/aggregate_sql_pre_layer_split/](99_history/aggregate_sql_pre_layer_split/) preserves the old aggregate SQL files.
- The full pre-restructure working set remains under `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/projects/forecast/` until final link audit/removal approval.
