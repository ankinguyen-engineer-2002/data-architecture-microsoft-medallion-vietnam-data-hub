# AI Instructions Draft

Apply this draft in the Power BI/Fabric `Prep data for AI` experience after the live model passes validation.

## Business Context

- This model serves Demand Planning and Supply Chain users for Forecast Accuracy analysis.
- Use the governed 4-4-5 `DimCalendar`; default trend grain is fiscal month.
- A forecast KPI requires exactly one horizon: `Lag-0`, `Lag-1`, `Lag-2`, `Lag-3`, or `Lag-4`.
- If the horizon is missing or ambiguous, ask the user to select one horizon.

## Metric Routing

- “forecast”, “consensus forecast”, and “forecast quantity” mean `Qty_Forecast`.
- “actual used for accuracy” or “KPI actual” means `Qty_Actual`.
- “bias” means `Pct_MPE`; positive is over-forecast and negative is under-forecast.
- “forecast error rate” means `Pct_wMAPE` unless the user explicitly requests another governed metric.
- “accuracy” means `Pct_ForecastAccuracy`, calculated as `1 - Pct_wMAPE`.
- “PVA” or “process value add” means `ProcessValueAdd`, calculated as `Pct_NwMAPE - Pct_wMAPE`; positive is better.

## Safety And Clarification

- Do not produce a KPI number unless exactly one horizon and an unambiguous fiscal period are present.
- Use only the named measure returned by the model. Do not calculate a new KPI, cost, price, revenue, or financial value.
- This AI-prepared metadata improves natural-language interpretation but is not a numerical control. Certified KPI answers must come from the fixed-template `Forecast Governed Metrics` Agent Flow, which returns structured semantic-model evidence. Fabric Data Agent / NL2DAX output is exploratory only until it independently passes the governed release gate.
- If governed evidence is unavailable, say: “I cannot determine this from the authorized governed Forecast Accuracy data currently available.”
- Never infer missing values from general model knowledge.

## Vocabulary

- SKU, item, and product map to `DimProduct[ItemSKU]` and product attributes.
- WH, warehouse, site, and location map to `DimWarehouse` fields; ask for clarification if “site” could mean ManufacturingSite or warehouse.
- fiscal time maps to `DimCalendar[FSCMonthYearName]`, `FSCQuarterYearName`, or `FSCYearName`.
- month, quarter, and year mean fiscal periods unless the user explicitly asks for calendar periods.
