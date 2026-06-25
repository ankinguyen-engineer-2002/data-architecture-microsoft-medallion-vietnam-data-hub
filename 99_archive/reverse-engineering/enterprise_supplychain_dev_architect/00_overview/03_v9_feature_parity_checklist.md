# v10 Feature Parity Checklist Against v9

This checklist is a non-negotiable design guardrail: v10 must preserve the strong operating capabilities from v9 while changing the Medallion physical layout.

## 1. Control Plane Capabilities To Preserve

| v9 capability | v9 object / mechanism | v10 control-plane name | v10 requirement |
|---|---|---|---|
| Generic load framework | `meta.usp_generic_load` | Generic SQL Load Runner | Keep one reusable runner; extend with `access_mode` instead of per-table SPs |
| 8 load patterns | `load_type` in `sp_registry` | Load Pattern Router | Preserve overwrite, incremental, upsert, datekey, daterange, identity, cdc, scd2 support |
| Metadata-driven config | `meta.sp_registry` | Asset Registry | Keep config-driven onboarding: source definition/model + registry row, no pipeline JSON change |
| Multi-mart routing | `sp_registry.project`, `pl_sc_master`, `pl_sc_mart` | Mart Routing Engine | Preserve project-based routing and parallel mart execution |
| Cron scheduling | `cron_expression`, `ufn_cron_is_due` | Schedule Gate | Preserve cron/frequency evaluation per asset |
| Smart skip | `next_run_time`, `ufn_should_run` | Smart Skip Engine | Preserve due-only execution; do not reload monthly/stale-ineligible assets |
| Concurrency control | pipeline ForEach batch counts | Execution Planner | Preserve per-layer batch sizing and project parallelism |
| DAG wave computation | `depends_on`, `usp_compute_slv_waves`, `slv_dag_waves_runtime` | DAG Wave Planner | Preserve dependency-based Silver execution |
| Parent-child Silver pipeline | `pl_sc_silver`, `pl_sc_silver_wave` | Wave Runner | Preserve wave-level parallelism |
| Data Quality engine | `dq_rules`, `usp_check_dq_single`, `pl_dq_check` | DQ Gate Engine | Preserve config-driven DQ and fail/warn gate behavior |
| DQ results history | `dq_results` | Quality Result Store | Preserve DQ auditability |
| Auto lineage | `source_objects`, `usp_build_lineage`, `sp_lineage` | Lineage Builder | Preserve source-to-target lineage, extended for logical Bronze and optional staging |
| Execution logging | `usp_log_run`, `sp_run_history` | Run Audit Logger | Preserve per-asset run logging, rows, duration, status, errors |
| Pipeline logging | `usp_log_pipeline_run`, `pipeline_run_log` | Pipeline Audit Logger | Preserve pipeline-level start/end/final status |
| Finalization | `usp_finalize_pipeline` | Finalizer | Preserve final lineage rebuild, status update, success/failed counts |
| Snapshot conflict mitigation | SP retry + pipeline retry + batch tuning | Retry / Conflict Guard | Preserve retry strategy and concurrency-safe logging |
| Timezone sync | `ufn_utc_to_cst`, CST columns | Timezone Normalizer | Preserve enterprise timezone alignment and run-history views |
| TableDictionary mapping | `vw_table_dictionary` | Enterprise Dictionary Adapter | Preserve and extend existing v9 enterprise metadata compatibility; do not rebuild TableDictionary from scratch |
| Schema contracts | `schema_contracts`, `usp_validate_schema_contracts` | Schema Contract Gate | Promote from optional to first-class preflight gate |
| Performance baseline | `performance_baseline` | Performance Baseline Monitor | Preserve baseline comparison for runtime regression |
| Cost monitoring | `pipeline_cost_log` | Cost Monitor | Preserve cost logging and cost trend visibility |
| Semantic refresh | PBISemanticModelRefresh activity | Semantic Refresh Controller | Preserve semantic model refresh/framing discipline after Gold physical table publish; validate Direct Lake does not unexpectedly fall back |
| Legacy/debug utilities | `usp_run_silver_dag`, `usp_debug_loop` | Recovery / Debug Utility | Keep as controlled fallback and troubleshooting path |

## 2. v10 Additions On Top Of v9

| v10 addition | Why it exists | Impact on v9 |
|---|---|---|
| Logical Bronze from shortcuts | Aligns with Fabric Medallion and reduces unnecessary copy | Replaces mandatory local Bronze duplication |
| Optional staging / BronzeMirror | Keeps operational snapshot/replay/performance capability | Preserves Warehouse-native strengths only where needed |
| `access_mode` metadata | Chooses direct vs staging per asset | Extends `sp_registry` instead of hardcoding |
| Domain Silver schemas | Aligns with enterprise schema standards | Replaces generic `silver` schema naming over time |
| Dedicated Gold serving boundary | Separates transformation from consumption | Improves BI/semantic model discipline |
| Source contract gate | Prevents direct-read instability | Makes shortcut usage governed, not blind |
| Enterprise-reusable flag | Decides SupplyChain-owned vs EnterpriseData-owned Silver | Avoids over-moving domain-specific logic |
| EDW supplement exit lifecycle | Keeps `_edw` fallback initially while making exit object-level and auditable | Preserves v9 fallback, but prevents permanent Bronze duplication |

## 3. Acceptance Rule

v10 is not accepted unless all v9 control-plane capabilities above are either:

1. Preserved unchanged.
2. Preserved with an explicit renamed component.
3. Replaced by a stronger equivalent with documented migration behavior.

No v9 capability should be silently removed during the Medallion refactor.

## 4. Audit Caveat

After the 2026-04-30 deep-read, do not interpret every row above as "fully active in v9 production flow".

- [Verified] Smart skip has now been live-verified for `pl_sc_bronze` and `pl_sc_gold` in `readiness_exports/20260430_230936/pipeline_sql_queries.csv`. Silver currently has all daily assets, but mixed-frequency Silver would require explicit schedule handling.
- [Verified] DQ engine exists, but DQ gate activities are currently deactivated for performance.
- [Verified] Schema contracts, performance baseline, and cost monitor objects exist, but are not fully wired into the active pipeline flow.
- [Verified] Source-target reconciliation is a v10 work item, not a completed v9 feature.
- [Verified] Alerting and CI/CD are designed but blocked/not active.
- [Verified] Multi-mart routing is active at master/mart level, but live Silver DAG execution is not yet project-filtered. v10 must fix this before true multi-mart scale.
- [Verified] EDW supplement must follow `ADR-002`: two objects are `ExitCandidate`, two are `NotReady`, and no `_edw` fallback is removed without dual-read validation and approval.

v10 requirement: preserve all mature v9 capabilities and explicitly implement or activate the designed-but-inactive capabilities where they are required for the new architecture.
