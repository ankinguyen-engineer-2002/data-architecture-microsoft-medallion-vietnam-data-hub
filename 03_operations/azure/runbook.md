# Azure runbook

On-call and admin tickets. Night order: [../runbook.md](../runbook.md).

## Missing night file (landing)

Two layouts ([landing.yaml](landing.yaml)): `current/` (masters, CODIS, book
on-hand) and `dt=yyyy-mm-dd/` (forecast, invoices, inventory daily, journal).

1. Path empty or no parquet → Spark **fail closed**. Do not overwrite Delta.
2. Do **not** start Agent if `sc_forecast_snapshot` or `sc_sales_invoices`
   failed.
3. Fabric Agent on yesterday’s shortcut = stale, not corrupt. DQ freshness
   should fail Forecast if snapshot date does not move.
4. Page source owner (CODIS / planning extract / journal).

## Joiners / leavers

Entra group only. Then Fabric workspace + Gold Read. Not Global Admin.
Analysts never get `raw/`.

## “Need tenant admin”

PIM → **Global Administrator** or **Fabric Administrator** for the
window: new workspace, tenant switch, capacity, UC mirror allow-list,
Conditional Access. Revert. Do not debug `_Wrk` SQL while elevated.

## SQL Agent failed at step 07 (`50003`)

DQ gate blocked Gold publish. Azure SQL Agent did its job. Fix data or
rule in Fabric; do not disable the step. Steps 08–11 must not run.

## Databricks workspace / UC mirror stale

Gold looks yesterday-old, Agent succeeded → check Azure Databricks
workspace + Fabric mirror `edw_dev`, not the wrapper. Capacity and
mirroring are Fabric Administrator + Azure resource health.

## Cost spike

`sc_forecast_snapshot` lost `--date_range_days 30`. Table ~11B rows.
Kill the job. Full rewrite is an incident.

## ADF `ashleyv2datafactory` failing

UKG/Maximo/ServiceNow. Does **not** block these two marts unless a
Bronze file starts referencing those schemas.

## Permission to Gold / OneLake

Contributor on SCM-Dev can edit the model; **cannot** grant Gold
Read/ReadAll or workspace identity (2026-08-12 snapshot). That needs
Workspace Admin or an approved Member/Admin. Escalate with the snapshot
attached, do not self-upgrade the story.
