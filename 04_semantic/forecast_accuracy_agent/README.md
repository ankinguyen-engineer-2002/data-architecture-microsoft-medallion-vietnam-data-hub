# Forecast Accuracy Agent Semantic Model

Portfolio role: DA/Copilot enablement layer over the Forecast Accuracy Gold
contract. It demonstrates semantic metric authority, TMDL/DAX parity, and
governed read-only AI access; it does not replace the underlying data platform.

Purpose-built Direct Lake semantic model for:

`Fabric semantic model -> fixed-template Copilot Studio Agent Flow -> Copilot Studio`

`Forecast Accuracy Agent` Fabric Data Agent may remain attached for labelled
exploration, but is not a certified numeric source: the same Golden question
has returned both `39.6%` and `52.5%` while direct semantic DAX is stable.

## Build Plan

1. Materialize the exact Forecast contract from `sc_control_tower`; the clone contains no non-Forecast tables or relationships.
2. Keep the original table and measure names. The Data Agent source schema, not a renamed semantic model, narrows AI exposure.
3. Keep the nine one-direction Forecast dimension-to-fact relationships.
4. Preserve all 89 Forecast measures exactly. The clone must never recreate or simplify their formulas.
5. Validate metadata and golden DAX before connecting a Fabric Data Agent.
6. Configure AI instructions, AI Data Schema, synonyms, and Verified Answers in the Power BI/Fabric `Prep data for AI` experience.
7. Use `deterministic_metrics/semantic_query_registry.json` and the QuerySpec
   v2 compiler for certified KPI retrieval. `metric_registry.json` is a V1
   deprecation redirect and must never feed a Flow. Instructions/RAG improve
   interpretation; they are not calculation or authorization controls.

## Scope

| Semantic table | Gold source | Purpose |
| --- | --- | --- |
| `FactForecastKpi` | `ForecastAccuracy_DW.FactForecastKpi` | Governed Forecast KPI observations |
| `FactForecastActual` | `ForecastAccuracy_DW.FactForecastActual` | Invoice, open-order, actual-demand, and forecast-version quantities |
| `DimForecastHorizon` | `ForecastAccuracy_DW.DimForecastHorizon` | Lag-0 through Lag-4 selection |
| `DimCustomerGrouping` | `ForecastAccuracy_DW.DimCustomerGrouping` | Customer grouping |
| `DimCalendar` | `Shared_DW.DimCalendar` | Governed 4-4-5 fiscal period logic |
| `DimProduct` | `Shared_DW.DimProduct` | Forecast-relevant product attributes |
| `DimWarehouse` | `Shared_DW.DimWarehouse` | Forecast-relevant warehouse attributes |
| `_Measure_ForecastAccuracy` | Measure table | All 89 Control Tower Forecast measures |

## Parity Contract

The model keeps the exact Control Tower formulas, including fiscal-date logic, snapshot handling, MAPE/RMSE treatment, lag calculations, prior-period measures, formatted measures, and narrative measures. The release gate compares every one of the 89 Forecast measures under multiple completed and future/no-data contexts; an all-blank DAX `ROW()` is treated as a valid all-blank semantic result, not a query error.

The Fabric Data Agent exposes only a focused business schema. `FactForecastKpi`
is retained with unselected columns only because the Fabric Data Agent requires
the measure dependency table to execute the approved measures; this is metadata
completeness, not raw-field AI exposure. It remains disabled for certified
numeric chat routes because Fabric Data Agent Preview has produced
nondeterministic NL2DAX results for an identical Golden question.

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

To round-trip a metadata-only change into the existing model:

```bash
python3 deploy_semantic_model.py \
  --workspace-id <workspace-guid> \
  --warehouse-id <warehouse-guid> \
  --update-existing \
  --execute
```
