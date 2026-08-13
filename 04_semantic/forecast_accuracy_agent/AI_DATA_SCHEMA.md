# AI Data Schema Recommendation

Configure this manually in `Prep data for AI`. It is guidance, not a security boundary.

## Include

- All measures from `Forecast Measures`.
- `Forecast Horizon[Forecast Horizon]`.
- `Fiscal Calendar[Fiscal Month End]`, `Fiscal Month`, `Fiscal Quarter`, `Fiscal Year`, and `Fiscal Period` hierarchy.
- Business fields from `Product`, `Warehouse`, and `Customer Group`.
- `Forecast Actuals[Quantity Status]` and `Forecast Actuals[Version Name]` only for operational/version questions.

## Exclude

- All hidden fact keys and raw numeric columns.
- Snapshot Date and sort/helper columns.
- Any cost, price, load timestamp, source-selection, or technical lineage field.
- MAPE and RMSE until governance confirms denominator and zero-handling logic.

## Synonyms

| Object | Synonyms |
| --- | --- |
| `Forecast Quantity` | forecast, consensus forecast, forecast units |
| `Observation Actual Quantity` | KPI actual, accuracy denominator |
| `Actual Demand Quantity` | actual demand, operational actual |
| `Forecast Bias %` | bias, signed error percent, over forecast, under forecast |
| `wMAPE` | weighted MAPE, weighted forecast error |
| `Forecast Accuracy` | accuracy, forecast accuracy percent |
| `Process Value Add` | PVA, process improvement versus naive |
| `Forecast Horizon` | lag, horizon, forecast lag |
