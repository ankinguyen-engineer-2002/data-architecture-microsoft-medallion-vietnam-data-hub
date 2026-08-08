# Fabric SupplyChain Operating Repository

This repository is the reviewed operating and architecture record for the
Enterprise Supply Chain Fabric estate. It contains SQL contracts, orchestration,
DQ controls, semantic contracts, runbooks, and a sanitized public lineage site.
It is not the live Fabric runtime and it must not be used as proof of current
data freshness without a fresh live check.

## Start Here

1. Read [`AGENTS.md`](AGENTS.md), then the complete current [`CONTEXT.md`](CONTEXT.md).
2. Read the [Enterprise Framework migration plan](01_docs/Enterprise_Framework_Migration_Master_Plan.md).
3. For live DEV to repository synchronization, follow
   [`FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md`](FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md).
4. For a Fabric DEV change through review/CI, follow
   [`supplychain_fabric_dev_to_pr_workflow.md`](01_docs/runbook/guides/supplychain_fabric_dev_to_pr_workflow.md).

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
| `03_operations/` | Orchestration manifests, SQLPROJ packages, deployment tools, and registries |
| `04_semantic/` | Semantic/report contracts |
| `05_tools/` | Repeatable maintenance, DQ, parity, sync, and lineage tooling |
| `99_archive/` | Historical reference only, not current runtime truth |
| `06_enterprise_control_tower/` | Confidential local evidence and Control Tower source; Git-ignored |

## Daily Operating Rules

- Start with the root `AGENTS.md` and current `CONTEXT.md`.
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
