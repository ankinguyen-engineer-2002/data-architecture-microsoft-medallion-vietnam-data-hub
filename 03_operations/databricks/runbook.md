# Databricks runbook — SCM slice

Night clock (UTC, reconstructed cron). Agent 11 starts **after** this wave.

| UTC | Job | Fail closed when |
|---|---|---|
| 01:10 | `sc_master_dims` | any `current/` master empty |
| 01:25 | `sc_codis_orders` | CODIS `current/` empty |
| 01:40 | `sc_sales_invoices` | no invoice files in 3 completed months |
| 02:00 | `sc_forecast_snapshot` | no `dt=` under 30-day lookback |
| 02:20 | `sc_inventory_onhand` | empty book `current/` or empty `dtea` window |
| 02:35 | `sc_supply_inbound` | empty PO `current/` or empty MO window |
| 02:50 | `sc_transfers_cdc` | empty journal `dt=yesterday` |

Do not start Fabric Agent if `sc_forecast_snapshot` or `sc_sales_invoices`
failed. DQ `50003` will not invent rows Spark refused to write.

## Job failed / empty partition

Spark raises `empty partition, refuse overwrite`. That is intentional.
Fix the Azure landing file, rerun **that job only**. Do not run Fabric
wrappers to “fill the gap.”

## Forecast job > 4 hours

Almost always `date_range_days` missing. Table is ~11B rows. Kill the
run, set `--date_range_days 30`, rerun. File an incident if someone
removed `replaceWhere`.

## Invoice Gold missing older months after a “successful” job

`sc_sales_invoices` used `write_delta` instead of `replaceWhere InvoiceDate`.
Older months outside the 3-month window were deleted. Restore from Delta
time travel / rerun is not enough if history was overwritten. Treat as
incident. Validator now fails that pattern.

## Inventory daily snapshot restated for years

`DemandInventorySnapshotDaily` is keyed by `dtea`. Full overwrite of the
UC table restates history. Job must `replaceWhere` 30 days.

## CDC merge duplicates transfers

Journal after-images must be `JOENTT` in (`UP`,`PX`,`PT`) only. If
`JO*` columns appear in UC tables, the drop list drifted from
`usp_IncrementalTableLoad` — fix `_slice_io.JO_DROP` to match the proc.
Deletes (`DL`/`UB`) are **not** this notebook.

## UC mirror stale

Fabric shortcuts read the mirror. If Gold looks yesterday-old but Agent
succeeded, check Databricks mirror `edw_dev` last sync, not the wrapper.

## Wrong catalog after a “promote”

Jobs pin `--catalog edw_dev`. A prod run that still writes `edw_dev` will
move Dev data. Catalog name for prod is `[Need-verify]` —
[cicd_and_promotion.md](cicd_and_promotion.md). Do not invent `edw_prod`.
