# Projects — Live Workspace Detail

This folder contains **per-project live state catalogs** of what's actually built and running in the Microsoft Fabric workspace `SupplyChain Dev` (`c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`).

Each project folder is a complete inventory: real table names, row counts, IDs, ETL DDL, pipeline definitions, semantic model details, lineage. Generated from live workspace scans.

> **Boundary:** Everything outside this `projects/` folder in `Enterprise_SupplyChain_Dev_architect/` is generic template content — do not put project-specific detail there.

## Project Index

| Folder | Mart | Gold Schema | Status | Last scan |
|--------|------|-------------|--------|-----------|
| [forecast/](forecast/README.md) | Forecast Accuracy | `ForecastAccuracy_DW` + shared `Shared_DW` dims | **LIVE**; semantic smoke green; shared dim cutover documented | 2026-06-01 |
| [inventory_health/](inventory_health/README.md) | Inventory Health | `InventoryHealth_DW` + shared `Shared_DW` dims | **LIVE**; DA-first refactor and semantic smoke green; residual cleanup candidates documented | 2026-06-01 |

## Latest Live Audit

- [live_audit_2026-06-01.md](live_audit_2026-06-01.md) is the current cross-mart source-of-truth for live Fabric item IDs, row counts, semantic smoke tests, shared dimension contracts, pipeline status, registry state, lineage state, and residual cleanup candidates.
- This audit supersedes older row-count/status paragraphs that still mention 2026-05-12, 2026-05-22, or 2026-05-28 as the latest verification date.

## Adding a new project

1. Create folder `Enterprise_SupplyChain_Dev_architect/projects/<name>/`
2. Copy structure from `forecast/` (8 docs + `etl/` subfolder)
3. Run live scan via Fabric MCP + pyodbc against Processing/Gold WH
4. Fill each doc with concrete data
5. Add row to "Project Index" table above

## Per-project structure

```
<project_name>/
├── README.md            project card: status + infra snapshot + quick links
├── 00_workspace.md      workspace, WH IDs, SQL endpoint, auth tokens
├── 10_bronze.md         Bronze layer — Lakehouses + EDW supplement feeds
├── 20_silver.md         Silver layer — domain schemas, tables, ETL logic
├── 30_gold.md           Gold layer — Fact/Dim, cross-DB serving
├── 40_pipelines.md      pipelines — IDs, DAG, schedule, runtime
├── 50_semantic.md       semantic model — tables, measures, RLS
├── 60_lineage.md        lineage edges + Gold → SemanticModel
└── etl/
    ├── staging_ddl.sql
    ├── silver_views.sql
    ├── gold_views.sql
    └── meta_sps.sql
```
