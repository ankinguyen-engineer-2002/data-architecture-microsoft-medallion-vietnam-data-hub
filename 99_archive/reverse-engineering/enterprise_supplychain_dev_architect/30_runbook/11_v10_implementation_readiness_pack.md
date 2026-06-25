# v10 Implementation Readiness Pack

Date: 2026-04-30

Scope: complete the five pre-build readiness steps requested before starting the v10 physical refactor.

## 1. Readiness Decision

Status: **Ready for v10 side-by-side build planning, not ready for production cutover.**

Why:

- [Verified] Baseline export is complete and stored locally.
- [Verified] Current v9 control plane and pipeline definitions were read live from Fabric.
- [Verified] Smart skip is active for `pl_sc_bronze` and `pl_sc_gold` Lookup queries.
- [Verified] DQ pipeline exists and is active as a standalone pipeline, but the current master pipeline does not invoke DQ gates.
- [Verified] Phase 3 objects exist: schema contracts, performance baseline, pipeline cost log, validation SPs.
- [Need-verify] Enterprise ETL/Rakesh sign-off is still external and cannot be completed by this repo work alone.
- [Need-verify] Silver multi-mart filtering needs design correction before scaling beyond one project.

Conclusion:

```text
Do not rewrite v9.
Do not build destructively.
Build v10 side-by-side after sign-off.
Start with metadata/control-plane extensions, then Staging/Silver/Gold separation.
```

## 2. Step 1 - Freeze Baseline v9 Live

Baseline export folder:

```text
Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/
```

Exported evidence:

| Area | Evidence file | Result |
|---|---|---|
| Object inventory | `sql/00_object_inventory.csv` | 150 objects |
| Table metadata row-count snapshot | `sql/01_table_row_counts.csv` | 71 tables; Fabric metadata row counts are blank for many tables, use registry `rows_loaded` as operational baseline |
| Columns | `sql/02_columns.csv` | 3,751 columns |
| Registry | `sql/03_sp_registry.csv` | 28 active registered assets |
| Registry summary | `sql/04_sp_registry_summary.csv` | 5 layer/frequency groups |
| Smart skip registry | `sql/05_smart_skip_registry.csv` | 28 assets with due/not-due evaluation |
| Lineage | `sql/06_lineage.csv` | 52 lineage edges |
| DQ rules | `sql/07_dq_rules.csv` | 54 rules |
| DQ recent results | `sql/09_dq_results_recent.csv` | 38 recent rows |
| Run history | `sql/10_run_history_recent.csv` | 300 recent rows |
| Pipeline run log | `sql/11_pipeline_run_log_recent.csv` | 23 recent rows |
| TableDictionary adapter | `sql/12_table_dictionary.csv` | 28 dictionary rows |
| View definitions | `sql/13_view_definitions.csv` | 55 views |
| Routine definitions | `sql/14_routine_definitions.csv` | 28 routines |
| Phase 3 objects | `sql/15_phase3_object_existence.csv` | 7/7 checked objects exist |
| Schema contracts | `sql/16_schema_contracts.csv` | 674 contracted source columns |
| Performance baseline | `sql/17_performance_baseline.csv` | 28 baselined SPs |
| Cost log | `sql/18_pipeline_cost_log.csv` | 1 cost log row |
| Fabric items | `rest/items.json` | 133 workspace items |
| Warehouses | `rest/warehouses.json` | 4 Warehouses |
| Lakehouses | `rest/lakehouses.json` | 3 Lakehouses |
| Semantic models | `rest/semanticModels.json` | 4 Semantic Models |
| Pipeline definitions | `pipeline_definitions/*/pipeline-content.json` | 7 Supply Chain pipelines decoded |

Operational baseline from registry `rows_loaded`:

| Layer | Count | Notes |
|---|---:|---|
| BRZ | 7 | Daily; 3 EDW-backed staging exceptions |
| REF | 11 | 1 daily, 10 monthly |
| SLV | 8 | Daily |
| GLD | 2 | Daily |
| Total registry assets | 28 | All active |

## 3. Step 2 - Verify Need-Verify Items

### 3.1 Smart Skip

[Verified] `pl_sc_bronze` has due-only Lookup:

```sql
AND (r.cron_expression IS NULL OR r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())
```

[Verified] `pl_sc_gold` has the same due-only filter.

[Verified] Current due/not-due state:

| State | Count | Evidence |
|---|---:|---|
| Due now | 18 | BRZ 7 + REF daily 1 + SLV 8 + GLD 2 |
| Not due | 10 | Monthly REF assets |

[Likely] The old doc conflict is resolved for Bronze/REF and Gold. However, Silver still runs through DAG waves and is currently all daily, so the lack of direct `next_run_time` filter in Silver is not an immediate issue. It becomes a v10 requirement if future Silver assets have mixed frequencies.

### 3.2 DQ Gates

[Verified] `pl_dq_check` exists and is active:

- `lk_dq_rules`
- `fe_dq_check`
- `exec_dq_single`

[Verified] `pl_sc_master` currently does not invoke `pl_dq_check`.

[Verified] DQ rule state:

| State | Count |
|---|---:|
| Active rules | 30 |
| Inactive rules | 24 |
| Total | 54 |

v10 action:

- Keep DQ engine.
- Add explicit gate mode: `Off`, `WarnOnly`, `CriticalStops`.
- Decide whether DQ gates run after Staging, Silver, and Gold in the side-by-side build.

### 3.3 Phase 3 Objects

[Verified] The following objects exist:

- `meta.schema_contracts`
- `meta.performance_baseline`
- `meta.pipeline_cost_log`
- `meta.usp_validate_schema_contracts`
- `meta.usp_check_dq_single`
- `meta.usp_compute_slv_waves`
- `meta.usp_finalize_pipeline`

[Verified] Schema contracts contain 674 source columns.

[Verified] Performance baseline contains 28 SP baselines.

[Verified] Cost log has 1 row.

v10 action:

- Promote schema contract validation into a pre-load gate.
- Wire performance/cost monitoring into the v10 finalizer or document as optional monitoring.

### 3.4 Multi-Mart / Silver Filtering

[Verified] `pl_sc_master` discovers projects:

```sql
SELECT project
FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry
WHERE is_active = 1 AND project IS NOT NULL
GROUP BY project
ORDER BY CASE
    WHEN project = 'shared' THEN 0
    WHEN project = 'forecast_accuracy' THEN 1
    WHEN project = 'inventory_health' THEN 2
    ELSE 99
END, project
```

[Verified] `pl_sc_mart` passes `project_name` to Bronze, Silver, and Gold.

[Need-verify / gap] Live `pl_sc_silver` and `pl_sc_silver_wave` do not visibly filter wave lookup by project. `meta.usp_compute_slv_waves` also computes all active Silver rows without project filtering.

Current impact:

- Low for current single-project state.
- High for v10 multi-mart scaling.

v10 action:

- Add `project` to `meta.slv_dag_waves_runtime` or compute waves per project.
- Filter Silver wave lookup by `project_name`.
- Add cross-mart dependency handling explicitly.

### 3.5 EDW Supplement

[Verified] `pl_sc_master` starts with `refresh_edw`.

[Verified] Current registry shows EDW-backed sources for:

- `brz_saleshistory_afi__invoicedetail`
- `brz_saleshistory_afi__invoiceheader`
- `brz_supplychain_enh_1__demandforecastsnapshotdaily`
- `ref_product`

v10 action:

- Keep all four as `EDWSupplement` / `StagingException` for initial v10 build.
- Split status between `ExitCandidate` and `NotReady`; do not treat all four as the same maturity.
- Do not move any object to direct shortcut until source completeness, grain, SLA, performance, and owner approval are validated.

| Object | V9 note | Live v9 source | Initial v10 status | Build action |
|---|---|---|---|---|
| `brz_saleshistory_afi__invoicedetail` | `Ready` | `_edw` | `EDWSupplement_ExitCandidate` | Keep fallback active; enable dual-read validation |
| `brz_saleshistory_afi__invoiceheader` | `Not Ready` | `_edw` | `EDWSupplement_NotReady` | Keep fallback active; block direct cutover |
| `brz_supplychain_enh_1__demandforecastsnapshotdaily` | `Not Ready` | `_edw` | `EDWSupplement_NotReady` | Keep fallback active; validate grain and snapshot coverage before any cutover |
| `ref_product` | `Ready` | `_edw` | `EDWSupplement_ExitCandidate` + owner decision | Keep fallback active; validate source and decide EnterpriseData ownership |

Detailed runbook:

- `Enterprise_SupplyChain_Dev_architect/30_runbook/15_v10_edw_supplement_exit_strategy.md`
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`

## 4. Step 3 - Object Classification Mapping

Detailed mapping:

- `Enterprise_SupplyChain_Dev_architect/20_proposals/12_v10_object_classification_mapping.md`

Summary:

| Target class | Count | Build decision |
|---|---:|---|
| StagingException / EDWSupplement | 4 total: 2 ExitCandidate + 2 NotReady | Keep persisted staging initially; validate ExitCandidates first |
| LogicalBronzeCandidate / DirectReadCandidate | 4 BRZ | Direct by default if source contract passes |
| ReferenceMaster / NeedOwnerDecision | 7 REF | Enterprise ETL/Rakesh ownership decision |
| ReferenceMaster / DomainReference | 3 REF | Keep local unless EnterpriseData takes ownership |
| DomainSilver | 8 SLV | Keep in SupplyChain Processing Warehouse initially |
| GoldServing | 2 GLD | Publish to dedicated Gold Warehouse physical tables |

## 5. Step 4 - Sign-Off Checklist

This step cannot be completed locally because Enterprise ETL/Rakesh approval is external. The required pack is ready.

Sign-off questions:

1. Naming: pure Pascal Case schemas or suffix pattern (`ENH`, `DW`, `WRK`)?
2. Silver ownership: which Silver/reference entities are enterprise reusable?
3. TableDictionary: is `vw_table_dictionary` accepted, or is a physical EnterpriseData sync required?
4. Power BI serving: is Gold physical table + Direct Lake semantic contract accepted as the Fabric interpretation of the old view rule?
5. Security: who owns workspace/item/04_semantic/SQL endpoint access approval?
6. DQ mode: should v10 run DQ gates in `WarnOnly` first, then move to `CriticalStops`?
7. EDW supplement: what exact SLA/coverage/grain/performance evidence and approval window are required before switching each `_edw` object to direct `Enterprise_Lakehouse`?

## 6. Step 5 - What To Build Next

Build order:

1. **Control-plane metadata extension**
   - Add metadata model for `canonical_layer`, `access_mode`, `physical_workspace`, `physical_item`, `domain_group`, `is_enterprise_reusable`, `staging_reason`, `source_contract_status`, `approval_status`.
   - Keep backward compatibility with current `sp_registry`.

2. **Access decision engine**
   - Route each asset as `DirectShortcut`, `StageRequired`, `EDWSupplement`, `ManualSeed`, `EnterpriseSilver`, or `GoldServing`.

3. **Smart skip and schedule gate hardening**
   - Preserve current Bronze/Gold due filters.
   - Add future-safe Silver frequency handling if mixed-frequency Silver is allowed.

4. **Project-aware Silver DAG**
   - Compute waves by project.
   - Preserve cross-mart dependency semantics.

5. **Source contract and reconciliation gates**
   - Use existing 674-column `schema_contracts`.
   - Add source-target reconciliation for high-volume facts and staged exceptions.

6. **Staging/Bronze refactor**
   - Keep EDW supplement staging.
   - Convert eligible Bronze objects to direct shortcut reads.
   - Move significant transformations out of Bronze into domain Silver.

7. **Domain Silver schemas**
   - Proposed local schemas:
     - `SalesHistory`
     - `ForecastHistory`
     - `OpenOrderHistory`
     - `ReferenceMaster`
   - Promote only approved reusable objects to EnterpriseData.

8. **Dedicated Gold serving**
   - Proposed item: `SupplyChain_Gold_Warehouse`.
   - Proposed schema: `ForecastAccuracy`.
   - Publish physical Gold tables for Direct Lake.

9. **Semantic model validation**
   - Validate Direct Lake behavior.
   - Compatibility views only if fallback/import/DirectQuery is accepted.

10. **Parallel run and cutover**
    - Run v9 and v10 side-by-side.
    - Compare registry row counts, source-target reconciliation, DQ results, Gold aggregates, and semantic measures.

## 7. Target Architecture After Adjustment

```text
Enterprise_Data workspace
  -> upstream source products
  -> optional enterprise reusable Silver/reference assets

SupplyChain Dev workspace
  -> Enterprise_Access_Lakehouse
       Role: logical Bronze through shortcuts

  -> SupplyChain_Processing_Warehouse
       Meta: v9/v10 control plane
       Staging: EDW supplement and other exception mirrors only
       ReferenceMaster: domain/reference assets not enterprise-owned
       SalesHistory: domain Silver
       ForecastHistory: domain Silver
       OpenOrderHistory: domain Silver

  -> SupplyChain_Gold_Warehouse
       ForecastAccuracy: physical Gold serving tables

  -> SupplyChain Semantic Model
       Direct Lake over Gold physical tables
```

## 8. Build Readiness Risks

| Risk | Status | Mitigation |
|---|---|---|
| Source contract not active in flow | Open | Promote schema contract validation to pre-load gate |
| DQ gates not called by master | Open | Add v10 DQ mode and explicit gate placement |
| Silver DAG not project-filtered | Open | Add project-aware wave computation |
| Naming not signed off | Open | Enterprise ETL/Rakesh decision before physical DDL |
| TableDictionary physical sync unclear | Open | Ask Enterprise ETL/Rakesh; keep adapter as default |
| Direct Lake view fallback | Open | Use physical Gold tables and validate semantic model mode |
| EDW supplement still temporary | Open | Keep `EDWSupplement` access mode |

## 9. Recommendation

Start v10 build only after sign-off on naming/ownership. The first implementation unit should be metadata/control-plane extension, not physical object moves.

Recommended immediate next engineering task:

```text
Build v10 metadata compatibility layer and project-aware DAG design in documentation/DDL draft,
then review with Enterprise ETL/Rakesh before deploying any Fabric object changes.
```
