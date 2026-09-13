# Architecture Docs

Portfolio entry: [`../../00_portfolio/03_platform_map.md`](../../00_portfolio/03_platform_map.md).
Read the portfolio lifecycle first when the goal is to understand the work as a
career/product story; use this folder for architecture source and evidence.

This folder contains high-level architecture views and navigation pointers.

## Read the boundary first

- [Three-platform operating model](three_platform_operating_model.md) — Azure →
  Databricks → Fabric boundary.
- [Azure ops](../../03_operations/azure/README.md) / [Databricks ops](../../03_operations/databricks/README.md)
  — reconstructed slice from the two marts (ADR-013). DE-weight path.
- [Four-cadence operating model](four_cadence_operating_model.md) — adjacent OT
  stream pattern only; not daily mart runtime.

## Current Final Architecture

- Entry point: [current/final_enterprise_etl_runtime_architecture.md](current/final_enterprise_etl_runtime_architecture.md)
- Mermaid source: [current/final_enterprise_etl_runtime_architecture.mmd](current/final_enterprise_etl_runtime_architecture.mmd)
- Generated SVG: [current/final_enterprise_etl_runtime_architecture.svg](current/final_enterprise_etl_runtime_architecture.svg)

Use this as the current architecture source of truth after Phase 1 Enterprise ETL migration.

## Current Contract Decisions

- [ADR-009: Enterprise `_Wrk` View Contract For Curated Warehouses](../decisions/ADR-009-enterprise-wrk-view-contract.md) — Silver/Gold final schemas contain physical tables; `_Wrk` schemas contain `v_<TableName>` work/source views used by `ETL_Framework`.

## Ashley enterprise end-to-end (infra + orchestration operating model)

- Entry point (deep dive + diagrams): `01_docs/architecture/ashley/overall_architecture_ashley.md`
- Quick overview diagram (PNG): `01_docs/architecture/ashley/overall_architecture_ashley_overview.png`
- Scheduling patterns (anti-pattern vs preferred): `01_docs/architecture/ashley/overall_architecture_ashley_scheduling_patterns.svg`
- Legend / glossary: `01_docs/architecture/ashley/overall_architecture_ashley_legend.md`

## Three-platform operating model

- [Azure → Databricks → Fabric runtime boundary](three_platform_operating_model.md)
  — canonical flow, ownership, contracts and open verification items.

## Four cadences (adjacent OT pattern only)

- [Batch vs AWS MSK/Flink vs edge](four_cadence_operating_model.md) — not the
  nightly mart path. Daily DE work is [azure](../../03_operations/azure/) + [databricks](../../03_operations/databricks/).

## Fabric hub-and-value-stream (2-workspace view, repo-local)

- Hub + value stream diagram (VN view of hub patterns): `99_archive/reverse-engineering/enterprise_data_architect/diagrams/cross_workspace_architecture.png`
- Repo navigation and context: `README.md`
