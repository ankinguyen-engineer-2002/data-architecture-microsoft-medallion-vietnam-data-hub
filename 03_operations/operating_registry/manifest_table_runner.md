# Manifest Table Runner

Default ad-hoc mart refresh method when Aric says "run" a mart or approved mart set.

## Name

- Short name: **Manifest Table Runner**
- Full name: **manifest-driven table-by-table ETL Framework refresh**

## When to use

Use this for approved ad-hoc refreshes where dependency order and clean audit evidence matter.

Default scope:

1. Read mart `manifest.json` from `03_operations/orchestration/<mart>/manifest.json`.
2. Execute tables sequentially by `sequence.step` and `wave` order.
3. Run each physical table through the Enterprise ETL Framework inner procedure.
4. Verify each table before moving to the next.

## Do not use by default

- Do not trigger Fabric DataPipeline `pl_*` jobs.
- Do not call mart wrapper procedures such as `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Silver`, or `Usp_Refresh_InventoryHealth_Gold`.
- Do not bypass manifest order.

## Tool

```bash
python3 03_operations/tools/run_mart_tables.py \
  --manifest 03_operations/orchestration/forecast_accuracy/manifest.json \
  --manifest 03_operations/orchestration/inventory_health/manifest.json
```

Live execution requires same-conversation approval:

```bash
python3 03_operations/tools/run_mart_tables.py \
  --manifest 03_operations/orchestration/forecast_accuracy/manifest.json \
  --manifest 03_operations/orchestration/inventory_health/manifest.json \
  --execute
```

## Procedure mapping

- `load_type=overwrite` → `[ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]`
- `load_type=incremental` → `[ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]`

`ReferenceMaster_Enh.*` expands to:

- `Calendar`
- `CustomerAccount`
- `CustomerAccountGroup`
- `CustomerGrouping`
- `CustomerShippingLocation`
- `ForecastCycle`
- `ForecastHorizon`
- `ItemMaster`
- `OrderType`
- `Vendor`
- `Warehouse`

## Verification

After every table:

- `DW_Developer.AuditLog` must show latest `Process Complete >= Process Start`.
- `DW_Developer.TableDictionary.Modified` must update for same target.
- Runner stops on first error.

After full run:

- Check Gold fact row counts.
- Check `AuditLog` error rows since run start = 0.
- Update `00_CONTEXT/current.md` with counts, last target, row-count smoke, and risks.

## Last verified run

2026-06-30 ICT:

- `forecast_accuracy`: 26/26 OK.
- `inventory_health`: 34/34 OK.
- Total: 60/60 OK.
- No Fabric `pl_*` pipeline.
- No mart wrapper `Usp_Refresh_*`.
- Audit errors since run start: 0.
- Smoke row counts:
  - `ForecastAccuracy_DW.FactForecastActual`: 163,034,308
  - `ForecastAccuracy_DW.FactForecastKpi`: 122,773,233
  - `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding`: 3,849,998
  - `InventoryHealth_DW.FactInventoryHealthSnapshot`: 3,327,322
