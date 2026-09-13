# Fabric SupplyChain Operating Repository

Data Engineer (SCM) operating record for **two marts**: Forecast Accuracy and
Inventory Health. Azure registers identity and resources; Azure Databricks
cooks the source slice; Fabric serves Gold. Claims: [`03_operations/CLAIMS.md`](03_operations/CLAIMS.md).

## Career and product lifecycle

```text
Azure / Databricks enterprise data flow
  -> Microsoft Fabric Supply Chain platform
  -> DataOps: ETL, orchestration, DQ, lineage, audit
  -> Forecast Accuracy + Inventory Health data products
  -> DA semantic models and reports
  -> Copilot / Data Agent / Agent Flows / bounded automation
  -> AIOS Workbench MVP (nested product repository)
```

Identity: **Data Engineer (SCM)**. Copilot is bounded on Gold. AIOS is a
nested MVP — not the front door.

DE walkthrough: [`00_portfolio/07_interviewer_walkthrough.md`](00_portfolio/07_interviewer_walkthrough.md).
Narrative index: [`00_portfolio/README.md`](00_portfolio/README.md).

For the full content map, read [`00_portfolio/11_business_and_user_map.md`](00_portfolio/11_business_and_user_map.md),
[`00_portfolio/12_operations_and_dataops.md`](00_portfolio/12_operations_and_dataops.md),
and [`00_portfolio/10_technology_decisions.md`](00_portfolio/10_technology_decisions.md).

## Product and capability index

| Product/capability | Business value | Detailed source |
|---|---|---|
| Supply Chain data platform | trusted SCM data foundation for DA and operations | [`00_portfolio/03_platform_map.md`](00_portfolio/03_platform_map.md) |
| Forecast Accuracy | forecast-versus-actual planning insight | [`02_marts/forecast_accuracy/README.md`](02_marts/forecast_accuracy/README.md) |
| Inventory Health | current and forward inventory-risk insight | [`02_marts/inventory_health/README.md`](02_marts/inventory_health/README.md) |
| DataOps runtime | repeatable, auditable and dependency-safe operation | [`00_portfolio/12_operations_and_dataops.md`](00_portfolio/12_operations_and_dataops.md) |
| Semantic/report enablement | reusable measures and analyst-facing meaning | [`04_semantic/README.md`](04_semantic/README.md) |
| Governed Copilot | conversational access without bypassing metric authority | [`00_portfolio/05_ai_enablement.md`](00_portfolio/05_ai_enablement.md) — after marts |
| AIOS Workbench | nested MVP; not the DE identity | `06_enterprise_control_tower/AIOS-Workspace/` |

Use [`00_portfolio/16_file_to_capability_map.md`](00_portfolio/16_file_to_capability_map.md)
when you need to find the implementation and proof surface for a claim.

This repository is the Fabric Supply Chain **operating** record: mart SQL,
wrappers, DQ, semantic contracts. Azure Databricks compute for those marts is
documented as reconstructed ops under `03_operations/azure/` and
`03_operations/databricks/` (ADR-013) — same Bronze names and load methods,
not a workspace export.
It is not proof of current data freshness without a fresh live check.

## Repository boundary

```text
Azure landing + Databricks Spark (reconstructed; 03_operations/azure, databricks)
  ADLS + UC edw_dev + seven Spark jobs, then EXIT
       ↓
This git: Fabric SCM
  Bronze shortcuts → Silver _Wrk → Gold → Agent (11 steps) → DQ
       ↓
DA / planner reports  |  Copilot only on governed Gold
```

## Start Here

Interview / DE path:

1. [`03_operations/CLAIMS.md`](03_operations/CLAIMS.md)
2. [`03_operations/azure/README.md`](03_operations/azure/README.md) then [`databricks/`](03_operations/databricks/)
3. [`03_operations/orchestration/main/README.md`](03_operations/orchestration/main/README.md) — 11 Agent steps
4. [`02_marts/forecast_accuracy/README.md`](02_marts/forecast_accuracy/README.md) / [`inventory_health`](02_marts/inventory_health/README.md)

Agent / live-ops path:

1. [`AGENTS.md`](AGENTS.md), then [`CONTEXT.md`](CONTEXT.md).
2. [Enterprise Framework migration plan](01_docs/Enterprise_Framework_Migration_Master_Plan.md).
3. [`FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md`](FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md).

## Runtime Shape

```text
Enterprise_Lakehouse
  -> SupplyChain_Processing_Warehouse
  -> SupplyChain_Gold_Warehouse
  -> semantic/report contracts

ETL_Framework owns TableDictionary, AuditLog, and approved loaders.
Business transformation lives in <Schema>_Wrk.v_<Table> work views.
```

The operating model preserves Bronze/Silver/Gold business surfaces while using
the Enterprise ETL Framework for loading, audit, metadata, DQ, and run order.
Do not infer successful data delivery from a completed `AuditLog` row alone:
validate the final object, row/count window, DQ gate, and relevant semantic
smoke separately.

## Repository Map

| Area | Purpose |
| --- | --- |
| `01_docs/` | Architecture, onboarding, decisions, plans, runbooks, and evidence |
| `02_marts/` | Business logic and contracts for `forecast_accuracy` and `inventory_health` |
| `03_operations/` | Azure landing + Databricks slice (reconstructed) + Fabric Agent 11 steps, SQLPROJ, registries |
| `04_semantic/` | Semantic/report contracts |
| `05_tools/` | Repeatable maintenance, DQ, parity, sync, and lineage tooling |
| `99_archive/` | Historical reference only, not current runtime truth |
| `06_enterprise_control_tower/` | Confidential local evidence and Control Tower source; Git-ignored |

The nested [AIOS Workbench portfolio surface](06_enterprise_control_tower/AIOS-Workspace/docs/portfolio/README.md)
documents the later AI-native MVP without making it the primary Supply Chain
platform identity.

## Daily Operating Rules

- Humans / interview: start at `03_operations/CLAIMS.md`, then azure / databricks / Agent 11.
- Agents: start with the root `AGENTS.md` and current `CONTEXT.md`.
- Read the relevant orchestration manifest before proposing a refresh.
- Default to dry-run. A live action requires current, explicit approval.
- Compare live Fabric behavior with source control before synchronizing code.
- Preserve SQLCMD/project-reference structure when adapting live logic to EDW.
- Stage only exact, reviewed task paths. This worktree may contain unrelated
  user changes.

## Public Lineage And Control Tower

- [Lineage portal](https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/)
  is a sanitized static representation. It contains no credentials or raw SQL.
- [Control Tower presentation](https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/control-tower/)
  is a separately sanitized public presentation. Its confidential local Library
  and blueprint source are intentionally excluded from GitHub Pages.

## Safety Boundary

The remote is public. Never publish internal evidence, raw enterprise SQL,
credentials, local paths, or protected Control Tower files. `Enterprise_Lakehouse`
is read-only for agents unless Aric names the exact object and before/after
change in the current conversation. Do not delete/move unknown artifacts or run
destructive SQL/Git commands without exact same-conversation approval.

For current facts, use `CONTEXT.md`, fresh Fabric REST/`pyodbc` evidence, and
the relevant runbook instead of stale counts embedded in this README.
