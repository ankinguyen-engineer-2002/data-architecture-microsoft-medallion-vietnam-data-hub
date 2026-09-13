# Current repository audit — 2026-09-13

## Audit scope

Scanned the current root worktree, active READMEs, architecture/ADR/runbook
surfaces, both mart packages, operations/SQLPROJ/orchestration, semantic and
Copilot contracts, portfolio diagrams, and nested Git boundaries. Generated or
dependency directories (`node_modules`, caches, archives) were classified, not
treated as current runtime source.

## Current shape

| Surface | Current conclusion | Evidence boundary |
|---|---|---|
| Upstream platform | Azure landing/access/operations and Databricks Spark/Delta batch + incremental context | `01_docs/architecture/ashley/`, ADR-012; exact external job/service inventory partly `[Need-verify]` |
| Lakehouse runtime | Fabric source/Bronze → Processing/Silver → Gold serving | `01_docs/architecture/current/`, `02_marts/` |
| DataOps | Enterprise ETL metadata, wrappers, SQL Agent hand-off, DQ gates, lineage, audit and deployment packages | `03_operations/`, `05_tools/`, ADR-010/011 |
| Data products | Forecast Accuracy and Inventory Health with explicit grain/history/snapshot contracts | `02_marts/*/README.md`, SQL and DQ contracts |
| Analytics | Semantic model, measures, relationships, RLS/access and report hand-off | `04_semantic/` |
| Applied AI | Governed Copilot/Data Agent/Agent Flows and deterministic presentation paths | `04_semantic/forecast_accuracy_agent/` |
| Adjacent operational stream | AWS MSK/Flink and plant/CDC edge pattern; not runtime in this repo | ADR-012, four-cadence model; IDs `[Need-verify]` |
| AIOS | Separate nested MVP repository; broader workbench, offline/high-level evidence | `06_enterprise_control_tower/AIOS-Workspace/` and nested `AGENTS.md` |

## What changed in the latest audit

- Corrected the portfolio master diagram to show two planes: the Fabric-heavy
  lakehouse implementation in this repo and the adjacent OT/AWS control plane.
- Made Databricks cadence explicit: batch and bounded incremental/CDC jobs that
  terminate; no unsupported claim of 24/7 plant streaming.
- Connected DataOps controls to actual stages instead of drawing them as a
  generic standalone box.
- Kept exact runtime object names in technical docs; showcase diagrams use
  conceptual names only.
- Preserved the distinction between repository source, owner-confirmed context,
  live-verified runtime, historical archive, and nested products.

## Reading path after audit

1. [`03_operations/CLAIMS.md`](../03_operations/CLAIMS.md)
2. [`03_operations/azure/`](../03_operations/azure/) → [`databricks/`](../03_operations/databricks/)
3. [`orchestration/main`](../03_operations/orchestration/main/README.md) (11 steps)
4. Mart READMEs
5. Copilot / AIOS only if the interviewer asks

## Remaining uncertainty

- Entra PIM screenshot is an empty slot: `03_operations/azure/ENTRA_EXPORT.md`.
  Until filled, Global Administrator / Fabric Administrator stay
  **owner-confirmed PIM**, not a dated export.
- Databricks workspace URL / live job name is an empty slot:
  `03_operations/databricks/WORKSPACE.md`. Job JSON in git stays
  **[Reconstructed]** (ADR-013). UC `edw_dev`, ADLS `ashleydevlake`, Bronze
  names, load methods are verified.
- AWS MSK/Flink/edge instance inventory is not in this repo and remains
  owner-confirmed/`[Need-verify]`.

These are intentionally recorded as open evidence items, not filled with
invented platform claims. Speak from [`03_operations/CLAIMS.md`](../03_operations/CLAIMS.md).
