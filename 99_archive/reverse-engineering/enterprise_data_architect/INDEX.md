# INDEX — `EnterpriseData-Dev` Workspace Analysis

> Bob Horton's Enterprise Data hub at Ashley Furniture · Workspace ID `5360a935-1984-4775-895f-f4c90bafa19d`
>
> This folder contains the VN team's analysis of Bob's enterprise architecture, synthesized from a comprehensive scan of the workspace via [`enterprisedata-dev-docs`](https://github.com/ankinguyen-engineer-2002/enterprisedata-dev-docs) (cloned to `_external_refs/`, gitignored).
>
> Mirror structure of `Enterprise_SupplyChain_Dev_architect/` for easy side-by-side comparison.

## 00_overview/ — Workspace identity + at-a-glance
- [Workspace overview](00_overview/01_workspace_overview.md) — display name, IDs, capacity, tenant, item counts
- [Architecture at a glance](00_overview/02_architecture_at_a_glance.md) — 11 WH + 5 LH layers, data flow, who owns what

## 10_evidence/ — Inventory + scan synthesis
- [Storage inventory](10_evidence/01_storage_inventory.md) — 11 warehouses + 5 lakehouses, schemas, table counts
- [ETL framework summary](10_evidence/02_etl_framework_summary.md) — control plane brain (links to deep-dive in `projects/etl_framework/`)
- [Orchestration summary](10_evidence/03_orchestration_summary.md) — 22 pipelines (mostly dormant), active runs, ADF mount, Mirror Databricks
- [Risks register](10_evidence/04_risks.md) — 28 issues from scan, top 5 critical/high

## 20_proposals/ — Integration planning
- [ETL framework alignment](20_proposals/01_etl_framework_alignment.md) — Bob's pattern vs VN approach, what to align
- [SupplyChain_Warehouse proposal](20_proposals/02_supply_chain_warehouse_proposal.md) — request to create new domain WH for SC team
- [Naming conventions audit](20_proposals/03_naming_conventions.md) — schema/table/view/proc patterns observed

## 30_runbook/ — Operational notes (read-mostly)
- [Cross-workspace consumption](30_runbook/01_cross_workspace_consumption.md) — how SC workspace shortcuts to hub Silver
- [How Bob's domain teams add Silver tables](30_runbook/02_domain_team_workflow.md) — Wholesale/Retail self-serve pattern

## projects/ — Deep dives per domain
- [ETL framework deep dive](projects/etl_framework/SYNTHESIS.md) — 35 procs, 65-col TableDictionary lifecycle, audit pattern
- [Storage inventory per WH](projects/storage_inventory/) — Wholesale, Retail, MasterData, Distribution, Quality, Centralized
- [Orchestration patterns](projects/orchestration/) — pipeline DAG, ForEach metadata, ADF integration

## diagrams/ — Cross-workspace architecture
- [`cross_workspace_flow.md`](diagrams/cross_workspace_flow.md) — 4 Mermaid diagrams (end-to-end architecture, daily orchestration sequence, decision tree, ownership matrix)
- [`cross_workspace_architecture.png`](diagrams/cross_workspace_architecture.png) — rendered hub + value-stream PNG used as hero image in repo root README

## artifacts/ — Raw scan derivatives
- (Empty — raw scan source lives at `_external_refs/enterprisedata-dev-01_docs/`, gitignored. Synthesized outputs land in `projects/etl_framework/SYNTHESIS.md`.)

## 05_tools/ — Analysis scripts
- (Empty — scan scripts live in `_external_refs/enterprisedata-dev-01_docs/scripts/`. VN-specific analysis lives in sister folder `../Enterprise_SupplyChain_Dev_architect/05_tools/`.)

---

## Cross-refs

- Sister folder: [`Enterprise_SupplyChain_Dev_architect/`](../Enterprise_SupplyChain_Dev_architect/) — VN team's value-stream workspace
- Raw scan source (gitignored): `_external_refs/enterprisedata-dev-01_docs/`
- Top-level cross-workspace README: [`../README.md`](../README.md)
- ADRs: [`../docs/decisions/`](../docs/decisions/)
