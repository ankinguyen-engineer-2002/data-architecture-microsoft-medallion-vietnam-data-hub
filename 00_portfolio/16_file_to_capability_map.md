# File-to-capability map

This map prevents the portfolio from becoming a folder tour. Each area is tied
to a capability and a proof path.

| Area | Capability represented | Primary implementation | Primary proof |
|---|---|---|---|
| Root README/AGENTS/CONTEXT | operating discipline and source-of-truth rules | repository instructions | current context and change history |
| `01_docs/architecture/ashley` | Azure → Databricks → Fabric enterprise context | architecture narrative and diagrams | evidence tags and architecture references |
| `01_docs/architecture/four_cadence_operating_model.md` | batch/micro-batch vs AWS MSK/Flink vs plant edge | cadence split mapped to mart objects | ADR-012 |
| `01_docs/architecture/current` | current Fabric runtime contract | `_Wrk`, loader, wrapper and lifecycle diagrams | Phase 1 closeout and current context |
| `01_docs/decisions` | architecture trade-offs and accepted constraints | ADRs including ADR-012 cadence/stream placement | decision status and linked artifacts |
| `01_docs/onboarding` | DA/DE handoff and operating workflow | onboarding guides/checklists | repeatable runbook steps |
| `01_docs/runbook` | approved operational procedures | connectivity, DQ, SQLPROJ and sync guides | command/result evidence |
| `02_marts/forecast_accuracy` | forecast/actual product | source, Silver, Gold, DQ, catalog | mart README, manifests, semantic contract |
| `02_marts/inventory_health` | inventory risk product | snapshots, supply signals, Gold, DQ, catalog | mart README, manifests, source investigations |
| `03_operations/azure` | Control plane: Entra, subscription, SQL/Agent, Fabric tenant, Databricks workspace | `control_plane.yaml`, `identity.md`, `sql.md` | tenant/sub verified; GA is PIM / owner-confirmed |
| `03_operations/databricks` | Spark jobs for the two-mart slice | jobs JSON, notebooks, `sources.yaml` | ADR-013; Bronze files in `02_marts` |
| `03_operations/orchestration` | dependency-safe runtime | YAML/JSON manifests and wrappers | dry-run/live audit evidence |
| `03_operations/deployment/sqlproj` | build and handoff discipline | SQLPROJ projects and package manifests | build logs and diff review |
| `03_operations/operating_registry` | machine-readable operations index | assets, DQ, lineage and run order | generated package checks |
| `04_semantic` | DA/report metric authority | TMDL, DAX, model and relationship contracts | semantic smoke/parity tests |
| `05_tools` | repeatable DataOps and drift detection | Python scanners/builders/auditors | fixture tests and sanitized snapshots |
| `06_enterprise_control_tower` | decision/AI architecture and feature packaging | blueprint, feature contracts, evidence | feature status and live-gate records |
| `06_enterprise_control_tower/AIOS-Workspace` | AI-native workbench MVP | FastAPI/React, federation, artifacts, evals | nested review packs and local tests |
| `99_archive` | provenance and historical context | retained snapshots and prior designs | archive README/status registers |

## Coverage rule

Every showcase claim should point to one implementation surface and one proof
surface. If a claim has only a blueprint or prototype, label it accordingly.
