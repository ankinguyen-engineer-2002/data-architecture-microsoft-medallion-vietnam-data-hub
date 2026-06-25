# Architecture Docs

This folder contains high-level architecture views and navigation pointers.

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

## Fabric hub-and-value-stream (2-workspace view, repo-local)

- Hub + value stream diagram (VN view of hub patterns): `99_archive/reverse-engineering/enterprise_data_architect/diagrams/cross_workspace_architecture.png`
- Repo navigation and context: `README.md`
