# v9 Source Inventory And Chronology

Status legend:

- `Pending`: not yet deeply read in the new audit pass.
- `Read`: fully read and summarized into the evidence ledger.
- `Sampled`: inspected for scope but not fully extracted.
- `Superseded`: older duplicate or generated artifact; keep for reference only.
- `Need-history`: must compare with git history because current copy may hide prior context.

## 1. v9 File Inventory

### 1.1 Root Context

| Status | File | Audit purpose |
|---|---|---|
| Read | `99_archive/architectures/v9_april/README.md` | Generic v9 architecture, object counts, current build state |
| Sampled | `99_archive/architectures/v9_april/FULL_CONTEXT.md` | Full project context and historical design notes |
| Read | `99_archive/architectures/v9_april/task.md` | Original task scope and assumptions |

### 1.2 Forecast Project Docs

| Status | File | Audit purpose |
|---|---|---|
| Pending | `99_archive/architectures/v9_april/01_sc_forecast/README.md` | Detailed project-specific v9 description |
| Sampled | `99_archive/architectures/v9_april/01_sc_forecast/docs/01_architecture.md` | Logical/physical v9 architecture |
| Sampled | `99_archive/architectures/v9_april/01_sc_forecast/docs/02_setup.md` | DDL, meta tables, SPs, load logic |
| Sampled | `99_archive/architectures/v9_april/01_sc_forecast/docs/03_pipeline.md` | Pipeline orchestration and execution flow |
| Pending | `99_archive/architectures/v9_april/01_sc_forecast/docs/04_v8_vs_v9_comparison.md` | Historical v8/v9 comparison and Direct Lake/semantic context |
| Sampled | `99_archive/architectures/v9_april/01_sc_forecast/docs/03_operations/edw_source_swap.md` | EDW supplement/source swap, rollback, lineage bridge |

### 1.3 Operations Docs

| Status | File | Audit purpose |
|---|---|---|
| Sampled | `99_archive/architectures/v9_april/docs/01_03_operations/01_runbook.md` | Operations, troubleshooting, run-state assumptions |
| Sampled | `99_archive/architectures/v9_april/docs/01_03_operations/02_onboarding.md` | New object onboarding and registry-driven behavior |
| Sampled | `99_archive/architectures/v9_april/docs/01_03_operations/03_scheduling.md` | Scheduling, cron, smart skip, concurrency |
| Sampled | `99_archive/architectures/v9_april/docs/01_03_operations/04_alerting.md` | Alerting and operational monitoring |
| Read | `99_archive/architectures/v9_april/docs/01_03_operations/05_generic_sp_migration.md` | Enterprise TableDictionary/generic SP alignment |
| Read | `99_archive/architectures/v9_april/docs/01_03_operations/06_timezone_sync.md` | CST/VN/UTC and `vw_table_dictionary` behavior |
| Read | `99_archive/architectures/v9_april/docs/01_03_operations/07_sqlproj_validation.md` | CI/CD and SQL project validation assumptions |

### 1.4 Template Docs

| Status | File | Audit purpose |
|---|---|---|
| Pending | `99_archive/architectures/v9_april/docs/02_templates/01_architecture.md` | Reusable architecture template |
| Pending | `99_archive/architectures/v9_april/docs/02_templates/02_setup_guide.md` | Reusable setup template |
| Pending | `99_archive/architectures/v9_april/docs/02_templates/03_pipeline_guide.md` | Reusable pipeline template |

### 1.5 Enterprise Alignment Docs

| Status | File | Audit purpose |
|---|---|---|
| Read | `99_archive/architectures/v9_april/01_sc_forecast/enterprise/01_roadmap.md` | Enterprise integration roadmap |
| Sampled | `99_archive/architectures/v9_april/01_sc_forecast/enterprise/02_multi_mart_scale.md` | Multi-mart scaling design |
| Read | `99_archive/architectures/v9_april/01_sc_forecast/enterprise/03_fabric_vs_enterprise.md` | Fabric-vs-enterprise tradeoffs |

### 1.6 Scripts And Validation

| Status | File | Audit purpose |
|---|---|---|
| Pending | `99_archive/architectures/v9_april/scripts/deep_verify.py` | Automated deep validation checks |
| Pending | `99_archive/architectures/v9_april/scripts/health_check.py` | Health check assumptions and expected object names |
| Pending | `99_archive/architectures/v9_april/requirements.txt` | Python/tooling dependencies |
| Pending | `99_archive/architectures/v9_april/runtime.txt` | Runtime assumptions |

### 1.7 Lineage Explorer And Exports

| Status | File | Audit purpose |
|---|---|---|
| Pending | `99_archive/architectures/v9_april/lineage_explorer/app.py` | Rendered lineage logic and source augmentation |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/data/lineage.csv` | Exported `meta.sp_lineage` snapshot |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/data/registry.csv` | Exported `meta.sp_registry` snapshot |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/data/run_history.csv` | Exported run history |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/data/views.csv` | Exported view definitions |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/templates/lineage.html` | Render template |
| Pending | `99_archive/architectures/v9_april/lineage_explorer/requirements.txt` | Explorer dependencies |

### 1.8 Diagrams

| Status | File | Audit purpose |
|---|---|---|
| Pending | `99_archive/architectures/v9_april/diagrams/template_full_architecture.mmd` | Generic architecture diagram |
| Pending | `99_archive/architectures/v9_april/diagrams/v9_supplychain_full_architecture.mmd` | Full SupplyChain v9 diagram |
| Pending | `99_archive/architectures/v9_april/diagrams/v9_presentation.mmd` | Presentation-level architecture |
| Superseded | `99_archive/architectures/v9_april/diagrams/svg/*.svg` | Rendered outputs; inspect only if Mermaid source is unclear |

## 2. v10 File Inventory

| Status | File | Audit purpose |
|---|---|---|
| Pending | `Enterprise_SupplyChain_Dev_architect/00_overview/01_super_plan_medallion_refactor.md` | Current v10 target plan |
| Pending | `Enterprise_SupplyChain_Dev_architect/00_overview/02_architecture_blueprint_mermaid.md` | v10 architecture narrative and diagrams |
| Pending | `Enterprise_SupplyChain_Dev_architect/00_overview/03_v9_feature_parity_checklist.md` | Claimed v9-to-v10 parity |
| Pending | `Enterprise_SupplyChain_Dev_architect/20_proposals/04_revised_enterprise_etl_standards_proposal.md` | Revised Enterprise ETL standards interpretation |
| Pending | `Enterprise_SupplyChain_Dev_architect/10_evidence/05_deep_audit_protocol.md` | Audit process |
| Pending | `Enterprise_SupplyChain_Dev_architect/diagrams/*.mmd` | Current architecture visuals |
| Superseded | `Enterprise_SupplyChain_Dev_architect/diagrams/render_check/*.svg` | Rendered outputs; use for visual check only |
| Pending | `Enterprise_SupplyChain_Dev_architect/SQL Server Data Warehouse Standards.docx` | Enterprise ETL/DE team standards; local-only evidence unless sharing is approved |

## 3. Git Chronology To Inspect

Initial `git log --oneline --decorate --all --max-count=60` shows the following high-signal history groups:

| Status | Commit pattern | Why inspect |
|---|---|---|
| Need-history | `Restore detailed README` | Recover project-specific context that may not be obvious after reorg |
| Need-history | `Restructure project + EDW source swap docs + cleanup` | Understand when `_edw` supplement and doc changes were introduced |
| Need-history | `Move generic operations docs to root 01_docs/operations` | Separate generic framework docs from project-specific docs |
| Need-history | `Fix README structure: root=generic reference, sc_forecast=project-specific` | Detect source-of-truth changes between root and project docs |
| Need-history | `Clean repo structure: numbered folders, remove dev artifacts` | Understand current folder split and missing old paths |
| Need-history | `Auto-refresh lineage data [skip ci]` | Compare lineage/registry snapshots over time |
| Need-history | `Remove AI config from tracking` | Not architecture-relevant except to avoid reading config noise |

## 4. Current Git Worktree Note

The repository is currently reorganized:

```text
99_archive/architectures/v9_april/     old v9 project content
Enterprise_SupplyChain_Dev_architect/     new v10 planning artifacts
```

`git status --short` shows many deleted old root paths and untracked numbered folders because the reorganization has not been committed. This is not an audit finding by itself, but git history comparisons must account for the folder move.

## 5. Read Order

Recommended order for the deep read:

1. Root v9 context: `README.md`, `FULL_CONTEXT.md`, `task.md`.
2. Project-specific v9 docs: architecture, setup, pipeline, v8/v9 comparison, EDW source swap.
3. Operations docs: runbook, onboarding, scheduling, alerting, generic SP, timezone, sqlproj validation.
4. Enterprise docs: roadmap, multi-mart scale, Fabric-vs-enterprise.
5. Scripts and lineage explorer exports.
6. v9 diagrams.
7. v10 proposal and diagrams.
8. Enterprise ETL DOCX.
9. Git history deltas for architecture-impact commits.

## 6. Output Linkage

Findings from this inventory must flow into:

- `07_v9_capability_evidence_ledger.md`
- `08_v10_gap_matrix.md`
- `09_enterprise_etl_standards_mapping_matrix.md`
- `10_final_v10_amendment_plan.md`
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `16_v10_readiness_scorecard_and_v9_cleanup.md`
