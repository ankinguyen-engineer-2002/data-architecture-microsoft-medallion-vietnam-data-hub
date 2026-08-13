# Forecast Accuracy Agent Semantic Model

Purpose-built Direct Lake semantic model for:

`Fabric semantic model -> Fabric Data Agent -> Copilot Studio -> Agent Flows`

## Build Plan

1. Use only governed Forecast Accuracy Gold tables and shared dimensions.
2. Expose business-friendly fields; omit cost and technical/load metadata.
3. Keep one-direction dimension-to-fact relationships.
4. Publish only explicit measures. Forecast KPIs fail closed when the horizon or snapshot cohort is ambiguous.
5. Validate metadata and golden DAX before connecting a Fabric Data Agent.
6. Configure AI instructions, AI Data Schema, synonyms, and Verified Answers in the Power BI/Fabric `Prep data for AI` experience.

## Scope

| Semantic table | Gold source | Purpose |
| --- | --- | --- |
| `Forecast KPI` | `ForecastAccuracy_DW.FactForecastKpi` | Governed forecast-accuracy observations |
| `Forecast Actuals` | `ForecastAccuracy_DW.FactForecastActual` | Invoice, open-order, actual-demand, and forecast-version quantities |
| `Forecast Horizon` | `ForecastAccuracy_DW.DimForecastHorizon` | Lag-0 through Lag-4 selection |
| `Customer Group` | `ForecastAccuracy_DW.DimCustomerGrouping` | Customer grouping for operational actuals |
| `Fiscal Calendar` | `Shared_DW.DimCalendar` | Governed 4-4-5 fiscal period logic |
| `Product` | `Shared_DW.DimProduct` | Forecast-relevant product attributes |
| `Warehouse` | `Shared_DW.DimWarehouse` | Forecast-relevant warehouse attributes |
| `Forecast Measures` | Calculated utility table | Explicit governed measures only |

## KPI Safety Contract

Forecast KPI measures return `BLANK()` unless all conditions are true:

- exactly one horizon is selected;
- the horizon is `Lag-0` through `Lag-4`;
- at least one non-null forecast snapshot exists;
- every selected fiscal month has exactly one snapshot cohort.

Use `KPI Context Message` to explain a refusal. The model intentionally excludes MAPE and RMSE until their denominator and zero-handling rules are formally confirmed.

## Deployment

`definition/expressions.template.tmdl` is safe for source control. The live OneLake path is materialized only in a temporary deployment payload.

```bash
python3 deploy_semantic_model.py \
  --workspace-id <workspace-guid> \
  --warehouse-id <warehouse-guid> \
  --folder-id <folder-guid> \
  --execute
```

The script refuses to create a duplicate model with the same display name.
