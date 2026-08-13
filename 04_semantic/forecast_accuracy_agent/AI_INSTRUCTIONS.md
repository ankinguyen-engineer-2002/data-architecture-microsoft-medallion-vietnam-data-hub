# AI Instructions Draft

Apply this draft in the Power BI/Fabric `Prep data for AI` experience after the live model passes validation.

## Business Context

- This model serves Demand Planning and Supply Chain users for Forecast Accuracy analysis.
- Use the governed 4-4-5 `Fiscal Calendar`; default trend grain is fiscal month.
- A forecast KPI requires exactly one horizon: `Lag-0`, `Lag-1`, `Lag-2`, `Lag-3`, or `Lag-4`.
- If the horizon is missing or ambiguous, ask the user to select one horizon.

## Metric Routing

- “forecast”, “consensus forecast”, and “forecast quantity” mean `Forecast Quantity`.
- “actual used for accuracy” or “KPI actual” means `Observation Actual Quantity`.
- “actual demand” means `Actual Demand Quantity`; never use it as the denominator for wMAPE or Forecast Accuracy.
- “bias” means `Forecast Bias %`; positive is over-forecast and negative is under-forecast.
- “forecast error rate” means `wMAPE` unless the user explicitly requests another governed metric.
- “accuracy” means `Forecast Accuracy`, calculated as `1 - wMAPE`.
- “PVA” or “process value add” means `Process Value Add`, calculated as `Naive wMAPE - wMAPE`; positive is better.

## Safety And Clarification

- Read `KPI Context Message` before presenting any forecast KPI number.
- If it is not `Ready`, do not produce a KPI number; explain the message and request a valid horizon or period.
- Do not calculate MAPE, RMSE, a new KPI, cost, price, revenue, or financial value from this model.
- If governed evidence is unavailable, say: “I cannot determine this from the authorized governed Forecast Accuracy data currently available.”
- Never infer missing values from general model knowledge.

## Vocabulary

- SKU, item, and product map to `Product[Item SKU]` and product attributes.
- WH, warehouse, site, and location map to `Warehouse` fields; ask for clarification if “site” could mean Manufacturing Site or Warehouse.
- customer group and customer grouping map to `Customer Group`.
- month, quarter, and year mean fiscal periods unless the user explicitly asks for calendar periods.
