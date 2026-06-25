# v10 Readiness Scorecard And v9 Cleanup Candidate List

Date: 2026-05-01

Purpose: summarize whether the v10 architecture package is ready to proceed and list v9 cleanup candidates without executing any destructive action.

## 1. Decision Summary

```text
Readiness score: 88 / 100

Ready for:
- Non-destructive v10 side-by-side build planning.
- v10 metadata/control-plane scaffolding.
- Bob/Rakesh approval discussion.
- Parallel validation design.

Not ready for:
- Production cutover.
- Disabling v9 schedules.
- Dropping/deleting v9 SQL objects.
- Removing `_edw` fallback.
- Moving EnterpriseData-owned Silver/reference objects without approval.
```

## 2. Scorecard

| Area | Score | Evidence | Remaining risk |
|---|---:|---|---|
| v9 evidence freeze and live clone | 10 / 10 | `readiness_exports/20260430_230936/`; `detail_clone_v9_forecast/20260501_093155/` | Raw exports are local-only and intentionally ignored from Git |
| Bob/Rakesh architecture alignment | 13 / 15 | Bob feedback mapped in `09_bob_standards_mapping_matrix.md`; runbook uses Pascal Case/process schemas and dedicated Gold | Final technical design sign-off still required |
| EDW supplement exit strategy | 10 / 10 | `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`; `15_v10_edw_supplement_exit_strategy.md` | Object-level approval required before any direct cutover |
| v9 control-plane parity | 18 / 20 | `03_v9_feature_parity_checklist.md`; `07_v9_capability_evidence_ledger.md`; live clone has registry, lineage, DQ, run logs, DAG, smart-skip evidence | DQ gates, alerting, CI/CD, and some Phase 3 objects are not fully active |
| v10 implementation runbook | 14 / 15 | `14_v10_step_by_step_implementation_runbook.md` | Exact deployment scripts/DDL are not created yet |
| Source contract and reconciliation readiness | 8 / 12 | `schema_contracts` exist in v9 clone; v10 requires reconciliation gates | Reconciliation implementation and source SLA approval are pending |
| Security and governance model | 7 / 10 | Bob standards mapping and runbook define security matrix requirement | Detailed Fabric workspace/item/SQL endpoint/semantic grants are still pending |
| CI/CD and deployment readiness | 8 / 10 | v10 docs require non-destructive side-by-side build and validation gates | Actual CI/CD/sqlproj migration path is still not implemented |
| **Total** | **88 / 100** | Architecture package is strong enough for side-by-side implementation planning | Not sufficient for production cutover or v9 decommission |

## 3. Interpretation

- [Verified] The package is strong enough to start non-destructive v10 scaffolding because the architecture, object mapping, EDW fallback policy, and runbook are now documented.
- [Verified] The package is not strong enough to cut over production because source contracts, reconciliation, security, DQ gate mode, and Bob/Rakesh approval remain open.
- [Verified] The package is not strong enough to remove `_edw` fallback because two of four `_edw` objects are still `NotReady`, and the two `ExitCandidate` objects still require dual-read validation.

## 4. Cleanup Principles

No deletion has been executed.

Cleanup must follow this order:

1. Archive/freeze v9 definitions, pipeline definitions, row-count snapshots, run-history snapshots, and semantic dependencies.
2. Build v10 side-by-side.
3. Run v9 and v10 in parallel until validation gates pass.
4. Switch consumers only after Bob/Rakesh or assigned approver signs off.
5. Keep rollback window open.
6. Disable old schedules before deleting anything.
7. Ask Aric for explicit same-conversation destructive-operation approval before any delete/drop/truncate/disable action.

## 5. v9 Cleanup Candidates After v10 Cutover

These are candidates only. They must not be deleted during v10 build.

### 5.1 Pipeline candidates

| Pipeline | ID | Earliest safe action |
|---|---|---|
| `pl_sc_master` | `319a8160-3f3a-4b87-8ad6-75ac4f3ec184` | Disable schedule after v10 cutover and rollback window approval |
| `pl_sc_mart` | `9a1e7a12-30ab-465c-a45d-b051619193ac` | Archive after consumer switch and rollback window |
| `pl_sc_bronze` | `1bdbaebb-7222-4e9c-a45d-3e632bba846d` | Archive after all direct/staging v10 routes are validated |
| `pl_sc_silver` | `46437ae6-3a15-4697-957d-f1f44ba10633` | Archive after v10 project-aware Silver DAG passes |
| `pl_sc_silver_wave` | `57a09720-21a2-49b5-a472-1e19abd14f76` | Archive after v10 wave runner passes |
| `pl_sc_gold` | `94fc130e-f327-46a9-b7ba-cd2aa328c0da` | Archive after v10 Gold publish and semantic model cutover |
| `pl_dq_check` | `c32dc18d-d027-4672-9872-f73404cd7c6f` | Archive only after v10 DQ gate engine replaces it |

### 5.2 SQL schema candidates in old `SupplyChain_Warehouse`

Live clone source: `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/sql/02_object_counts_by_schema.csv`.

| Schema | Live object count | Cleanup rule |
|---|---:|---|
| `bronze` | 41 objects: 22 tables, 18 views, 1 stored procedure | Last-resort cleanup after v10 logical Bronze, Staging, and EDW fallback exits are proven |
| `silver` | 16 objects: 8 tables, 8 views | Cleanup only after v10 process schemas pass parallel validation |
| `gold` | 4 objects: 2 tables, 2 views | Cleanup only after dedicated v10 Gold Warehouse and 04_semantic/report cutover are approved |
| `meta` | 27 objects: 11 tables, 2 views, 11 stored procedures, 3 functions | Do not delete until v10 control plane proves full parity and audit retention is exported |

### 5.3 EDW-specific candidates

These are the last cleanup candidates, not first.

| Object | Cleanup condition |
|---|---|
| `bronze.usp_refresh_edw_tables` | Only after all four EDW supplement objects reach `RetiredFallback` |
| `bronze.brz_saleshistory_afi__invoicedetail_edw` | Only after object-level direct cutover, fallback retention, and approval |
| `bronze.brz_saleshistory_afi__invoiceheader_edw` | Only after source status changes from `NotReady` to validated `DirectActive`, fallback retention, and approval |
| `bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw` | Only after grain, snapshot coverage, metric parity, fallback retention, and approval |
| `bronze.ref_product_edw` | Only after source validation and EnterpriseData/reference ownership decision |

### 5.4 Semantic and report candidates

| Item | Cleanup rule |
|---|---|
| `SC_Control_Tower` semantic model | Cleanup candidate only, based on Aric's scope clarification |

Do not delete these report/model items as part of v9 cleanup:

- `SupplyChain_Gold` semantic model
- `Forecast Accuracy Gold` report
- `Supply Chain Control Tower` semantic model
- Any other report/semantic model unless Aric explicitly adds it to the cleanup scope

### 5.5 Dataflow boundary

Do not delete these four dataflows. They currently load data into `SupplyChain_Lakehouse`, and v8 depends on those Lakehouse tables.

| Dataflow | v10 rule |
|---|---|
| `df_brz_SalesHistory_AFI_InvoiceDetail` | Keep; map as upstream `LegacyDataflowBridge` feeding `SupplyChain_Lakehouse` |
| `df_brz_SalesHistory_AFI_InvoiceHeader` | Keep; map as upstream `LegacyDataflowBridge` feeding `SupplyChain_Lakehouse` |
| `df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1` | Keep; map as upstream `LegacyDataflowBridge` feeding `SupplyChain_Lakehouse` |
| `df_ref_product` | Keep; map as upstream `LegacyDataflowBridge` feeding `SupplyChain_Lakehouse` |

Do not delete any dataflow in this v9 cleanup scope.

## 6. Explicit Do-Not-Touch Boundary

Do not touch these during v10 build:

- v8 or production assets.
- `Enterprise_Lakehouse` item and its shortcuts, except read-only validation.
- `SupplyChain_Lakehouse`, except read-only validation.
- Existing Warehouses and Lakehouses. v10 may create new Warehouse/Lakehouse items, but cleanup scope must not delete existing ones.
- All Dataflows, including the four `df_brz_*` / `df_ref_product` feeds that populate `SupplyChain_Lakehouse`.
- Any non-`pl_sc_*` pipeline, notebook, dataflow, report, semantic model, or warehouse unless separately classified and approved.
- Old `SupplyChain_Warehouse` as a whole.
- Any workspace-level item outside the approved Supply Chain v10 scope.

## 7. Go / No-Go

| Stage | Decision | Reason |
|---|---|---|
| v10 architecture documentation | Go | Enough evidence and controls exist for review |
| v10 non-destructive side-by-side scaffolding | Conditional Go | Requires naming/item approval before Fabric mutation |
| v10 production cutover | No-Go | Needs parallel run, reconciliation, DQ mode, security, and semantic validation |
| v9 schedule disable | No-Go | Only after v10 cutover and rollback approval |
| v9 object deletion/drop | No-Go | Requires explicit object-level destructive approval |
| `_edw` fallback removal | No-Go | Requires ADR-002 lifecycle completion object-by-object |

## 8. Source References

Local evidence:

- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/analysis/03_v9_delete_candidates_review.md`
- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/run_summary.json`
- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/sql/02_object_counts_by_schema.csv`
- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/rest/items_by_type_summary.json`
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`

Official Microsoft sources:

- Microsoft Fabric shortcuts: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-shortcuts
- Microsoft Fabric medallion architecture: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- Lakehouse SQL analytics endpoint: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint
