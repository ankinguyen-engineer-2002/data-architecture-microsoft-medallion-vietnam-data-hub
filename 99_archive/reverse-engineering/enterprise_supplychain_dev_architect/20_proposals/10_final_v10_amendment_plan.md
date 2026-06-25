# Final v10 Amendment Plan After Deep v9/Bob Audit

Date: 2026-04-30

Purpose: convert the v9 audit, Bob feedback, and Bob SQL Server Data Warehouse Standards review into concrete amendments before any v10 implementation.

## 1. Executive Position

- [Verified] The v10 direction remains valid: Hybrid Medallion, logical Bronze through shortcut-backed access, domain-owned Silver, dedicated Gold serving, and v9 control-plane preservation.
- [Verified] v10 must not be sold as a clean rewrite. It is a large architecture refactor that keeps the v9 operating model and changes physical placement, naming, governance, and source-access policy.
- [Verified] Bob's core objection is covered: the shortcut-backed Enterprise Lakehouse should be treated as the logical Bronze layer; local Warehouse `bronze` should not be the canonical Bronze layer.
- [Verified] Smart skip was live-verified for Bronze/REF and Gold Lookup queries in the 2026-04-30 readiness export.
- [Need-verify] A few v9 features still need implementation or sign-off before claiming "preserved 100%": master-level DQ gates, source-target reconciliation, project-aware Silver DAG, alerting, CI/CD, and security.

Short conclusion:

```text
Keep v10 Hybrid Medallion.
Make the control plane stronger and more honest.
Do not remove optional staging capability.
Do not claim unverified v9 features are already active.
```

## 2. Architecture Amendments Required

### Amendment A - Bronze Definition

[Verified] Target Bronze should be logical/source-aligned:

```text
Enterprise_Data upstream products
  -> Enterprise_Access_Lakehouse shortcuts in SupplyChain Dev
  -> Logical Bronze
```

Rules:

- Bronze mimics source structure.
- Bronze does not contain significant business enhancement.
- If current `bronze` objects have casts, standardization, filters, joins, or business meaning, classify them as Staging or Silver candidates.
- Optional `BronzeMirror`/`Staging` remains as an operational pattern, not as the default medallion layer.
- `_edw` fallback exits are governed by `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`; two objects start as `ExitCandidate`, two remain `NotReady`.

### Amendment B - Staging Exception Policy

[Verified] Do not delete staging capability from the framework.

Keep staging only when one of these is true:

- Source contract/SLA is not stable.
- Run-level snapshot consistency is required.
- Replay/debug/audit of exact source input is required.
- Direct shortcut read is too slow or unstable.
- Warehouse-native CTAS/DML/persisted state is required.
- EDW supplement remains active; two ready objects become dual-read exit candidates, while not-ready objects stay staged.

### Amendment C - Silver Placement

[Verified] Silver placement should be by ownership/reuse, not by name alone.

```text
Enterprise reusable/conformed Silver -> Enterprise_Data SupplyChain_Warehouse / approved enterprise item
Domain-specific Supply Chain Silver -> SupplyChain Dev Processing Warehouse
```

Required classification:

- Enterprise reusable/conformed.
- Supply Chain domain-specific.
- Temporary staging/working.
- Gold serving.

### Amendment D - Gold Serving

[Verified] Create a dedicated Gold serving boundary.

For current Fabric/Power BI Direct Lake behavior, Gold semantic sources should be physical Gold tables, not default non-materialized SQL views.

Rationale:

- Microsoft Direct Lake docs state Direct Lake is optimized for Delta tables in OneLake and useful for Gold analytics layers.
- Direct Lake on SQL endpoints can discover SQL views, but non-materialized SQL views can fall back to DirectQuery.
- Direct Lake on OneLake does not support semantic model tables based on non-materialized SQL views.

Source:

- https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-overview

## 3. v9 Capabilities: Preserve vs Complete

### Existing Capabilities To Preserve

- [Verified] Metadata registry / `sp_registry`.
- [Verified] Generic SQL load runner / `meta.usp_generic_load`.
- [Verified] Eight load pattern model: overwrite, incremental, upsert, datekey, daterange, identity, cdc, scd2.
- [Verified] Multi-mart routing with `project` and `pl_sc_mart`.
- [Verified] DAG/wave Silver orchestration.
- [Verified] Auto lineage from metadata/source objects.
- [Verified] Run logging, pipeline logging, finalizer.
- [Verified] Timezone/TableDictionary CST alignment.
- [Verified] Semantic model refresh discipline.
- [Verified] Metadata-driven onboarding.

### Designed Or Created But Not Fully Active

- [Verified] Smart skip: live `pl_sc_bronze` and `pl_sc_gold` Lookup queries check `next_run_time`; current registry evaluates 18 due assets and 10 monthly REF assets not due.
- [Verified] DQ engine exists, but DQ gates are deactivated for performance.
- [Verified] Source-target reconciliation is still a planned work item, not fully implemented.
- [Verified] Schema contracts exist but are not in pipeline flow.
- [Verified] Performance baseline and cost monitoring objects exist but are not fully wired into the active pipeline flow.
- [Verified] Alerting is designed but blocked by IT/admin permissions.
- [Verified] CI/CD/sqlproj validation is designed but blocked/not active.

## 4. Control Plane v10 Target

The v10 control plane should sit horizontally across layers:

```text
Meta / Control Plane
  -> Asset Registry
  -> Access Decision Engine
  -> Generic SQL Load Runner
  -> Mart Routing Engine
  -> Schedule Gate
  -> Smart Skip Engine
  -> DAG Wave Planner
  -> DQ Gate Engine
  -> Source Contract Gate
  -> Source-Target Reconciliation
  -> Lineage Builder
  -> Run/Pipeline Audit Logger
  -> Finalizer
  -> Enterprise Dictionary Adapter
  -> Timezone Normalizer
  -> Performance/Cost Monitor
  -> Semantic Refresh Controller
```

Mandatory metadata extensions:

| Field | Purpose |
|---|---|
| `canonical_layer` | Logical layer: Bronze, Staging, Silver, Gold |
| `physical_workspace` | Actual Fabric workspace |
| `physical_item` | Actual Lakehouse/Warehouse/Semantic item |
| `access_mode` | DirectShortcut, StageRequired, EDWSupplement, ManualSeed, EnterpriseSilver, GoldServing |
| `domain_group` | Business/process schema group |
| `is_enterprise_reusable` | Whether Silver should move to EnterpriseData ownership |
| `staging_reason` | Why persisted staging is needed |
| `source_contract_status` | Stable, Pending, Exception |
| `approval_status` | Draft, BobReviewed, RakeshApproved |

## 5. Bob Standards Application

Apply directly:

- No user/business objects in `dbo`.
- Explicit column lists; avoid `SELECT *` unless approved.
- PK metadata required for duplicate checks.
- Architect/technical design approval before production development.
- TableDictionary metadata must exist for all managed tables.
- Significant source enhancements belong in Silver/ENH, not Bronze.
- End users/BI should only read curated serving objects.

Adapt for Fabric:

- PowerBI view rule -> Gold physical tables + semantic model contract for strict Direct Lake.
- HASH/REPLICATE/CCIX/CIX -> Fabric performance/readiness checklist, not literal ADW distribution rules.
- PolyBase external tables -> OneLake shortcuts/source contracts.
- SQL Agent alerts -> Fabric Pipeline/Power Automate/Teams/Graph/Data Activator pattern.
- Schema security -> workspace/item/04_semantic/SQL endpoint security matrix.
- TableDictionary -> existing `vw_table_dictionary` adapter plus optional physical sync if Bob/Rakesh require it.

Need Bob/Rakesh clarification:

- Exact Silver/Gold schema naming: `ForecastHistory_ENH` / `ForecastAccuracy_DW` vs pure Pascal Case `ForecastHistory` / `ForecastAccuracy`.
- Whether `vw_table_dictionary` is enough or a physical EnterpriseData sync/export is required.
- Which current Silver objects are enterprise-reusable.
- Whether the target CI/CD should align to full Enterprise `.sqlproj` ProjectReference.

## 6. Work Estimate After Audit

This is a revised estimate after finding smart-skip/status conflicts and inactive Phase 3 capabilities.

| Work type | Estimate | Meaning |
|---|---:|---|
| Preserve mostly unchanged | 25-30% | Generic runner logic, registry concept, DAG, lineage, audit, semantic refresh patterns |
| Modify/refactor | 50-55% | Metadata model, source access, schema naming, Silver/Gold placement, lineage semantics, DQ semantics, pipeline lookups |
| Build/activate new | 20-25% | Gold Warehouse, source contract gates, reconciliation, alerting/SLA, CI/CD section, security matrix |

[Likely] This is not a v9 rewrite, but it is a major refactor. The highest risk is not SQL transformation logic; the highest risk is control-plane correctness across new physical boundaries.

## 7. Implementation Phases

### Phase 0 - Evidence Freeze

- Export current registry, lineage, view definitions, table row counts, DQ rules/results, run history, semantic model dependencies.
- Preserve live Bronze/Gold smart-skip Lookup SQL and decide whether Silver needs mixed-frequency skip behavior.
- Verify which Phase 3 objects are in active pipeline flow.
- Save object mapping before rename.

Exit gate:

- No feature claim remains unverified if it affects v10 parity.

### Phase 1 - Classification And Design Sign-off

- Classify every current object: LogicalBronze, StagingException, DomainSilver, EnterpriseReusableSilver, GoldServing, Meta/Audit.
- Produce naming map from v9 names to v10 Pascal Case/process schemas.
- Confirm Bob/Rakesh approval path.

Exit gate:

- Approved mapping for all active objects and known exceptions.

### Phase 2 - Control Plane Extension

- Extend registry with v10 metadata fields.
- Add `access_mode` logic.
- Update lineage builder to distinguish logical vs physical lineage.
- Add source contract and source-target reconciliation gates.
- Make smart skip explicit and tested.

Exit gate:

- Same table can run in DirectShortcut or StageRequired mode from metadata only.

### Phase 3 - Staging/Bronze Refactor

- Reclassify current Warehouse `bronze` as Staging/BronzeMirror only where justified.
- Direct-read candidates read from `Enterprise_Access_Lakehouse`.
- EDW supplement remains explicit `EDWSupplement`; exit to `DirectShortcut` is object-by-object after reconciliation and approval.
- Use `ADR-002` and `15_v10_edw_supplement_exit_strategy.md` as the controlling lifecycle for `_edw` fallback.
- No destructive rename/drop during transition.

Exit gate:

- Direct vs staging decision documented per table.

### Phase 4 - Silver Refactor

- Move Supply Chain-specific transformations into Pascal Case domain/process schemas.
- Promote only approved reusable/conformed Silver entities to EnterpriseData-managed Silver.
- Preserve DAG/wave dependencies using canonical object IDs.

Exit gate:

- Silver dependencies compute correctly after schema rename.

### Phase 5 - Gold Serving Boundary

- Create dedicated SupplyChain Gold Warehouse/serving item.
- Publish physical Gold tables for Direct Lake semantic model.
- Keep compatibility views only where needed and validate fallback behavior.
- Refresh semantic model after Gold publish.

Exit gate:

- Semantic model remains Direct Lake or fallback is explicitly accepted.

### Phase 6 - Parallel Run And Cutover

- Run v9 and v10 side-by-side.
- Compare row counts, duplicate keys, aggregates, DQ results, lineage, semantic measures.
- Require repeated successful runs before switching reports.

Suggested gate:

- 3 successful daily runs.
- 0 critical DQ failures.
- Source-target reconciliation passed for critical facts.
- Gold KPI variance explained and approved.
- Semantic model refresh green.

## 8. Required Tests

- Schema contract validation.
- Source-target row count and key reconciliation.
- Duplicate key checks.
- Null/key completeness checks.
- Freshness checks.
- DirectShortcut vs StageRequired behavior.
- Smart skip due/not-due cases.
- DAG dependency order.
- `_edw` lineage bridge.
- Direct Lake fallback validation.
- Performance baseline comparison.
- TableDictionary completeness.
- Security access test.

## 9. Current Gaps To Close

Use `08_v10_gap_matrix.md` as the active gap register.

Top gaps:

- `GAP-001`: source-target reconciliation not complete.
- `GAP-002`: PowerBI view rule vs strict Direct Lake.
- `GAP-004`: CI/CD/sqlproj section missing.
- `GAP-005`: security model missing.
- `GAP-007`: smart skip is verified for Bronze/Gold, but Silver mixed-frequency behavior still needs a decision.
- `GAP-012`: project-aware Silver DAG is required before real multi-mart scale.
- `GAP-008`: alerting/SLA missing.
- `GAP-010`: source contracts not in active pipeline flow.

## 10. Source References

Local project evidence:

- `Enterprise_SupplyChain_Dev_architect/10_evidence/07_v9_capability_evidence_ledger.md`
- `Enterprise_SupplyChain_Dev_architect/20_proposals/08_v10_gap_matrix.md`
- `Enterprise_SupplyChain_Dev_architect/20_proposals/09_bob_standards_mapping_matrix.md`
- `99_archive/architectures/v9_april/docs/01_03_operations/03_scheduling.md`
- `99_archive/architectures/v9_april/docs/01_03_operations/07_sqlproj_validation.md`
- `99_archive/architectures/v9_april/01_sc_forecast/enterprise/01_roadmap.md`
- `99_archive/architectures/v9_april/01_sc_forecast/docs/03_operations/edw_source_swap.md`
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/15_v10_edw_supplement_exit_strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`

Official docs checked:

- Direct Lake overview: https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-overview
- Medallion architecture in Fabric: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- Fabric Warehouse T-SQL surface area: https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area
- Power BI semantic models in Fabric Warehouse: https://learn.microsoft.com/en-us/fabric/data-warehouse/semantic-models
