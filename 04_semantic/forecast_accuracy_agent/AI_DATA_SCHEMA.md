# AI Data Schema Recommendation

Configure this manually in `Prep data for AI`. It is guidance, not a security boundary.

For certified numeric answers, pair this metadata with the fixed-template
`Forecast Governed Metrics` Agent Flow. AI-prepared metadata and instructions
improve retrieval/interpretation; they do not make NL2DAX deterministic.

## Include

- Named business measures from `_Measure_ForecastAccuracy`.
- `DimForecastHorizon[HorizonCode]`.
- `DimCalendar[FSCMonthYearName]`, `FSCQuarterYearName`, and `FSCYearName`.
- Business fields from `DimProduct` and `DimWarehouse`.
- `FactForecastActual[StatusCode]` and `FactForecastActual[VersionName]` only for operational/version questions.

## Exclude

- All hidden fact keys and raw numeric columns.
- Snapshot Date and sort/helper columns.
- Any cost, price, load timestamp, source-selection, or technical lineage field.
- All raw `FactForecastKpi` fields, including Snapshot, numeric inputs, and validity flags.

## Synonyms

| Object | Synonyms |
| --- | --- |
| `Qty_Forecast` | forecast, consensus forecast, forecast units |
| `Qty_Actual` | KPI actual, accuracy denominator |
| `Pct_MPE` | bias, signed error percent, over forecast, under forecast |
| `Pct_wMAPE` | weighted MAPE, weighted forecast error |
| `Pct_ForecastAccuracy` | accuracy, forecast accuracy percent |
| `ProcessValueAdd` | PVA, process improvement versus naive |
| `DimForecastHorizon[HorizonCode]` | lag, horizon, forecast lag |
