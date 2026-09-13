# Azure Databricks: CI/CD, version, Dev → Production

Azure Databricks is an **Azure resource** in subscription DATAWAREHOUSE PROD
(Entra login, ADLS, ARM). It is not a third cloud. CI/CD and promotion still
**do not share** the Fabric SQLPROJ / `.dacpac` path.

This page is the operating contract for the **two-mart slice**. Job JSON and
notebooks in this folder are **[Reconstructed]** (ADR-013). Catalog `edw_dev`
and the Fabric mirror are **[Verified]**. Production catalog name and workspace
URL are **[Need-verify]** — see [WORKSPACE.md](WORKSPACE.md) (empty on purpose).

Fabric warehouse CI/CD stays in
[`01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md`](../../01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md).

Speak from [`../CLAIMS.md`](../CLAIMS.md).

## Same Azure, two artifacts

```text
Azure (registration)
  Entra + PIM
  ADLS ashleydevlake
  Azure Databricks workspace ── job/notebook CI/CD ──► UC catalog ── mirror ──► OneLake
  Azure SQL / Agent host     ── schedule            ──► 11 EXEC Fabric
  Fabric capacity            ── SQLPROJ / Fabric Git ──► warehouse objects
```

| Concern | Question | Fabric (this git) | Azure Databricks (this git) |
|---|---|---|---|
| CI/CD **code** | What should the object/job look like? | `.sqlproj` → `.dacpac` → review → publish | Notebook + Jobs 2.1 JSON (or Asset Bundles) → workspace |
| **Runtime** DataOps | Did last night’s data land? | SQL Agent 11 steps + `AuditLog` + DQ `50003` | Seven Spark jobs **EXIT** + UC + mirror |
| Azure **control plane** | Who may enter, bill, keys, network? | Capacity + workspace Git | Workspace ARM, ADLS access connector, Key Vault, Monitor |

A `.dacpac` publish does not create a cluster and does not run `replaceWhere`.
A Spark job deploy does not create `ForecastAccuracy_DW` views.

This repo’s GitHub Actions (`lineage-portal.yml`) deploys **neither** warehouse
SQL nor Databricks jobs. Official Fabric CD, when it exists, is the US EDW
repo / Azure DevOps (`sqlproj_cicd_research.md` Option B: this git is
**build-only**). Databricks CD from this git **does not exist**.

## Three version axes (do not collapse)

| Axis | What changes | Where it lives | In this git |
|---|---|---|---|
| **1. Job code** | Notebook logic, MERGE / `replaceWhere`, `--date_range_days 30` | Git (this folder) or Databricks Repos | `jobs/*.json` + `notebooks/*.py` **[Reconstructed]** |
| **2. Compute** | Databricks Runtime, SKU, Photon, autoscale | Job cluster spec / policy; `TableDictionary` columns | JSON pin `15.4.x-scala2.12`, `Standard_D8ds_v5` **[Reconstructed]**. Columns `DataBricksClusterVersion`, `DataBricksNodeType`, `DataBricksClusterRange` **[Verified]** |
| **3. Data** | Delta tables | UC `catalog.schema.table` + Delta history | Catalog **`edw_dev` [Verified]** mirrored to OneLake. **No production catalog name in git** |

`edw_dev` is a **data catalog**, not a Git branch. Changing a notebook does
not rename the catalog.

Pinning Runtime is compute versioning. Editing a notebook on an all-purpose
cluster is not a release process.

`TableDictionary.DataBricksClusterVersion` records **which runtime a load
used**. It is audit metadata, not a Git tag.

## CI vs CD vs night clock

Same split as Fabric SQL:

```text
CI/CD answers:  what should the job look like?
Runtime answers: did the partition land?
```

```text
PR: notebooks/sc_forecast_snapshot.py
    + jobs/sc_forecast_snapshot.json
      (Runtime pin, --date_range_days 30, --catalog …)
  → CI in this git:
      python3 03_operations/tools/validate_upstream_slice.py
      Bronze 33 = yaml 33 = 7 jobs
      JO_DROP matches usp_IncrementalTableLoad
      every job/notebook labelled [Reconstructed]
  → artifact: job JSON + notebook   [Reconstructed today]
  → CD [Need-verify / not in git]:
      Databricks CLI / Asset Bundles / Jobs API 2.1
      Entra service principal or OIDC (no PAT in git)
      target = Azure Databricks workspace
  → DEV canary (one date partition, never full ~11B)
  → approval → same notebook, --catalog switched
  → night: Databricks job schedule, then EXIT
  → Fabric Agent 11 steps (does not start Spark)
```

Do not put the seven jobs on a Fabric pipeline. Do not use GitHub Actions in
this repo as the nightly clock.

**Identity for CD:** Entra principal on the workspace + UC grants. Secrets in
Key Vault. Same tenant as Fabric; different RBAC plane than SCM-Dev
Contributor.

## Dev → Production

Fabric already has Dev/Prod **workspaces** (SCM-Dev vs SCM, EnterpriseData-Dev
vs EnterpriseData). Hub DEV hosts **Mirror Databricks `edw_dev`** (scan).
ADR-005 is a **SQL / semantic** promote path. It does not deploy Spark.

Databricks promotion is **not** “copy the Dev Delta table into Prod” and
**not** a Fabric Deployment Pipeline.

```text
DEV  [Verified catalog]
  UC edw_dev
  jobs --catalog edw_dev
  mirror → EnterpriseData-Dev → SCM-Dev shortcuts
  Agent 11 on SCM-Dev

PROD [Need-verify name]
  usually a second UC catalog (often edw / edw_prod — NOT in this git)
  and/or a second Azure Databricks workspace
  same notebook, --catalog changed
  mirror → Fabric PROD hub / SCM prod
  Agent on SCM prod
```

| Move | Meaning | This repo |
|---|---|---|
| Two catalogs, one metastore | Same code, `--catalog` changes | `edw_dev` verified; prod catalog **[Need-verify]** |
| Two Azure workspaces | Separate bill / VNet / prod jobs | Workspace URL **empty** |
| Copy Dev Delta → Prod | Wrong: Prod loads from prod `raw/` | Do not |

**Promote code:** merge Git → CD the job spec onto the prod workspace (approval).
**Promote data:** prod job reads prod landing, `replaceWhere` / MERGE into the
prod catalog.
**Do not:** publish a `.dacpac` and expect Spark to move.

Rollback **code** = redeploy the previous job JSON from Git.
Rollback **data** = Delta time travel or re-run `replaceWhere` for that window.
A dacpac rollback does not rewind the snapshot.

### One slice example

1. Change the 30-day `replaceWhere` on ~11B snapshot rows — **code version**.
2. CI: `validate_upstream_slice.py` must still PASS.
3. CD DEV: `--catalog edw_dev`. Canary **one day**, never a full rewrite.
4. Mirror + SCM-Dev shortcut + Agent + DQ `50003`.
5. After approval: **same notebook**, `--catalog` prod (**[Need-verify]**),
   prod schedule, cluster EXIT.
6. If Gold looks like yesterday but Agent succeeded: check mirror / ADLS, not
   the wrapper ([runbook.md](runbook.md)).

## Night DataOps (not CI)

Landing has **two** layouts ([`../azure/landing.yaml`](../azure/landing.yaml)):

| Layout | Path | Jobs |
|---|---|---|
| Current-state | `.../supplychain/{domain}/{table}/current` | dims, CODIS, ItemBalance, PO, ATP, ITEMBL |
| Dated fact | `.../supplychain/{domain}/{table}/dt=yyyy-mm-dd/` | forecast 30d, invoices 3 completed months, inventory `dtea`, MO 14d, TFR journal |

Clock: [`night_order.yaml`](night_order.yaml) (must match `jobs/*.json` cron — validator).

```text
01:10–02:50 UTC  seven jobs, jobs-compute, auto-terminate
then            mirror edw_dev → OneLake shortcuts
then            SQL Agent 11 steps
```

Date-bounded facts **must** `replaceWhere` on the contract key (`dfcSnapshot`,
`InvoiceDate`, `dtea`, `OrderDate`). A filtered `overwrite` without
`replaceWhere` deletes history outside the window. That is an incident,
not a successful load.

Spark evidence is the Databricks job run + ADLS partition + UC table + (later)
Fabric freshness DQ. An `AuditLog` row alone does not prove the 30-day
snapshot landed.

On-call: [runbook.md](runbook.md) and [`../azure/runbook.md`](../azure/runbook.md).

## What you may say

- Azure Databricks CI/CD is **job/notebook as code** on an Azure workspace,
  Entra identity, not SQLPROJ.
- This git **validates the slice contract** (33 Bronze). It does not publish
  jobs and does not dump the Jobs API.
- Catalog in evidence is **`edw_dev`**. Prod catalog is unnamed here.
- Dev → prod is **catalog/workspace + CD**, not table copy, not dacpac.

## What you may not say

- “One Azure Pipeline deploys Fabric SQL and Databricks jobs.”
- “GitHub Actions in this repo CD Spark.”
- “I promote `edw_prod`.” (name not in git)
- “Repos in the workspace is the source of truth for this operating repo.”
- “CI ran, so last night’s 11B load succeeded.”
