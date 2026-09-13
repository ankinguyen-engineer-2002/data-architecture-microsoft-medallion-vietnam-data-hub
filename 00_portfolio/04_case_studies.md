# Selected case studies

## Case 1 — Supply Chain data platform

**Problem:** SCM analysts and operations need trusted data products rather than
isolated extracts and report-specific transformations.

**Built/operated:** the Fabric operating implementation and the contracts that
connect it to the upstream Azure/Databricks estate: Bronze/Silver/Gold layers,
shared dimensions, semantic contracts, and operational boundaries.

**Proof:** current architecture, mart packages, SQLPROJ contracts, orchestration
manifests, and live-verified context under `01_docs/`, `02_marts/`, and
`03_operations/`.

The repository contains the Fabric-heavy implementation surface. Azure and
Databricks ownership is evidenced through upstream architecture/context and
handoff contracts; their external platform code is not duplicated here.
Databricks on this path is Spark batch and micro-batch on super-large tables
(jobs terminate). Sub-second operational loops (yard, sorter, ATP+cube, mill)
are an adjacent AWS MSK/Flink and plant-edge plane — see ADR-012.

## Case 2 — Enterprise ETL/DataOps runtime

**Problem:** business logic needed an auditable, dependency-safe, enterprise-aligned
execution path.

**Built:** `_Wrk` source views, final tables, `TableDictionary`, `AuditLog`, wrapper
procedures, manifest order, DQ gates, parity checks, and build-only deployment packs.

**Proof:** Phase 1 closeout evidence in
`01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md` and
`01_docs/Enterprise_Framework_Migration_Master_Plan.md`.

## Case 3 — Forecast Accuracy and Inventory Health

**Problem:** planning and operations require stable, reusable facts at the correct
time/entity grain.

**Built:** two domain data products with history, snapshots, forecast/actual logic,
inventory risk helpers, dimensions, run order, DQ and semantic consumption.

**Proof:** `02_marts/forecast_accuracy/README.md` and
`02_marts/inventory_health/README.md`.

## Case 4 — Governed Copilot enablement

**Problem:** conversational access must not invent KPI logic or bypass data access.

**Built:** semantic instructions, approved metric contracts, Data Agent boundaries,
deterministic query/presentation paths, and a bounded Adaptive Card chart MVP.

**Proof:** `04_semantic/forecast_accuracy_agent/` and the feature catalog under
`06_enterprise_control_tower/00_catalog/`.

## Case 5 — AIOS Workbench MVP

**Problem:** explore a broader AI-native workspace while preserving data authority,
provenance, safe rendering, and explicit execution boundaries.

**Built:** a React/FastAPI workbench with specialist routing, semantic compilation,
evidence envelopes, artifacts, research, isolated execution, plugins, and durable
workflow contracts.

**Status:** local/offline implementation and high-level testing; live provider,
production identity, scale-out, and external connector gates remain separate.

**Proof:** nested repo `06_enterprise_control_tower/AIOS-Workspace/` and its
`docs/review/` reports. It is not the primary production SCM platform.
