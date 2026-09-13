# Databricks operations

Peer of `../azure/` and `../orchestration/`. Unity Catalog **`edw_dev`** is
mirrored into Fabric OneLake (`[Verified]` scan). Job JSON and notebooks
here are **[Reconstructed]** from mart Bronze — not a workspace export.

Registry: [registry/sources.yaml](registry/sources.yaml) (33 shortcuts).
Check: `python3 03_operations/tools/validate_upstream_slice.py`.
Live workspace URL: [WORKSPACE.md](WORKSPACE.md) (empty until export).

## Cluster posture [Reconstructed, matches TableDictionary intent]

`TableDictionary` has `DataBricksClusterVersion`, `DataBricksNodeType`,
`DataBricksClusterRange` **[Verified columns]**. Nightly jobs use **jobs
compute**, autoscaling, auto-terminate. No all-purpose cluster for these
seven jobs.

Forecast snapshot is the expensive job: partition by snapshot date, 30-day
lookback, never a full-table rewrite.

## Jobs

Landing layouts in [`../azure/landing.yaml`](../azure/landing.yaml):
`current/` for masters, `dt=` for facts, journal `dt=` for CDC.

| Job id | Landing | Spark write | Trigger UTC | Exit |
|---|---|---|---|---|
| `sc_master_dims` | `current/` | overwrite current | 01:10 | yes |
| `sc_codis_orders` | `current/` | overwrite current (not CDC) | 01:25 | yes |
| `sc_sales_invoices` | `dt=` 3 completed months | `replaceWhere InvoiceDate` | 01:40 | yes |
| `sc_forecast_snapshot` | `dt=` 30 days | `replaceWhere dfcSnapshot` | 02:00 | yes |
| `sc_inventory_onhand` | `current/` + `dt=` 30d | overwrite book + `replaceWhere dtea` | 02:20 | yes |
| `sc_supply_inbound` | `current/` + `dt=` 14d MO | overwrite PO/Logility + `replaceWhere OrderDate` | 02:35 | yes |
| `sc_transfers_cdc` | journal `dt=yesterday` | MERGE JOENTT UP/PX/PT | 02:50 | yes |

A filtered `write_delta` on invoices or the 11B snapshot is a bug: it would
drop history outside the window. Validator rejects that.

JSON: `jobs/*.json` (Jobs API 2.1 shape). Clock: [night_order.yaml](night_order.yaml).
Fabric Agent (11 steps) starts **after** this wave; it does not start Spark.

Version / CI/CD / Dev→Prod: [cicd_and_promotion.md](cicd_and_promotion.md).
This git validates the slice (`validate_upstream_slice.py`). It does **not**
publish jobs. Catalog in evidence is `edw_dev`; prod catalog name is
`[Need-verify]`. Spark does not share the Fabric `.dacpac` path.

## What a Spark job is allowed to do

- Read ADLS `raw/` (`current/` or `dt=` — see landing.yaml); write Delta under UC `edw_dev`.
- MERGE/overwrite **one schema.table** that a mart Bronze file names.
- Date-bounded facts use `replaceWhere` on the contract date key.
- Fail if the partition is empty (empty overwrite would look like “load
  succeeded, data vanished”).
- Stop. No streaming query, no `processingTime=0`.

## What it is not allowed to do

- `CREATE OR REPLACE` Gold `ForecastAccuracy_DW.*`
- Call Fabric wrappers
- Drop `JO*` logic on a non-DB2 source
- Scan `DemandForecastSnapshotDaily` without a date predicate
