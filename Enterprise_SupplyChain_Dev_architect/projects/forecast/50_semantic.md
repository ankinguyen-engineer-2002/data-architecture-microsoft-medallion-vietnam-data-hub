# 50 — Semantic Model

> Scanned: 2026-05-06 · Updated 2026-06-02 after shared `Shared_DW` dimension cutover, live DAX smoke, and legacy v8 semantic recovery check.
> **Model:** `sc_forecast_control_tower`

## Identity

| Item | Value |
|------|-------|
| Display name | `sc_forecast_control_tower` |
| Item ID | `f06a2361-15fd-4f91-9d37-941fefe62aaf` |
| Item type | `SemanticModel` |
| Workspace | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` (`SupplyChain Dev`) |
| Mode | **Direct Lake** |
| Source | `SupplyChain_Gold_Warehouse` (`98e2a911-5af9-442e-9cc8-5d8dadb8b762`) |
| Source schema | `ForecastAccuracy_DW` |
| Deployed | 2026-05-05 |

## Live Smoke Test (2026-06-01)

Power BI `executeQueries` against `sc_forecast_control_tower` returned:

```text
DimProductRows   = 383,883
DimWarehouseRows = 53
DimCalendarRows  = 21,551
FactKpiRows      = 115,757,696
FactActualRows   = 138,509,914
```

[Verified] The model currently binds `DimCalendar`, `DimProduct`, and `DimWarehouse` to `Shared_DW`, while facts remain in `ForecastAccuracy_DW`.

## Provenance

Cloned from Cherry/BCherry's v8 `Supply Chain Control Tower` (Lakehouse/Spark mode) after closing v8↔v10 ETL parity:

| Object | v8 → v10 |
|--------|---------|
| `DimCalendar` | 10 cols → 74 cols (extended Silver `v_Calendar` from `Enterprise_Lakehouse.MasterData_DW.DimDate`) |
| `FactForecastKpi` | 12 cols → 18 cols (added 7 derived metrics) |
| `DimForecastHorizon` | 2 cols → 3 cols (+`Rank` for sort order) |

See [`30_runbook/17_v8_to_v10_etl_parity.md`](../../30_runbook/17_v8_to_v10_etl_parity.md) (template doc) for full parity story (template-level).

## Model Tables (consumed via Direct Lake from `ForecastAccuracy_DW`)

| Table | Source | Mode |
|-------|--------|------|
| `DimCalendar` | `Shared_DW.DimCalendar` | directLake |
| `DimCustomerGrouping` | `ForecastAccuracy_DW.DimCustomerGrouping` | directLake |
| `DimForecastHorizon` | `ForecastAccuracy_DW.DimForecastHorizon` | directLake |
| `DimProduct` | `Shared_DW.DimProduct` | directLake |
| `DimWarehouse` | `Shared_DW.DimWarehouse` | directLake |
| `FactForecastActual` | `ForecastAccuracy_DW.FactForecastActual` | directLake |
| `FactForecastKpi` | `ForecastAccuracy_DW.FactForecastKpi` | directLake |
| `_Measure` | (calculated table) | local |
| `Param_Horizon` | (parameter table) | local |
| `Param_Period` | (parameter table) | local |

## Relationships (9 total)

```
DimCalendar  1 ← * FactForecastActual  (FSCMonthFirst → FSCMonthFirst)
DimCalendar  1 ← * FactForecastKpi     (FSCMonthFirst → FSCMonthFirst)
DimProduct   1 ← * FactForecastActual  (ItemSKU → ItemSKU)
DimProduct   1 ← * FactForecastKpi     (ItemSKU → ItemSKU)
DimWarehouse 1 ← * FactForecastActual  (WarehouseCode → WarehouseCode)
DimWarehouse 1 ← * FactForecastKpi     (WarehouseCode → WarehouseCode)
DimCustomerGrouping  1 ← * FactForecastActual  (CustomerGroupCode → CustomerGroupCode)
DimCustomerGrouping  1 ← * FactForecastKpi     (CustomerGroupCode → CustomerGroupCode)
DimForecastHorizon   1 ← * FactForecastKpi     (HorizonCode → HorizonCode)
```

## DAX Measures (35 total)

Hosted in `_Measure` calculated table. Categories:

| Category | Measure examples | Count |
|----------|-----------------|------:|
| Volume | Actual Demand, Forecast Demand, Naive Forecast | ~5 |
| Forecast accuracy | MAPE, WMAPE, sMAPE | ~6 |
| Bias | Bias, Bias %, Tracking Signal | ~5 |
| Error metrics | RMSE, MAE, Squared Error | ~6 |
| Business sliders | Time-shifted measures (LM, LY, etc.) | ~8 |
| Filter helpers | Has Forecast, Has Actual, Valid Obs | ~5 |

## RLS (Row-Level Security)

| Role | Filter |
|------|--------|
| `All_Permission` | No filter — full read access |

> Production deployment may add region-based / customer-group-based roles via Fabric admin.

## Lineage Edges (live in `Meta.LineageEdge`)

7 directLake edges automatically tracked:

```
Shared_DW.DimCalendar                   → SemanticModel.sc_forecast_control_tower (directLake)
ForecastAccuracy_DW.DimCustomerGrouping → SemanticModel.sc_forecast_control_tower (directLake)
ForecastAccuracy_DW.DimForecastHorizon  → SemanticModel.sc_forecast_control_tower (directLake)
Shared_DW.DimProduct                    → SemanticModel.sc_forecast_control_tower (directLake)
Shared_DW.DimWarehouse                  → SemanticModel.sc_forecast_control_tower (directLake)
ForecastAccuracy_DW.FactForecastActual  → SemanticModel.sc_forecast_control_tower (directLake)
ForecastAccuracy_DW.FactForecastKpi     → SemanticModel.sc_forecast_control_tower (directLake)
```

## Lineage Refresh

The GitHub Action `refresh_lineage_data.yml` discovers Direct Lake edges from semantic model TMDL definition every 10 minutes. It writes to `Meta.LineageEdge` (edge_type = `'semantic'`) — but this requires Service Principal grants on Meta tables, which IT has NOT granted.

**Workaround:** Manual refresh via:
```bash
python3 Enterprise_SupplyChain_Dev_architect/tools/build_semantic_model_lineage.py
```

The Action's CSV export step (which feeds Streamlit lineage explorer) works regardless — it reads existing `Meta.LineageEdge` content. See [`30_runbook/18_lineage_extension_to_semantic_models.md`](../../30_runbook/18_lineage_extension_to_semantic_models.md) (template doc).

## Reports Connected

| Report | Source semantic model |
|--------|----------------------|
| `Forecast Accuracy Gold` | `sc_forecast_control_tower` |

## Other Semantic Models in Workspace (not consumed by `forecast`)

| Model | Status |
|-------|--------|
| `Supply Chain Control Tower` | Cherry's v8 model (Lakehouse mode) — separate ownership. Recovered and scheduled daily on 2026-06-02; latest semantic refresh completed and DAX smoke passed. See [../../30_runbook/19_legacy_v8_daily_refresh_recovery.md](../../30_runbook/19_legacy_v8_daily_refresh_recovery.md). |
| `SupplyChain_Gold` | Auto-generated default by Gold WH |
| `temp_SCPModel` | Temp / experimental |
