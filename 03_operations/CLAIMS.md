# What you may say — and what you may not

Read this before a DE interview. One page.

## Live in this git (Fabric)

Two marts, `_Wrk` → wrappers, **11 SQL Agent steps**, DQ error `50003`,
SQLPROJ. Bronze shortcuts match `02_marts/*/01_bronze/`.

## Verified names (dated checks)

| Item | Source |
|---|---|
| Owner identity, tenant and subscription **DATAWAREHOUSE PROD** (identifiers redacted) | 2026-06-21 |
| Workspaces EnterpriseData, EnterpriseData-Dev, SupplyChain-Dev/Prod, Analytics-Premium | 2026-06-21 |
| SCM-Dev **Contributor**, Analytics **Member**, not Workspace Admin | 2026-08-12 `AGENTS.md` |
| ADLS `ashleydevlake`, ADF `ashleyv2datafactory`, UC `edw_dev` mirror | enterprise scan |
| Forecast snapshot ~11B, DateRange 30 days, CDC `JO*` | ADR-011, loader proc |

## Reconstructed (same Bronze, not an export)

`03_operations/databricks/jobs/*.json` and notebooks. Cron, SKU
`Standard_D8ds_v5`, `abfss://<storage-account>/dt=` paths. Run:

`python3 03_operations/tools/validate_upstream_slice.py`

Say: “mapped from the mart sources.” Do **not** say: “pulled from the
Databricks Jobs API.”

CI/CD: Fabric = SQLPROJ/dacpac (build-only here). Databricks = job/notebook
on an Azure workspace — [databricks/cicd_and_promotion.md](databricks/cicd_and_promotion.md).
Do **not** say one Azure Pipeline deploys both, or that this git CDs Spark.
Catalog in evidence is `edw_dev`. Do **not** name a prod catalog.

Load methods: current-state overwrite (`current/`) vs date-bounded
`replaceWhere` (`dt=`) vs CDC MERGE. Invoices and the ~11B snapshot **must
not** `write_delta` a filtered window — that deletes older history.

## Owner-confirmed, no card in git

Global Administrator and Fabric Administrator via **PIM** (elevate, revert).
Until `azure/ENTRA_EXPORT.md` has a sanitized role screenshot, do not say
“I am Global Admin all day.” Daily work is groups + Contributor.

## Adjacent only

AWS MSK / Flink / plant edge: ADR-012. Not in `03_operations/`.
AIOS: nested MVP. Not the DE identity.

## Fill later (do not invent)

| Slot | File | Replaces |
|---|---|---|
| Entra PIM / directory roles | `azure/ENTRA_EXPORT.md` | owner-confirmed GA |
| Databricks workspace URL / real job name | `databricks/WORKSPACE.md` | reconstructed cron/SKU |
| Databricks prod catalog / second workspace | `databricks/cicd_and_promotion.md` | invented `edw_prod` |
