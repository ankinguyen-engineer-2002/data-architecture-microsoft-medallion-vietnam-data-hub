# v10 Gap Matrix

Purpose: summarize only the gaps proven by `07_v9_capability_evidence_ledger.md`.

Do not add a gap here unless the corresponding ledger row has evidence.

## 1. Gap Severity

| Severity | Meaning |
|---|---|
| Critical | v10 would lose a core v9 operating capability or break production migration |
| High | v10 preserves the concept but lacks key implementation/validation detail |
| Medium | v10 needs naming, ownership, documentation, or governance clarification |
| Low | documentation or diagram consistency issue |

## 2. Gap Matrix

| Gap ID | Related ledger IDs | Severity | Gap | Why it matters | Proposed v10 amendment | Owner / approval |
|---|---|---|---|---|---|---|
| GAP-001 | V9-007 | High | Source-target reconciliation is mentioned as a v10 non-negotiable, but v9 task tracker marks it as TODO | Avoid claiming v9 already has complete source-target reconciliation; this is important for direct shortcut validation and BronzeMirror removal | Add explicit v10 work item: source vs target row-count/key reconciliation generated from `source_objects` / source contracts | Aric + Bob/Rakesh validation |
| GAP-002 | V9-012 | High | Bob DOCX PowerBI view rule conflicts with strict Direct Lake physical-table serving | Non-materialized SQL views can cause DirectQuery fallback; v10 should not accidentally lose Direct Lake behavior | Keep Gold physical tables as semantic source; document SQL views as compatibility-only | Bob/Rakesh decision |
| GAP-003 | V9-010 | Medium | v9 has `vw_table_dictionary`, but Bob may expect a physical EnterpriseData TableDictionary sync | Local adapter may be enough for review, but enterprise monitoring may require sync/export | Confirm whether adapter view is accepted or whether a scheduled sync to EnterpriseData is required | Bob/Rakesh decision |
| GAP-004 | V9-013 | High | v10 proposal does not yet detail CI/CD/sqlproj impact, while v9 marks CI/CD as blocked but designed | Architecture refactor touches schemas/items and can break deployment validation if not planned | Add v10 CI/CD migration section with three tiers: SQL lint, same-Warehouse sqlproj, and full Enterprise ProjectReference | Aric + DevOps |
| GAP-005 | V9-014 | High | v10 schema/workspace split lacks a verified security model | Bob standards include schema-based security; Fabric Direct Lake may need workspace/item/semantic security instead | Create Fabric-specific security matrix across workspace roles, item permissions, semantic RLS/OLS, SQL endpoint grants, and approval ownership | Bob/Rakesh + workspace admins |
| GAP-006 | V9-015 | Medium | v9 performance baseline/cost monitors exist but are not in pipeline flow; v10 currently says preserve without defining activation | Could preserve tables only but not operational value | Decide whether v10 activates enhanced finalizer, keeps optional, or replaces with Fabric monitoring hooks | Aric |
| GAP-007 | V9-005 | Medium | Smart skip documentation conflicted; live pipeline export verifies due-only filters in `pl_sc_bronze` and `pl_sc_gold`, but Silver frequency handling is not explicit | v10 can preserve current BRZ/REF/GLD behavior, but mixed-frequency Silver would still need a design | Keep current due filter for Bronze/Gold; add explicit Silver schedule decision if non-daily Silver is introduced | Aric |
| GAP-008 | V9-017 | High | Alerting/SLA monitoring is designed but blocked/not active, and v10 does not yet define operational escalation | A cleaner medallion architecture still fails operationally if stale/failed data is not pushed to owners | Add v10 Alerting/SLA plan: IT-dependent automated alert path plus fallback health dashboard/manual runbook | Aric + IT/workspace admins |
| GAP-009 | V9-019 | Medium | v10 proposes Bob-style Pascal Case/process schemas, but exact naming pattern is unresolved (`ENH`/`DW` suffixes vs pure Pascal Case) | Renaming impacts registry keys, lineage names, Direct Lake semantic model/TMDL, and report compatibility | Create naming ADR and object rename mapping before implementation; keep compatibility aliases only where Direct Lake mode allows | Bob/Rakesh decision |
| GAP-010 | V9-020, V9-016 | High | Source contracts exist but are not active in pipeline flow; v10 direct-source mode and EDW exits depend on governed source contracts | Removing BronzeMirror or `_edw` fallback safely requires schema, grain, coverage, completeness, and performance guarantees before running downstream Silver/Gold | Promote `schema_contracts`/source-contract validation into v10 pre-load or pre-publish gates; add source-target reconciliation for staged tables; apply `ADR-002` lifecycle to all `_edw` exits | Aric + Bob/Rakesh validation |
| GAP-011 | V9-018 | Medium | v10 must re-document onboarding after schema/workspace split, otherwise the v9 "view + registry row" productivity model becomes unclear | New table onboarding is one of v9's strongest features; losing it increases maintenance cost and pipeline drift | Add v10 onboarding templates for DirectRead, StagingException, DomainSilver, EnterpriseReusableSilver, and GoldPublish assets | Aric |
| GAP-012 | V9-004, V9-006 | High | Live `pl_sc_silver` / `pl_sc_silver_wave` definitions do not visibly filter wave execution by `project`; `usp_compute_slv_waves` computes all active Silver rows | Current single-project run is fine, but v10 multi-mart architecture needs project-aware Silver DAG execution | Add `project` to `slv_dag_waves_runtime` or compute waves per project; filter Silver wave lookup by project and define cross-mart dependencies | Aric |

## 3. Decision Rules

- If a gap would remove v9 scheduling, DQ, lineage, logging, TableDictionary, Direct Lake refresh, or multi-mart routing, classify at least `High`.
- If a gap is only naming or diagram mismatch, classify `Low` or `Medium`.
- If a gap depends on Fabric live behavior, mark the amendment as `NeedVerify` before implementation.
