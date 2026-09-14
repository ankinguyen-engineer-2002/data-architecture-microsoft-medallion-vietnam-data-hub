# Fabric Supply Chain Operating Repository

This is the public, sanitized operating record of a Supply Chain data platform:
Azure landing and access context, Databricks Spark hand-off, Microsoft Fabric
DataOps, two governed marts, semantic models, and bounded Copilot capabilities.
The primary role represented here is **Data Engineer (SCM)** with hands-on
ownership across data platform, DataOps, analytics enablement, and applied-AI
boundaries.

The repository is evidence-led. It distinguishes verified Fabric runtime facts,
owner-confirmed context, reconstructed upstream contracts, adjacent patterns,
and unfinished MVP work.

## What this repository demonstrates

| Layer | Responsibility represented here | Evidence boundary |
|---|---|---|
| Azure control plane | Entra/PIM boundary, subscription/resource registration, ADLS landing, SQL/EDW and Fabric/Databricks hand-off | Verified names and owner-confirmed access are labelled; no ARM export |
| Databricks compute | Seven Spark batch/incremental job contracts for the selected source slice, Delta/Unity Catalog load methods, Dev→Prod guidance | `[Reconstructed]` from mart Bronze contracts; not a Jobs API export |
| Fabric lakehouse | Bronze → Processing/Silver → Gold runtime for Forecast Accuracy and Inventory Health | Current operating implementation in this repository |
| DataOps | Enterprise ETL metadata, SQL Agent order, wrappers, DQ publish gates, audit, lineage, SQLPROJ deployment surface | Current contracts and runbooks; live freshness requires a fresh check |
| Analytics | Gold grains, semantic relationships/measures, RLS/access and report contracts for DAs | Downstream contract; report and permission checks are separate |
| Copilot | Governed Data Agent/Copilot Studio instructions, deterministic tools and presentation routes | Bounded applied-AI surface; never the metric authority |
| AIOS Workbench | Broader AI-native workbench MVP used by development/high-level testing | Separate nested repository; not the primary DE runtime or identity |

## End-to-end operating flow

```text
Azure landing (ADLS, identity, resource boundary)
  → Databricks Spark batch / bounded incremental + DB2/AS400 CDC
  → Fabric Enterprise_Lakehouse (Bronze shortcuts)
  → SupplyChain_Processing_Warehouse (Silver / _Wrk views)
  → SupplyChain_Gold_Warehouse (serving marts)
  → semantic models and reports for analysts / planners
  → governed Copilot, Data Agent and deterministic Agent Flows
```

This is the lakehouse plane represented by this repository. A separate,
adjacent operational plane (AWS MSK/Flink and plant/CDC edge for seconds or
sub-second control) is documented as a boundary decision only; its runtime is
not in this git and no Gold→Flink production feed is claimed.

## Evidence and source-of-truth order

1. [`03_operations/CLAIMS.md`](03_operations/CLAIMS.md) — what is safe to say.
2. [`03_operations/azure/`](03_operations/azure/) — registration, identity, landing and access.
3. [`03_operations/databricks/`](03_operations/databricks/) — selected upstream slice and reconstructed Spark contracts.
4. [`03_operations/orchestration/main/README.md`](03_operations/orchestration/main/README.md) — current 11-step Fabric Agent hand-off.
5. [`forecast_accuracy`](02_marts/forecast_accuracy/README.md) and [`inventory_health`](02_marts/inventory_health/README.md) — mart contracts.
6. [`04_semantic/`](04_semantic/) — governed meaning and report hand-off.
7. [`01_docs/architecture/`](01_docs/architecture/) and [`01_docs/decisions/`](01_docs/decisions/) — rationale and history.

`CONTEXT.md` and [`AGENTS.md`](AGENTS.md) are operating instructions for
agents, not claims of production access.

## Upstream slice: Azure → Databricks

This repository does not pretend to contain the entire enterprise hub. The
selected slice contains **33 Bronze/source contracts** used by the two active
marts, grouped into **seven reconstructed Spark jobs**:

| Job family | Landing / write contract | Downstream purpose |
|---|---|---|
| Master dimensions and CODIS orders | `current/` → overwrite current state | Stable product, warehouse and order keys |
| Sales invoices | three completed months in `dt=` → `replaceWhere` on invoice date | Bounded fact work without deleting history |
| Forecast snapshot | 30-day `dt=` → `replaceWhere` on snapshot date | Forecast-versus-actual planning grain |
| Inventory on-hand | current book overwrite plus bounded daily window | Weekly inventory health snapshots |
| Supply / inbound | current master plus 14-day order window | Purchase-order and supply-plan views |
| Transfers CDC | journal `dt=yesterday` → MERGE using `JO*` operations | DB2/AS400 changes without full replay |

These files are an operating reconstruction from mart Bronze references, load
procedures and dated scans. They are labelled `[Reconstructed]`; exact
workspace URLs, live job names and production catalog remain `[Need-verify]`.

```bash
python3 03_operations/tools/validate_upstream_slice.py
```

Jobs terminate after their work. They are not a 24/7 plant-control stream.
Versioning and promotion are documented in
[`cicd_and_promotion.md`](03_operations/databricks/cicd_and_promotion.md);
Databricks does not share the Fabric `.dacpac` deployment path.

## Fabric runtime and DataOps contract

```text
Enterprise_Lakehouse
  → SupplyChain_Processing_Warehouse
  → SupplyChain_Gold_Warehouse
  → semantic/report contracts
```

The current SQL Agent hand-off contains **11 fail-fast steps**: shared
reference/staging prerequisites, three Forecast Accuracy Silver waves, Forecast
Gold, an exact-run Forecast DQ gate (`50003` blocks continuation), three
Inventory Health Silver waves, and Inventory Gold. The four-wrapper sequence in
the migration closeout is historical Phase 1 context, not the current contract.

`ETL_Framework.DW_Developer` owns `TableDictionary`, `AuditLog` and approved
loaders. Curated objects live in final schemas; source/work logic follows
`<Schema>_Wrk.v_<Table>`. A wrapper or audit row alone does not prove delivery:
validate the target object, expected window/counts, DQ gate and semantic smoke
independently.

Operational entry points:

- [`03_operations/runbook.md`](03_operations/runbook.md) — Azure → Spark → Agent night order.
- [`03_operations/orchestration/main/manifest.json`](03_operations/orchestration/main/manifest.json) — dependency order.
- [`FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md`](FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md) — read-first live sync.

## Data products and consumption

- **Forecast Accuracy** — forecast-versus-actual measures at planning grain,
  with snapshot and horizon semantics in mart and semantic contracts.
- **Inventory Health** — weekly on-hand, supply-plan and risk classification at
  item/warehouse grain, including forward-looking health views.
- **Semantic/report layer** — relationships, reusable measures, date roles,
  Direct Lake bindings, RLS/access expectations and smoke tests. This is the
  KPI meaning authority; Copilot is not.
- **Copilot/Data Agent** — clarification, governed query selection, evidence
  envelopes, deterministic routing and bounded automation around approved
  semantic/Gold surfaces. Prompts, generated SQL and tool output are untrusted.

Start with [`04_semantic/README.md`](04_semantic/README.md) and the
[`forecast_accuracy_agent`](04_semantic/forecast_accuracy_agent/) package.
Rich presentation prototypes and Forecast Exception Alert work are explicitly
marked draft/runtime-blocked where applicable.

## AIOS boundary

[`06_enterprise_control_tower/AIOS-Workspace/`](06_enterprise_control_tower/AIOS-Workspace/)
is a separate nested repository and a later AI-native workbench MVP. It contains
broader capability-platform ideas (intent/semantic tooling, provider ports,
evidence, jobs, visualisation and evaluation surfaces) and is used by
development teams for high-level testing. It is not the source of truth for the
Fabric marts, is not a production control plane, and does not replace the Data
Engineer (SCM) identity represented here.

## Repository map

| Path | Purpose |
|---|---|
| `00_portfolio/` | Sanitized profile, lifecycle, diagrams, evidence matrix and interview navigation |
| `01_docs/` | Architecture, ADRs, migration history, runbooks and technical decisions |
| `02_marts/` | Forecast Accuracy and Inventory Health source-to-Gold contracts |
| `03_operations/` | Azure/Databricks upstream slice, Fabric orchestration, SQLPROJ and operating tools |
| `04_semantic/` | Semantic models, measures, Data Agent/Copilot contracts and tests |
| `05_tools/` | Maintenance, DQ, parity, sync and validation tooling |
| `06_enterprise_control_tower/` | Confidential local Control Tower and nested products; Git-ignored |
| `99_archive/` | Historical/reference material only; never current runtime truth |

Portfolio entry point: [`00_portfolio/00_master_read.md`](00_portfolio/00_master_read.md).
For stage-by-stage responsibility, see
[`00_portfolio/19_de_platform_detail.md`](00_portfolio/19_de_platform_detail.md)
and [`00_portfolio/14_diagram_catalog.md`](00_portfolio/14_diagram_catalog.md).

## Verification and public-safety boundary

Use read-only evidence first: Fabric/Power BI REST, ephemeral Entra-token
`pyodbc`, repository contracts, then reviewed tools. Default refresh commands to
dry-run; live execution requires explicit approval for the exact scope.

The remote is public. Do not publish credentials, tokens, tenant-specific
identifiers, raw enterprise extracts/SQL, local paths, protected Control Tower
evidence, or unverified production claims. Public presentations are sanitized:

- [Lineage portal](https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/)
- [Control Tower presentation](https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/control-tower/)

For current status, prefer the dated evidence and claim labels in
[`03_operations/CLAIMS.md`](03_operations/CLAIMS.md) over counts embedded in
this overview.
