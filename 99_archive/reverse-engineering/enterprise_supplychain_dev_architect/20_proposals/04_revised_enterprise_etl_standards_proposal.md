# Revised Proposal: Apply Enterprise ETL SQL DW Standards To Fabric v10

Purpose: apply Enterprise ETL's SQL Server Data Warehouse Standards as an enterprise governance overlay for v10, but adapt the parts that conflict with Fabric Direct Lake, OneLake, Warehouse, and the existing v9 control plane.

## 1. Executive Decision

Recommended direction:

- [Verified] Keep the v10 Hybrid Medallion architecture.
- [Verified] Treat `Enterprise_Access_Lakehouse` shortcuts as logical Bronze.
- [Verified] Keep optional `Staging` / `BronzeMirror` only for exception cases.
- [Verified] Preserve v9 control-plane capabilities: metadata registry, generic load runner, mart routing, smart skip, DAG/waves, DQ, lineage, logging, finalizer, semantic refresh.
- [Verified] Do not rebuild TableDictionary from scratch. v9 already has a concrete `vw_table_dictionary` / Enterprise Dictionary Adapter pattern.
- [Verified] Do not apply Enterprise ETL's "PowerBI should only access views" literally for the Fabric Direct Lake serving path. For strict Direct Lake, Power BI should consume Gold physical tables backed by Delta/OneLake, not non-materialized SQL views.
- [Verified] Do not remove `_edw` fallback as part of the initial v10 build. `ADR-002` keeps all four fallback paths active, with two `ExitCandidate` objects and two `NotReady` objects.

Short version:

```text
Enterprise ETL standards should control naming, governance, security, dictionary metadata, deployment approval, and DQ expectations.
Fabric v10 should keep Direct Lake physical-table serving for Power BI and keep v9 metadata orchestration.
```

## 2. Verification Notes

### 2.1 Power BI Direct Lake vs View Layer

Decision:

- [Verified] If Supply Chain semantic models are intended to stay 100% Direct Lake, Gold serving objects should be physical Gold tables, not non-materialized SQL views.
- [Verified] Direct Lake reads Delta tables in OneLake. Microsoft documentation states Direct Lake is optimized for Delta tables and is ideal for Gold analytics layers.
- [Verified] With Direct Lake on SQL endpoints, SQL views can be discovered, but a semantic model table based on a non-materialized SQL view can fall back to DirectQuery.
- [Verified] Direct Lake on OneLake does not support creating a table based on a non-materialized SQL view.
- [Likely] Therefore, Enterprise ETL's PowerBI-view rule should be interpreted as "stable semantic contract boundary", not necessarily "SQL view object" in Fabric.

Recommended Fabric interpretation:

| Enterprise ETL standard intent | Fabric v10 interpretation |
|---|---|
| Decouple BI from physical warehouse structures | Use certified Gold physical tables and semantic model metadata/renames/measures as the BI contract |
| Avoid reports reading raw/transformation objects | Semantic model reads only Gold; never Staging/Silver directly |
| Isolate security by BI/external model | Use workspace/item/security model and optional security-specific Gold schemas; use SQL views only if DirectQuery/import/fallback is acceptable |
| Allow view shim when shape changes | Keep compatibility views only for transition or legacy tools, not as the default Direct Lake path |

When to use views anyway:

- [Likely] Legacy report migration where column names must be shimmed quickly.
- [Likely] Import or DirectQuery models where a SQL view contract is acceptable.
- [Likely] Temporary compatibility during schema rename cutover.
- [Need-verify] If a SQL view is selected in the semantic model, confirm whether the table remains Direct Lake or falls back before production.

Alternative if a view-like abstraction is still required:

- [Need-verify] Use Materialized Lake Views only after a POC. The docs say they persist results as Delta files and can be queried like Delta tables, but the feature has region and current limitation considerations. It should not replace the v9 Warehouse-native framework unless validated with CI/CD, governance, and operational support.

### 2.2 TableDictionary Is Already Part Of v9

Decision:

- [Verified] v9 already has an Enterprise Dictionary Adapter through `meta.vw_table_dictionary`.
- [Verified] v9 already extended `sp_registry` toward the enterprise TableDictionary model: primary key, date key, date range, source platform, update method/load type, refresh/schedule metadata, source object mapping, and run status.
- [Verified] v9 already implements CST alignment for US/Enterprise consumption through `meta.ufn_utc_to_cst`, CST log columns, and `vw_table_dictionary`.

So the revised v10 proposal is:

```text
Do not create a separate TableDictionary system unless Enterprise ETL/Rakesh require a physical table.
Promote the existing v9 adapter into the official v10 Enterprise Dictionary Adapter.
Extend only missing attributes needed by Enterprise ETL standards.
```

Suggested v10 mapping:

| Enterprise ETL TableDictionary field group | Existing v9 source | v10 action |
|---|---|---|
| Object identity: server/db/schema/table/object type | `sp_registry.target_schema`, `sp_registry.target_table`, physical item metadata | Extend with workspace/item fields |
| Primary key / alternate key | `sp_registry.primary_key`, planned `alternate_key` | Keep and require for duplicate checks |
| Refresh rate / job / package | `frequency`, `cron_expression`, `next_run_time`, `project`, pipeline names | Keep; map to `tpkRefreshRate`, `tpkJobName`, `tpkETLTool` |
| Source metadata | `source_objects`, view definitions, source contracts | Extend with `source_platform`, source workspace/item |
| Update method | `load_type` | Map to Enterprise ETL update method naming where useful |
| Row count / last modified / audit | `sp_run_history`, `pipeline_run_log`, `last_load_date`, `rows_loaded` | Keep; expose in dictionary adapter |
| PII / valid key values | not fully first-class today | Add metadata columns only when needed |
| Security mapping | not fully first-class today | Add `Meta.SecurityPolicy` / dictionary-security adapter if required |

## 3. What To Apply From Enterprise ETL Standards

### 3.1 Apply Directly

These should become v10 standards:

- [Verified] No business/user objects in `dbo`.
- [Verified] Bronze/source-aligned objects mimic source structures.
- [Verified] Significant enhancements to source data belong in Silver/ENH, not Bronze.
- [Verified] Use logical schemas grouped by business/process/metric area, not generic `bronze/silver/gold` schemas long term.
- [Verified] Silver and Gold naming should follow Pascal Case per Enterprise ETL's feedback.
- [Verified] Use explicit column lists; avoid `SELECT *` except with documented approval.
- [Verified] Every managed table must have primary key metadata for duplicate checks, even if Fabric constraints are informational/not enforced.
- [Verified] End-user/BI consumption should only read curated Gold/serving objects, not raw/staging/work tables.
- [Verified] Technical design approval by Rakesh or assigned approver before development.
- [Verified] TableDictionary metadata must be populated/exposed for all managed v10 objects.

### 3.2 Apply With Fabric Adaptation

| Enterprise ETL standard | Why not literal in Fabric v10 | v10 adaptation |
|---|---|---|
| PowerBI only reads SQL views | Non-materialized SQL views can break strict Direct Lake by causing DirectQuery fallback | Power BI reads Gold physical tables; optional views only for compatibility/DirectQuery/import |
| CCIX/CIX/HEAP standards | Fabric Warehouse T-SQL/storage behavior differs from classic SQL Server / ADW | Use Fabric-supported statistics/performance monitoring and Gold table design gates |
| HASH/REPLICATE distribution | Synapse dedicated SQL pool concept, not a direct Fabric Warehouse design knob | Replace with Fabric table/query/performance baseline validation |
| PolyBase external tables | Fabric uses OneLake, shortcuts, Lakehouse SQL endpoint, Warehouse, and Delta | Use shortcuts/Delta/source contracts instead of PolyBase external-table pattern |
| Temporary source fallback | Source-like data should not be maintained forever, but live v9 still needs `_edw` supplement paths | Keep `EDWSupplement` in Staging initially and retire object-by-object under `ADR-002` |
| XBK backup schemas | Valid rollback intent, but implementation should not create unnecessary dead objects | Use non-destructive side-by-side versioning, CTAS/copy only when approved, and archive policy |
| SQL Agent/job monitoring | Fabric pipelines and REST refresh model differ | Keep v9 pipeline logging, Fabric pipeline history, and alerting hooks |

### 3.3 Defer Or POC First

- [Need-verify] Materialized Lake Views as a future Gold abstraction: promising for persisted Delta outputs, but requires POC because it is newer and has current limitations.
- [Need-verify] Moving control-plane metadata to EnterpriseData: do not move until v10 is stable; keep local `Meta` for domain autonomy first.
- [Need-verify] SQL-based RLS/CLS with Direct Lake: confirm selected Direct Lake mode and fallback behavior before designing security only at SQL endpoint level.

## 4. Revised Physical Architecture

### 4.1 SupplyChain Dev Workspace

```text
SupplyChain Dev workspace
├── Enterprise_Access_Lakehouse
│   └── shortcuts to Enterprise_Data source products
│       Role: logical Bronze, source-aligned, no business enhancement
│
├── SupplyChain_Processing_Warehouse
│   ├── Meta
│   │   ├── sp_registry
│   │   ├── vw_table_dictionary
│   │   ├── source_contracts / schema_contracts
│   │   ├── dq_rules / dq_results
│   │   ├── sp_lineage
│   │   └── sp_run_history / pipeline_run_log
│   ├── Audit
│   ├── Staging_WRK or BronzeMirror_WRK
│   │   ├── exception-only persisted source snapshots
│   │   └── EDWSupplement objects governed by ADR-002
│   ├── ForecastHistory_ENH or ForecastHistory
│   ├── InventoryHistory_ENH or InventoryHistory
│   ├── SalesHistory_ENH or SalesHistory
│   └── ReferenceMaster_ENH or ReferenceMaster
│
├── SupplyChain_Gold_Warehouse
│   ├── ForecastAccuracy_DW or ForecastAccuracy
│   │   ├── FactForecastAccuracy...
│   │   └── Dim...
│   ├── InventoryPerformance_DW or InventoryPerformance
│   └── ServiceLevel_DW or ServiceLevel
│
└── SupplyChain_Semantic_Model
    └── Direct Lake tables from SupplyChain_Gold_Warehouse physical tables
```

Naming note:

- [Need-verify] Enterprise ETL's email says Pascal Case on Silver and Gold. The DOCX uses suffixes such as `ENH`, `DW`, `WRK`. Before implementation, confirm whether the target should be `ForecastHistory_ENH` / `ForecastAccuracy_DW` or pure PascalCase schemas such as `ForecastHistory` / `ForecastAccuracy`.

### 4.2 Enterprise_Data Workspace

```text
Enterprise_Data workspace
├── Source_Data / source-system-aligned objects
├── existing SupplyChain_Warehouse or enterprise Silver warehouse
│   └── only cross-domain / reusable / conformed Silver objects
└── governed enterprise contracts, approvals, shared dictionary standards
```

Rule:

- [Verified] If a Silver object is enterprise reusable, it belongs under EnterpriseData ownership.
- [Likely] If a Silver object is Supply Chain forecasting/inventory/operational logic, it should remain domain-owned in SupplyChain Dev until explicitly promoted.

## 5. Revised Gold And Power BI Rule

New v10 rule:

```text
Power BI Direct Lake should connect to Gold physical tables, not non-materialized SQL views.
Gold physical tables are the BI serving contract.
The semantic model owns business display names, measures, relationships, perspectives, and report-facing semantics.
```

Optional `PowerBI` schema:

- Do not create by default for Direct Lake.
- Create only if:
  - legacy reports require view-based compatibility,
  - DirectQuery/import model is intentionally used,
  - security requires a temporary SQL view layer,
  - external consumers cannot consume the semantic model and need SQL access.

Validation gate:

- [Verified] A Direct Lake semantic model refresh/framing step should remain after Gold publish.
- [Need-verify] Confirm no semantic model table falls back to DirectQuery before cutover.
- [Need-verify] Confirm row groups, file counts, model memory guardrails, and Direct Lake performance after Gold table publish.

## 6. Revised TableDictionary Rule

New v10 rule:

```text
TableDictionary compatibility is a required v10 control-plane output.
Implementation starts from v9 vw_table_dictionary and sp_registry, not from a brand-new table.
Do not create one oversized 63/69-column physical base table.
Use normalized metadata tables plus a compatibility view adapter.
```

Minimum required outputs:

- Workspace name / item name / schema / table.
- Canonical layer: LogicalBronze, Staging, Silver, EnterpriseSilver, Gold.
- Physical object type: Lakehouse shortcut, Warehouse table, view, MLV, semantic model table.
- Primary key metadata.
- Refresh rate / schedule / cron / next run.
- ETL tool / pipeline / load type.
- Source object mapping.
- Last modified / last batch start / row count.
- DQ status and invalid count when available.
- Owner / approval status.
- PII/security classification where required.

Recommended implementation:

1. Keep `Meta.vw_table_dictionary` as the external-facing dictionary view.
2. Extend `sp_registry` with missing governance fields only if they are stable and required.
3. Add supplemental metadata tables for slow-changing governance data if `sp_registry` becomes too wide.
4. Do not duplicate run logs inside TableDictionary; expose them through view joins to `sp_run_history` / `pipeline_run_log`.

## 7. Revised Work Estimate

This estimate corrects the previous assumption that TableDictionary was missing.

| Area | Estimate | Notes |
|---|---:|---|
| Keep unchanged | 35-40% | v9 control plane, generic runner pattern, mart routing, smart skip, DAG, DQ, lineage, logging, finalizer |
| Modify/refactor | 45-50% | access mode, schema naming, logical Bronze, direct/stage decision, TableDictionary adapter extension, Direct Lake Gold validation |
| Build new | 10-15% | dedicated Gold item, Enterprise ETL standards acceptance checklist, optional security metadata, compatibility views only if needed |

Conclusion:

- [Likely] This remains a significant architecture refactor.
- [Verified] It is not a rewrite of v9.
- [Verified] The strongest v9 capabilities remain reusable if metadata interfaces are extended instead of replaced.

## 8. Acceptance Checklist Before Applying Enterprise ETL Standards

Before development:

- [ ] Confirm Silver/Gold schema naming convention: `ForecastHistory_ENH` vs `ForecastHistory`.
- [ ] Confirm which Silver entities move to EnterpriseData-owned Silver.
- [ ] Confirm Direct Lake mode: Direct Lake on SQL endpoint vs Direct Lake on OneLake.
- [ ] Confirm whether any semantic model table currently uses SQL views and whether it falls back to DirectQuery.
- [ ] Confirm `vw_table_dictionary` output matches Enterprise ETL-required fields.
- [ ] Confirm primary key metadata exists for every managed physical table.
- [ ] Confirm security requirement: workspace/item/semantic security vs SQL endpoint RLS/CLS.
- [ ] Confirm rollback/side-by-side strategy without destructive drops.
- [ ] Confirm `_edw` exit criteria and fallback retention window per `ADR-002`.

Before cutover:

- [ ] 3 successful daily runs.
- [ ] No critical DQ failures.
- [ ] Row count, key count, and KPI parity accepted.
- [ ] Direct Lake semantic model refresh/framing succeeds.
- [ ] No unexpected DirectQuery fallback for Gold tables.
- [ ] Lineage complete from Enterprise source to Gold.
- [ ] TableDictionary adapter complete for all managed objects.
- [ ] EDW supplement `ExitCandidate` objects pass dual-read validation or remain staged with documented reason.
- [ ] Enterprise ETL/Rakesh or assigned approver signs off technical design.

## 9. Sources

Official Microsoft docs:

- Direct Lake overview: https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-overview
- Power BI semantic models in Fabric Warehouse: https://learn.microsoft.com/en-us/fabric/data-warehouse/semantic-models
- Lakehouse overview: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-overview
- Materialized Lake Views overview: https://learn.microsoft.com/en-us/fabric/data-engineering/materialized-lake-views/overview-materialized-lake-view
- Materialized Lake Views refresh: https://learn.microsoft.com/en-us/fabric/data-engineering/materialized-lake-views/refresh-materialized-lake-view

Local evidence:

- Enterprise ETL standards DOCX: `Enterprise_SupplyChain_Dev_architect/SQL Server Data Warehouse Standards.docx` (local-only evidence; intentionally ignored from Git unless sharing is approved)
- v9 generic SP migration: `99_archive/architectures/v9_april/docs/01_03_operations/05_generic_sp_migration.md`
- v9 timezone / TableDictionary mapping: `99_archive/architectures/v9_april/docs/01_03_operations/06_timezone_sync.md`
- v9 setup: `99_archive/architectures/v9_april/01_sc_forecast/docs/02_setup.md`
- v10 feature parity: `Enterprise_SupplyChain_Dev_architect/00_overview/03_v9_feature_parity_checklist.md`
