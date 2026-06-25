# Deep Audit Protocol: v9 To v10 And Enterprise ETL Standards

Purpose: re-read the v9 architecture from source evidence, compare it against the current v10 proposal and Enterprise ETL's SQL Data Warehouse Standards, then produce a defensible gap matrix before making more architecture claims.

This protocol exists because the previous v10 review was directionally useful but not deep enough to claim complete v9 feature coverage.

## 1. Ground Rules

- Do not claim a v9 capability exists unless it is backed by a file, export, script, diagram, git history entry, or live Fabric verification.
- Do not claim a v10 capability covers v9 unless there is a matching v10 requirement, diagram, or proposed object/control-plane component.
- Tag every important finding as:
  - `[Verified]`: directly supported by local 01_docs/exports/source code or official Microsoft/Enterprise ETL docs.
  - `[Likely]`: supported by evidence but still needs implementation/live validation.
  - `[Need-verify]`: plausible but requires live Fabric/GitHub/Fabric REST/SQL check.
  - `[Speculation]`: architecture hypothesis only; must not become a decision.
- Separate three things:
  - What v9 currently has.
  - What v10 currently proposes.
  - What Enterprise ETL standards require or imply.
- Treat Enterprise ETL's DOCX as an enterprise governance standard, but adapt platform-specific SQL Server / ADW rules when they conflict with Fabric Direct Lake, OneLake, Warehouse, or v9's existing control plane.

## 2. Source Inventory

### 2.1 v9 Local Evidence

Read all files under `99_archive/architectures/v9_april`, grouped by purpose:

| Group | Files | Why it matters |
|---|---|---|
| Root context | `README.md`, `FULL_CONTEXT.md`, `task.md` | Project scope, object counts, current state, known constraints |
| Forecast project docs | `01_sc_forecast/README.md`, `01_docs/01_architecture.md`, `01_docs/02_setup.md`, `01_docs/03_pipeline.md`, `01_docs/04_v8_vs_v9_comparison.md` | Actual v9 architecture, DDL, pipeline, semantic model, v8/v9 lineage |
| Operations docs | `01_docs/01_03_operations/*.md` | Runbook, onboarding, scheduling, alerting, generic SP migration, timezone sync, sqlproj validation |
| Enterprise docs | `01_sc_forecast/enterprise/*.md` | Enterprise alignment, multi-mart scale, Fabric vs enterprise comparison |
| Mermaid diagrams | `diagrams/*.mmd`, `diagrams/svg/*.svg` | Previously documented architecture diagrams and feature placement |
| Scripts | `scripts/deep_verify.py`, `scripts/health_check.py` | Automated checks, validation assumptions |
| Lineage explorer | `lineage_explorer/app.py`, `lineage_explorer/data/*.csv`, `templates/lineage.html` | Actual exported lineage, registry, views, run history, rendered augmentation |

### 2.2 v10 Local Evidence

Read all files under `Enterprise_SupplyChain_Dev_architect`:

| Group | Files | Why it matters |
|---|---|---|
| Core proposal | `01_super_plan_medallion_refactor.md` | Current target v10 Medallion plan |
| Architecture diagrams | `02_architecture_blueprint_mermaid.md`, `../diagrams/*.mmd` | Physical/logical architecture, control plane, staging/direct decision |
| Feature parity | `03_v9_feature_parity_checklist.md` | Claimed v9 capabilities preserved in v10 |
| Enterprise ETL alignment | `04_revised_enterprise_etl_standards_proposal.md` | Current interpretation of Enterprise ETL standards and Direct Lake/TableDictionary corrections |
| EDW fallback | `15_v10_edw_supplement_exit_strategy.md`, `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md` | Object-level `_edw` fallback lifecycle, validation, and retirement |
| Readiness/cleanup | `16_v10_readiness_scorecard_and_v9_cleanup.md` | Readiness score and non-destructive v9 cleanup candidate list |
| Enterprise ETL standards | `SQL Server Data Warehouse Standards.docx` | Enterprise standards to map against v10; local-only evidence unless sharing is approved |

### 2.3 Version-Control Evidence

Use git history to recover old architecture edits and avoid relying only on the latest reorganized folder:

| Command | Purpose |
|---|---|
| `git log --oneline --decorate --all --max-count=100` | Identify architecture, restructure, README restore, EDW source swap, lineage refresh commits |
| `git show --stat <commit>` | See which 01_docs/code changed in a commit |
| `git show <commit>:<path>` | Read historical file version before reorg or cleanup |
| `git diff <old>..<new> -- <path>` | Compare how a design note changed over time |

Initial high-signal commit labels to inspect:

- `Restore detailed README`
- `Restructure project + EDW source swap docs + cleanup`
- `Move generic operations docs to root 01_docs/operations`
- `Fix README structure`
- `Clean repo structure`
- `Auto-refresh lineage data`

### 2.4 Official / External Evidence

Use official Microsoft docs only when the claim depends on Fabric behavior:

- Direct Lake and fallback behavior.
- Direct Lake on SQL endpoint vs Direct Lake on OneLake.
- Lakehouse SQL analytics endpoint read/write limitations.
- Warehouse T-SQL surface area.
- Warehouse statistics/table constraints.
- Materialized Lake Views only as a future/POC option.

## 3. Audit Workflow

### Phase A - Inventory And Chronology

Output: `06_v9_source_inventory_and_chronology.md`

Steps:

1. List every v9/v10/Enterprise ETL source file.
2. Mark whether the file was read fully, sampled, or not yet read.
3. Map git commits that changed architecture docs or lineage exports.
4. Identify stale docs vs current docs by comparing overlapping content.

Exit criteria:

- No source file remains unclassified.
- Historical commits with architecture impact are identified.
- ADR and readiness outputs are linked when the audit finds a decision-worthy risk.

### Phase B - v9 Capability Extraction

Output: `07_v9_capability_evidence_ledger.md`

Extract v9 capabilities into an evidence ledger:

| Capability Area | Examples To Capture |
|---|---|
| Physical architecture | Workspaces, Lakehouse, Warehouse, schemas, shortcuts, SQL endpoint |
| Metadata registry | `sp_registry` columns, source objects, project, frequency, load type |
| Generic load framework | `usp_generic_load`, load patterns, CTAS/MERGE/overwrite/incremental |
| Multi-mart orchestration | `pl_sc_master`, `pl_sc_mart`, `project`, ForEach behavior |
| Scheduling | Fabric trigger, cron expression, `next_run_time`, smart skip |
| Silver DAG | `depends_on`, wave planner, wave runtime table, parent-child pipeline |
| DQ | rules, gates, result store, active/inactive status, performance tradeoff |
| Lineage | `source_objects`, `usp_build_lineage`, `sp_lineage`, lineage explorer augmentation |
| Audit/logging | `sp_run_history`, `pipeline_run_log`, finalizer, retry/failure behavior |
| TableDictionary | `vw_table_dictionary`, CST mapping, enterprise field mapping |
| Timezone | UTC/CST/VN handling, `ufn_utc_to_cst` |
| Semantic model | Direct Lake refresh/framing, Gold source tables, measure parity |
| CI/CD/deployment | sqlproj validation, GitHub workflow, Fabric deployment assumptions |
| Security/governance | approvals, schema-based access, TableDictionary security gaps |
| Performance/cost | runtime baseline, concurrency, performance_baseline, pipeline_cost_log |
| EDW/source swap | `_edw` supplement tables, rendered bridge, rollback docs |

Ledger row format:

| ID | v9 capability | Evidence | Current implementation | v10 coverage | Enterprise ETL alignment | Gap | Action |
|---|---|---|---|---|---|---|---|
| V9-001 | capability name | file:line | concise summary | covered/partial/missing | align/adapt/conflict | issue | proposed fix |

Exit criteria:

- Every major v9 feature has at least one evidence row.
- Rows with no v10 mapping are explicitly marked `Missing`.
- Rows with Enterprise ETL conflict are explicitly marked `Conflict` or `Adapt`.

### Phase C - v10 Coverage Review

Output: update `07_v9_capability_evidence_ledger.md` and create `08_v10_gap_matrix.md`.

For each v9 capability:

1. Find current v10 coverage in `01_super_plan_medallion_refactor.md`, `03_v9_feature_parity_checklist.md`, or Mermaid diagrams.
2. Score coverage:
   - `Covered`: same capability explicitly retained.
   - `CoveredWithChange`: retained but renamed or moved.
   - `Partial`: concept present, implementation detail missing.
   - `Missing`: no v10 mention.
   - `IntentionallyRemoved`: removed with explicit rationale and approval requirement.
3. Add required v10 amendment if `Partial` or `Missing`.

Exit criteria:

- v10 coverage score exists for every v9 capability.
- No v9 feature disappears silently.

### Phase D - Enterprise ETL Standards Mapping

Output: `09_enterprise_etl_standards_mapping_matrix.md`

Map Enterprise ETL DOCX standards to v10:

| Enterprise ETL standard | Apply Directly | Adapt For Fabric | Defer/POC | Not Applicable | v10 action |
|---|---|---|---|---|---|

Required challenge points:

- Power BI views vs Direct Lake physical tables.
- TableDictionary existing v9 adapter vs new build.
- WRK/ENH/DW suffixes vs Enterprise ETL email Pascal Case instruction.
- Source data not maintained in DW vs optional BronzeMirror/Staging exception.
- Primary key duplicate tests vs Fabric constraints not enforced.
- ADW HASH/REPLICATE/CCIX/CIX/PolyBase vs Fabric Warehouse/OneLake behavior.
- Security through schema/AD groups vs Fabric workspace/item/semantic security.

Exit criteria:

- Every Enterprise ETL DOCX section has an apply/adapt/defer/not-applicable classification.
- Every conflict has a Fabric-specific rationale.

### Phase E - Final Architecture Corrections

Output: update v10 docs only after the matrices are complete.

Allowed changes:

- Update v10 diagrams to add missing control-plane components.
- Update v10 plan to reflect actual v9 behavior.
- Add migration phases only where backed by evidence.
- Add Enterprise ETL standards overlay only where platform-compatible.

Not allowed:

- Rewriting v10 based on assumptions.
- Removing v9 features for aesthetic Medallion alignment.
- Treating Direct Lake as view-based without fallback validation.
- Treating TableDictionary as missing when v9 has an adapter.

## 4. Review Cadence

After each source group is read:

1. Summarize verified findings.
2. Compare directly against current v10.
3. Mark gaps immediately.
4. Do not wait until the end to record gaps.

Suggested checkpoints:

- Checkpoint 1: root context + forecast project docs.
- Checkpoint 2: operations docs + enterprise docs.
- Checkpoint 3: scripts + lineage explorer + CSV exports.
- Checkpoint 4: git history deltas.
- Checkpoint 5: Enterprise ETL DOCX mapping.
- Checkpoint 6: final v10 correction list.

## 5. Completion Criteria

Audit is not complete until:

- All v9 files are read or explicitly marked not relevant with reason.
- Git history has been sampled for architecture-impact commits.
- Enterprise ETL DOCX is mapped section by section.
- Every v9 capability is mapped to v10 coverage.
- Every gap has an action: update v10, defer with validation, or reject with rationale.
- Mermaid diagrams render after any updates.
- Final report lists both preserved strengths and real gaps.

## 6. Expected Final Artifacts

```text
Enterprise_SupplyChain_Dev_architect/
├── 05_deep_audit_protocol.md
├── 06_v9_source_inventory_and_chronology.md
├── 07_v9_capability_evidence_ledger.md
├── 08_v10_gap_matrix.md
├── 09_enterprise_etl_standards_mapping_matrix.md
└── 10_final_v10_amendment_plan.md
```

Only after these artifacts exist should the v10 architecture be treated as deeply reviewed.
