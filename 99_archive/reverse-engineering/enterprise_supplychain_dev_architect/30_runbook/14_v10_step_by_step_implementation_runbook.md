# v10 Bob/Rakesh-Aligned Step-by-Step Implementation Runbook

> **For agentic workers:** REQUIRED SUB-SKILL: use a task-by-task execution flow with review checkpoints. Do not mutate Fabric production assets, delete objects, rename live objects, or cut over reports without explicit approval.

**Goal:** Build v10 as a Bob/Rakesh-aligned Hybrid Medallion implementation while preserving the v9 control plane and avoiding destructive changes.

**Architecture:** v10 keeps `Enterprise_Access_Lakehouse` / current `Enterprise_Lakehouse` shortcuts as the logical Bronze layer, creates exception-only `Staging`, moves Supply Chain transformations into Pascal Case process schemas, publishes physical Gold tables into a dedicated Gold serving Warehouse, and keeps the v9 metadata-driven framework as the control plane.

**Tech Stack:** Microsoft Fabric, OneLake shortcuts, Lakehouse SQL analytics endpoint, Fabric Warehouse T-SQL, Fabric Data Pipelines, Power BI Direct Lake semantic model, v9 metadata framework.

---

## 1. Non-Negotiable Execution Rules

- [Verified] Build v10 **side-by-side**, not in-place.
- [Verified] Do not drop, truncate, delete, force-rename, bulk-overwrite, or recreate v9 objects during implementation.
- [Verified] Keep v9 live until v10 passes repeated parity checks and receives Bob/Rakesh or assigned technical approval.
- [Verified] Treat the current Warehouse `bronze` schema as legacy v9 implementation, not canonical v10 Bronze.
- [Verified] Treat shortcut-backed Enterprise Lakehouse data as logical Bronze when source contract, schema, grain, SLA, and performance are acceptable.
- [Verified] Keep `Staging` / `BronzeMirror` capability for exception cases: EDW supplement, unstable source, incomplete source, snapshot requirement, replay/debug need, or direct-read performance risk.
- [Verified] Preserve v9 control-plane features: metadata registry, generic SQL runner, mart routing, schedule gate, smart skip, Silver DAG waves, DQ engine, lineage, logging, finalizer, TableDictionary adapter, semantic refresh discipline.
- [Need-verify] Do not create or move EnterpriseData Silver physical objects until Bob/Rakesh decide which entities are enterprise reusable.
- [Need-verify] Do not finalize naming suffixes (`ENH`, `DW`, `WRK`) until Bob/Rakesh choose between pure Pascal Case and DOCX suffix convention.

## 2. Source Evidence Used

### Microsoft Fabric official documentation

- [Verified] Fabric recommends medallion architecture and says layers should remain separated for governance; Bronze stores raw/source-aligned data, Silver enriches/cleans, Gold curates for reporting.
  Source: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- [Verified] Fabric medallion guidance says if the source data is already in OneLake/ADLS/S3/Google, use shortcuts in Bronze instead of copying data where possible.
  Source: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- [Verified] OneLake shortcuts are logical pointers that can reduce edge copies and staging latency, but they can break if target paths are renamed/moved/deleted.
  Source: https://learn.microsoft.com/en-us/fabric/onelake/onelake-shortcuts
- [Verified] Lakehouse SQL analytics endpoint is read-only for Delta tables; insert/update/delete require Warehouse or Spark/lakehouse write path.
  Source: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint
- [Verified] Fabric Warehouse supports T-SQL tables, views, stored procedures, functions, permissions, security roles, DML, and MERGE; SQL analytics endpoint does not support table write operations.
  Source: https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area
- [Verified] Direct Lake is ideal for Gold analytics layers over Delta-backed Fabric data. Non-materialized SQL views can force fallback or be unsupported depending on Direct Lake mode.
  Source: https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-overview
- [Verified] Power BI semantic models are the analytical contract for facts/dimensions/metrics and Direct Lake avoids importing data into the model.
  Source: https://learn.microsoft.com/en-us/fabric/data-warehouse/semantic-models

### Local project evidence

- [Verified] v10 architecture plan: `Enterprise_SupplyChain_Dev_architect/00_overview/01_super_plan_medallion_refactor.md`
- [Verified] v9/v10 feature parity: `Enterprise_SupplyChain_Dev_architect/00_overview/03_v9_feature_parity_checklist.md`
- [Verified] Bob standards Fabric adaptation: `Enterprise_SupplyChain_Dev_architect/20_proposals/04_revised_bob_standards_proposal.md`
- [Verified] v9 capability evidence ledger: `Enterprise_SupplyChain_Dev_architect/10_evidence/07_v9_capability_evidence_ledger.md`
- [Verified] v10 gap matrix: `Enterprise_SupplyChain_Dev_architect/20_proposals/08_v10_gap_matrix.md`
- [Verified] Bob standards mapping matrix: `Enterprise_SupplyChain_Dev_architect/20_proposals/09_bob_standards_mapping_matrix.md`
- [Verified] final v10 amendment plan: `Enterprise_SupplyChain_Dev_architect/20_proposals/10_final_v10_amendment_plan.md`
- [Verified] implementation readiness pack: `Enterprise_SupplyChain_Dev_architect/30_runbook/11_v10_implementation_readiness_pack.md`
- [Verified] object classification mapping: `Enterprise_SupplyChain_Dev_architect/20_proposals/12_v10_object_classification_mapping.md`
- [Verified] post-readiness build blueprint: `Enterprise_SupplyChain_Dev_architect/30_runbook/13_v10_build_blueprint_after_readiness.md`
- [Verified] EDW supplement decision: `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- [Verified] v10 readiness scorecard and v9 cleanup candidate list: `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`
- [Verified] live readiness export: `Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/` (local-only raw evidence; intentionally ignored from Git)
- [Verified] Bob standard DOCX: `Enterprise_SupplyChain_Dev_architect/SQL Server Data Warehouse Standards.docx` (local-only evidence; intentionally ignored from Git unless sharing is approved)

## 3. Target Build Picture

```text
Enterprise_Data workspace
  -> upstream source products
  -> Enterprise reusable/conformed Silver only after Bob/Rakesh approval
  -> existing EnterpriseData SupplyChain_Warehouse for approved Silver patterns

SupplyChain Dev / approved Enterprise_SupplyChain workspace
  -> Enterprise_Access_Lakehouse
       Logical Bronze through OneLake shortcuts
       Current physical item may be Enterprise_Lakehouse; do not rename until approved

  -> SupplyChain_Processing_Warehouse
       Meta / control plane
       Staging for exceptions only
       ReferenceMaster for domain reference objects not owned by EnterpriseData
       SalesHistory for Supply Chain domain Silver
       ForecastHistory for Supply Chain domain Silver
       OpenOrderHistory for Supply Chain domain Silver

  -> SupplyChain_Gold_Warehouse
       ForecastAccuracy physical Gold tables

  -> SupplyChain semantic model
       Direct Lake over physical Gold tables
```

## 4. What To Create, Change, Keep, Defer, And Eventually Remove

### 4.1 Create now in v10 side-by-side

- Create a v10 implementation branch/folder/package for deployment scripts and run evidence.
- Create or designate `SupplyChain_Processing_Warehouse` as the v10 processing Warehouse.
- Create or designate `SupplyChain_Gold_Warehouse` as the v10 Gold serving Warehouse.
- Create v10 `Meta` schema and companion control-plane tables/views without altering live v9 tables first.
- Create v10 `Staging` schema for EDW supplement and exception-only persisted mirrors.
- Create v10 Pascal Case domain schemas: `SalesHistory`, `ForecastHistory`, `OpenOrderHistory`, `ReferenceMaster`.
- Create v10 Gold schema: `ForecastAccuracy`.
- Create v10 copy pipelines instead of editing v9 pipelines directly.
- Create validation result tables for source contracts, reconciliation, DQ gate results, and Direct Lake validation.
- Create a Bob/Rakesh approval evidence pack from metadata, object classification, naming, security, DQ mode, and cutover criteria.

### 4.2 Change during implementation

- Change metadata semantics from `layer = BRZ/SLV/GLD` only to `canonical_layer + physical_location + access_mode`.
- Change Bronze handling from mandatory local copy to direct shortcut read by default, with staging only by exception.
- Change generic `silver` schema to process/metric schemas.
- Change Gold serving from same Warehouse schema to dedicated Gold Warehouse physical tables.
- Change Silver DAG runtime to be project-aware before multi-mart expansion.
- Change DQ from deactivated/standalone to explicit gate mode: `Off`, `WarnOnly`, or `CriticalStops`.
- Change source contracts from passive metadata to pre-load/pre-publish gate.
- Change TableDictionary from v9 adapter only to v10 Enterprise Dictionary Adapter with workspace/item/access mode fields.

### 4.3 Keep unchanged initially

- Keep current v9 Warehouse and pipelines live.
- Keep current v9 `meta.sp_registry` as the baseline source of truth until v10 compatibility views are validated.
- Keep `meta.usp_generic_load` concept and load pattern routing.
- Keep v9 smart-skip logic for Bronze/REF and Gold.
- Keep EDW supplement staging for the four known EDW-backed assets until source SLA/coverage/grain/performance is approved.
- Keep the four Dataflows that load `SupplyChain_Lakehouse` for v8/v9; v10 maps them as upstream `LegacyDataflowBridge` feeds, not cleanup targets.
- Keep semantic model refresh/framing discipline after Gold publish.
- Keep compatibility views only where they are needed for transition or non-Direct-Lake consumers.

### 4.4 Defer until Bob/Rakesh or assigned approver signs off

- Physical move of reusable Silver/reference assets into EnterpriseData.
- Final schema suffix naming: pure Pascal Case vs `ENH` / `DW` / `WRK`.
- Physical TableDictionary sync/export into EnterpriseData if Bob requires more than a view adapter.
- Security grants/RLS/OLS/SQL endpoint permission changes.
- Production cutover of semantic model/report dependencies.
- Deactivation of v9 schedules.
- Rename of existing `Enterprise_Lakehouse` to `Enterprise_Access_Lakehouse`.

### 4.5 Do not delete during v10 build

- Do not delete v9 `bronze`, `silver`, `gold`, or `meta` schemas.
- Do not delete v9 tables, views, stored procedures, functions, pipelines, semantic model, or lineage exports.
- Do not delete EDW supplement tables.
- Do not delete any Dataflow during v10 cleanup/build, especially the four feeds that populate `SupplyChain_Lakehouse` for v8.
- Do not delete old semantic model/report dependencies.
- Do not delete compatibility views until after cutover and consumer sign-off.

### 4.6 Eventually remove only after cutover approval

- Disable old v9 schedules only after v10 has accepted parity.
- Archive old v9 pipelines only after rollback window closes.
- Decommission obsolete v9 Bronze mirrors only table-by-table after direct-read validation.
- Remove compatibility views only after reports/semantic model dependencies are proven unused.
- Archive old schema documentation after the new onboarding runbook replaces it.

## 5. Implementation Phases

### Phase -1: Freeze Evidence And Working Branch

**Purpose:** lock current state so v10 changes can be compared to v9.

**Files / artifacts:**

- Read: `Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/`
- Read: `Enterprise_SupplyChain_Dev_architect/20_proposals/12_v10_object_classification_mapping.md`
- Create: `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/`
- Create: `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/baseline_manifest.md`

**Steps:**

- [ ] Step 1: Create a build run folder under `Enterprise_SupplyChain_Dev_architect/build_runs/`.
- [ ] Step 2: Copy or reference the existing readiness export path in `baseline_manifest.md`.
- [ ] Step 3: Record the v9 live baseline counts: 28 registry assets, 52 lineage edges, 54 DQ rules, 7 decoded Supply Chain pipeline definitions.
- [ ] Step 4: Record that current `pl_sc_master` does not invoke DQ gates.
- [ ] Step 5: Record that `pl_sc_bronze` and `pl_sc_gold` contain due-only smart-skip filters.
- [ ] Step 6: Record that live Silver DAG is not project-filtered.
- [ ] Step 7: Do not run any DDL/DML in this phase.

**Exit gate:**

- Baseline manifest exists.
- No live Fabric objects have been changed.

### Phase 0: Bob/Rakesh Approval Pack Before DDL

**Purpose:** present enough design detail to get approval before creating physical objects that could conflict with standards.

**Files / artifacts:**

- Create: `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/approval_pack.md`
- Reference: `Enterprise_SupplyChain_Dev_architect/20_proposals/09_bob_standards_mapping_matrix.md`
- Reference: `Enterprise_SupplyChain_Dev_architect/20_proposals/12_v10_object_classification_mapping.md`

**Steps:**

- [ ] Step 1: State that Bronze is logical/source-aligned through shortcuts.
- [ ] Step 2: State that local `Staging` replaces canonical Warehouse `bronze` only for exceptions.
- [ ] Step 3: State that significant source enhancements move to Silver/process schemas.
- [ ] Step 4: State that enterprise-reusable Silver moves to EnterpriseData only after owner approval.
- [ ] Step 5: State that domain-specific Supply Chain Silver remains in SupplyChain processing Warehouse.
- [ ] Step 6: State that Gold physical tables are the default Power BI Direct Lake serving contract.
- [ ] Step 7: State that SQL views are compatibility-only unless fallback/DirectQuery/import is accepted.
- [ ] Step 8: Ask for naming decision: pure Pascal Case (`ForecastHistory`) or suffix convention (`ForecastHistory_ENH`).
- [ ] Step 9: Ask for TableDictionary decision: v10 adapter view only or physical sync/export to EnterpriseData.
- [ ] Step 10: Ask for security owner: workspace roles, item permissions, SQL endpoint grants, semantic RLS/OLS.
- [ ] Step 11: Ask for EDW supplement exit criteria: SLA, grain, completeness, row parity, performance.
- [ ] Step 12: Attach `ADR-002` and the readiness scorecard so `_edw` fallback is reviewed as object-level lifecycle, not a blanket Bronze duplication exception.

**Exit gate:**

- Bob/Rakesh or assigned approver confirms the target naming and ownership rules.
- If approval is delayed, continue only with local drafts and non-destructive v10 side-by-side objects.

### Phase 1: Create Or Designate v10 Physical Items

**Purpose:** create safe side-by-side Fabric items without disturbing v9.

**Fabric items:**

- Create or designate: `SupplyChain_Processing_Warehouse`
- Create or designate: `SupplyChain_Gold_Warehouse`
- Designate logical role: `Enterprise_Access_Lakehouse`
- Keep current item if applicable: `Enterprise_Lakehouse`

**Steps:**

- [ ] Step 1: List current workspace items from the SupplyChain Dev workspace.
- [ ] Step 2: Confirm whether a v10 processing Warehouse already exists.
- [ ] Step 3: If it does not exist, create `SupplyChain_Processing_Warehouse` as a new Warehouse.
- [ ] Step 4: Confirm whether a v10 Gold Warehouse already exists.
- [ ] Step 5: If it does not exist, create `SupplyChain_Gold_Warehouse` as a new Warehouse.
- [ ] Step 6: Do not rename `Enterprise_Lakehouse` yet. Register it as logical role `Enterprise_Access_Lakehouse` in metadata.
- [ ] Step 7: Record Warehouse IDs, SQL endpoints, and workspace IDs in the build run folder.
- [ ] Step 8: Do not create EnterpriseData Silver objects in this phase unless approval exists.

**Exit gate:**

- v10 items are created or designated.
- v9 items remain unchanged.
- New item IDs are recorded.

### Phase 2: Create v10 Metadata Compatibility Layer

**Purpose:** preserve v9 framework behavior while adding Bob-aligned governance fields.

**Schemas:**

- Create in `SupplyChain_Processing_Warehouse`: `Meta`

**Tables / views to create:**

- `Meta.AssetRegistryV10`
- `Meta.AssetAccessPolicy`
- `Meta.ObjectClassification`
- `Meta.SourceContractRun`
- `Meta.ReconciliationRule`
- `Meta.ReconciliationResult`
- `Meta.DQGateRun`
- `Meta.LineageEdge`
- `Meta.ApprovalLog`
- `Meta.DeploymentChecklist`
- `Meta.SecurityPolicy`
- `Meta.SemanticModelContract`
- `Meta.vw_RegistryCompat`
- `Meta.vw_TableDictionary`

**Minimum metadata fields:**

```text
asset_id
legacy_target_schema
legacy_target_table
canonical_layer
physical_workspace
physical_item
physical_schema
physical_object
access_mode
domain_group
project
frequency
cron_expression
next_run_time
load_type
primary_key
watermark_column
depends_on
source_objects
is_enterprise_reusable
staging_reason
source_contract_status
approval_status
owner_name
is_active
```

**Allowed `canonical_layer` values:**

```text
LogicalBronze
Staging
ReferenceMaster
DomainSilver
EnterpriseSilver
Gold
Meta
```

**Allowed `access_mode` values:**

```text
DirectShortcut
StageRequired
EDWSupplement
ManualSeed
EnterpriseSilver
WarehouseTransform
GoldPublish
```

**Steps:**

- [ ] Step 1: Create `Meta` schema in the v10 processing Warehouse.
- [ ] Step 2: Create the metadata tables listed above.
- [ ] Step 3: Load `Meta.ObjectClassification` from `12_v10_object_classification_mapping.md`.
- [ ] Step 4: Load `Meta.AssetRegistryV10` from the v9 readiness export, not by querying mutable live objects during initial design.
- [ ] Step 5: Set direct-read Bronze candidates to `canonical_layer = LogicalBronze` and `access_mode = DirectShortcut`.
- [ ] Step 6: Set all four EDW supplement objects to `canonical_layer = Staging` and `access_mode = EDWSupplement`.
- [ ] Step 6a: Mark `brz_saleshistory_afi__invoicedetail` and `ref_product` as `edw_exit_status = ExitCandidate`.
- [ ] Step 6b: Mark `brz_saleshistory_afi__invoiceheader` and `brz_supplychain_enh_1__demandforecastsnapshotdaily` as `edw_exit_status = NotReady`.
- [ ] Step 7: Set domain Silver objects to `canonical_layer = DomainSilver` and `access_mode = WarehouseTransform`.
- [ ] Step 8: Set Gold objects to `canonical_layer = Gold` and `access_mode = GoldPublish`.
- [ ] Step 9: Mark reusable/reference candidates as `approval_status = NeedsOwnerDecision`.
- [ ] Step 10: Create `Meta.vw_RegistryCompat` so existing v9-style logic can still read target schema/table/load type/project/frequency.
- [ ] Step 11: Create `Meta.vw_TableDictionary` as the v10 Enterprise Dictionary Adapter.
- [ ] Step 12: Validate that the v10 registry has exactly the expected 28 initial assets before adding new ones.

**Exit gate:**

- v10 metadata can represent every v9 registry object.
- Direct vs staging behavior is metadata-driven, not hardcoded in pipeline JSON.

### Phase 3: Build Access Decision Engine

**Purpose:** decide direct vs staging per asset using metadata, source contracts, and approval status.

**Create:**

- Stored procedure/function draft: `Meta.usp_ResolveAccessMode`
- View: `Meta.vw_AccessDecision`

**Decision logic:**

```text
If access_mode = EDWSupplement
and edw_exit_status = ExitCandidate
and reconciliation_status != Passed
  -> use Staging and run dual-read validation

Else if access_mode = EDWSupplement
  -> use Staging

Else if source_contract_status != Stable
  -> use Staging or block based on gate mode

Else if staging_reason is not null
  -> use Staging

Else if canonical_layer = LogicalBronze and access_mode = DirectShortcut
  -> read from Enterprise_Access_Lakehouse shortcut

Else if canonical_layer in DomainSilver, Gold
  -> use Warehouse transform/publish path
```

**Steps:**

- [ ] Step 1: Create the access decision view from `Meta.AssetRegistryV10`.
- [ ] Step 2: Add a `decision_reason` output column.
- [ ] Step 3: Add `resolved_source_reference` output column.
- [ ] Step 4: Add `resolved_target_reference` output column.
- [ ] Step 5: Test the four direct CODIS source objects resolve as `DirectShortcut`.
- [ ] Step 6: Test all four EDW-backed objects resolve as `EDWSupplement` for initial build.
- [ ] Step 7: Test `brz_saleshistory_afi__invoicedetail` and `ref_product` expose `edw_exit_status = ExitCandidate` but do not cut over without validation.
- [ ] Step 8: Test `brz_saleshistory_afi__invoiceheader` and `brz_supplychain_enh_1__demandforecastsnapshotdaily` expose `edw_exit_status = NotReady`.
- [ ] Step 9: Test `ref_product` also remains owner-decision gated until Bob/Rakesh approval.
- [ ] Step 10: Test all eight Silver objects resolve as `WarehouseTransform`.
- [ ] Step 11: Test both Gold objects resolve as `GoldPublish`.

**Exit gate:**

- Every active asset returns one and only one execution path.
- No direct-source asset is allowed when source contract status is unstable.

### Phase 4: Create Staging Exception Layer

**Purpose:** keep operational safety without keeping duplicate Bronze as the default architecture.

**Create:**

- Schema: `Staging`
- Optional schema if Bob suffix standard is selected: `Staging_WRK`

**Initial staged objects:**

- `brz_saleshistory_afi__invoicedetail`
- `brz_saleshistory_afi__invoiceheader`
- `brz_supplychain_enh_1__demandforecastsnapshotdaily`
- `ref_product`

**Steps:**

- [ ] Step 1: Create `Staging` schema in `SupplyChain_Processing_Warehouse`.
- [ ] Step 2: Create only EDW supplement / exception tables in `Staging`.
- [ ] Step 3: Do not recreate all v9 Bronze tables in `Staging`.
- [ ] Step 4: Add source contract checks before loading each staged table.
- [ ] Step 5: Add source-target reconciliation after loading each staged table.
- [ ] Step 6: Add lineage edge type `PhysicalStaging`.
- [ ] Step 7: Record staging reason for each object in `Meta.AssetRegistryV10`.
- [ ] Step 8: Keep rollback path back to v9 source for each staged object.

**Exit gate:**

- Staging contains exceptions only.
- Each staged object has a documented reason and exit criteria.

### Phase 5: Build Logical Bronze Direct-Read Path

**Purpose:** answer Bob's Bronze duplication concern by using shortcuts directly when governed and stable.

**Direct-read candidates:**

- `brz_wholesale_codis_afi__codatan`
- `brz_wholesale_codis_afi__comast`
- `brz_wholesale_codis_afi__extord`
- `brz_wholesale_codis_afi__extorit`

**Steps:**

- [ ] Step 1: Confirm each source shortcut exists in the Enterprise Lakehouse Tables section.
- [ ] Step 2: Confirm each shortcut is visible through the Lakehouse SQL analytics endpoint.
- [ ] Step 3: Confirm each direct source can be queried read-only.
- [ ] Step 4: Confirm source schema matches `Meta.schema_contracts` / v10 source contract metadata.
- [ ] Step 5: Confirm row counts and grain against v9 operational baseline.
- [ ] Step 6: Confirm direct query runtime is acceptable for downstream Silver transformations.
- [ ] Step 7: If direct query is acceptable, keep `access_mode = DirectShortcut`.
- [ ] Step 8: If direct query is not acceptable, set `access_mode = StageRequired` with explicit `staging_reason`.
- [ ] Step 9: Do not materialize a local copy just because it existed in v9.

**Exit gate:**

- Each logical Bronze candidate is classified as direct or staged with evidence.

### Phase 6: Build Domain Silver Schemas

**Purpose:** align with Bob's schema guidance: schemas group related tables/views/procs by business/process/metric area, not generic medallion layer names.

**Default schema names unless Bob/Rakesh select suffixes:**

- `SalesHistory`
- `ForecastHistory`
- `OpenOrderHistory`
- `ReferenceMaster`

**Object mapping:**

- `slv_invoice_detail_line_level` -> `SalesHistory.InvoiceDetailLineLevel`
- `slv_invoice_weekly` -> `SalesHistory.InvoiceWeekly`
- `slv_actual_demand_monthly` -> `SalesHistory.ActualDemandMonthly`
- `slv_actual_demand_weekly` -> `SalesHistory.ActualDemandWeekly`
- `slv_forecast_demand_monthly` -> `ForecastHistory.ForecastDemandMonthly`
- `slv_naive_forecast_monthly` -> `ForecastHistory.NaiveForecastMonthly`
- `slv_open_order_line_level` -> `OpenOrderHistory.OpenOrderLineLevel`
- `slv_open_order_monthly` -> `OpenOrderHistory.OpenOrderMonthly`

**Steps:**

- [ ] Step 1: Create the approved Silver process schemas.
- [ ] Step 2: Create physical Silver tables side-by-side with Pascal Case names.
- [ ] Step 3: Use explicit column lists. Do not use `SELECT *` in managed v10 transforms.
- [ ] Step 4: Move significant source enhancements out of logical Bronze and into Silver transformations.
- [ ] Step 5: Preserve v9 load pattern semantics using `load_type`.
- [ ] Step 6: Preserve primary key metadata for duplicate checks.
- [ ] Step 7: Preserve `depends_on` dependencies using canonical asset IDs, not only schema/table text.
- [ ] Step 8: Add lineage edge type `DomainTransform`.
- [ ] Step 9: Keep old v9 `silver` objects unchanged.

**Exit gate:**

- Every v9 Silver output has a v10 Domain Silver equivalent.
- Naming is Bob/Rakesh-approved or explicitly marked as draft.

### Phase 7: Handle EnterpriseData Silver Candidates

**Purpose:** use EnterpriseData for reusable/conformed Silver only, not for every Supply Chain transformation.

**Candidate groups:**

- `ReferenceMaster / NeedOwnerDecision`
- Any Silver object Bob/Rakesh classifies as cross-domain reusable

**Steps:**

- [ ] Step 1: Create a candidate list from `12_v10_object_classification_mapping.md`.
- [ ] Step 2: Separate domain-specific Supply Chain logic from conformed/reusable logic.
- [ ] Step 3: For each reusable candidate, document owner, consumer domains, grain, keys, refresh SLA, and source contract.
- [ ] Step 4: Ask Bob/Rakesh whether the object belongs in EnterpriseData `SupplyChain_Warehouse` or remains local.
- [ ] Step 5: If approved, create EnterpriseData implementation plan for that object.
- [ ] Step 6: If not approved, keep object in local `ReferenceMaster` or domain Silver schema.
- [ ] Step 7: Do not create EnterpriseData objects without approval.

**Exit gate:**

- No object is moved to EnterpriseData just because it is named Silver.
- Reusability and ownership drive placement.

### Phase 8: Build Dedicated Gold Warehouse

**Purpose:** create a clean serving boundary for business-ready analytics and Direct Lake.

**Create:**

- Warehouse: `SupplyChain_Gold_Warehouse`
- Schema: `ForecastAccuracy`
- Physical tables:
  - `ForecastAccuracy.FactForecastActual`
  - `ForecastAccuracy.FactForecastKpi`

**Steps:**

- [ ] Step 1: Create `ForecastAccuracy` schema.
- [ ] Step 2: Create physical Gold tables, not non-materialized SQL views as default semantic source.
- [ ] Step 3: Populate Gold from v10 Domain Silver tables.
- [ ] Step 4: Keep explicit column list and stable semantic names.
- [ ] Step 5: Add primary key / uniqueness metadata even if Fabric constraints are not enforced.
- [ ] Step 6: Add DQ rules for Gold KPI sanity checks.
- [ ] Step 7: Add source-target reconciliation between v9 Gold and v10 Gold.
- [ ] Step 8: Add lineage edge type `GoldPublish`.
- [ ] Step 9: Add optional compatibility views only if a legacy consumer requires them.

**Exit gate:**

- Gold physical tables are available for semantic model connection.
- Compatibility views are not treated as the default BI contract.

### Phase 9: Create v10 Pipeline Copies

**Purpose:** preserve v9 operation while building a safer v10 orchestration path.

**Create pipeline copies:**

- `pl_sc_v10_master`
- `pl_sc_v10_mart`
- `pl_sc_v10_access_gate`
- `pl_sc_v10_stage`
- `pl_sc_v10_silver`
- `pl_sc_v10_silver_wave`
- `pl_sc_v10_dq_gate`
- `pl_sc_v10_reconcile`
- `pl_sc_v10_gold_publish`
- `pl_sc_v10_semantic_refresh`
- `pl_sc_v10_finalize`

**Pipeline order:**

```text
pl_sc_v10_master
  -> load active projects
  -> ForEach project
       -> pl_sc_v10_mart
            -> pl_sc_v10_access_gate
            -> pl_sc_v10_stage where required
            -> pl_sc_v10_silver
            -> pl_sc_v10_dq_gate
            -> pl_sc_v10_reconcile
            -> pl_sc_v10_gold_publish
            -> pl_sc_v10_semantic_refresh
            -> pl_sc_v10_finalize
```

**Steps:**

- [ ] Step 1: Export v9 pipeline definitions before copying.
- [ ] Step 2: Create v10 pipeline copies with new names.
- [ ] Step 3: Keep v9 pipeline schedules unchanged.
- [ ] Step 4: Point v10 pipelines to v10 metadata tables.
- [ ] Step 5: Preserve project/mart parameter flow from master to mart.
- [ ] Step 6: Preserve Bronze/Gold smart-skip due filters.
- [ ] Step 7: Add project-aware Silver wave computation.
- [ ] Step 8: Add DQ mode parameter: `Off`, `WarnOnly`, `CriticalStops`.
- [ ] Step 9: Add reconciliation after staged loads and after Gold publish.
- [ ] Step 10: Add finalizer that logs direct-source, staging, Silver, Gold, DQ, reconciliation, and semantic refresh status.
- [ ] Step 11: Run v10 pipelines manually only in DEV until sign-off.

**Exit gate:**

- v10 pipelines can execute manually without touching v9 schedules.
- Silver execution is project-aware before multi-mart scaling.

### Phase 10: Make Silver DAG Project-Aware

**Purpose:** fix a known v9/v10 gap before true multi-mart scale.

**Create or modify in v10 only:**

- `Meta.SilverDagWaveRuntime`
- `Meta.usp_ComputeSilverWaves`
- `Meta.vw_SilverWaveRuntime`

**Required fields:**

```text
project
wave_number
asset_id
target_schema
target_object
depends_on_asset_ids
is_due
execution_status
```

**Steps:**

- [ ] Step 1: Add `project` to v10 Silver wave runtime.
- [ ] Step 2: Compute waves per project.
- [ ] Step 3: Resolve dependencies by `asset_id`, not by old schema/table names only.
- [ ] Step 4: Filter `pl_sc_v10_silver` lookup by `project_name`.
- [ ] Step 5: Filter `pl_sc_v10_silver_wave` lookup by `project_name` and `wave_number`.
- [ ] Step 6: If future Silver assets have monthly/weekly frequency, apply schedule gate before wave runtime is built.
- [ ] Step 7: Add cross-mart dependency rule: a mart cannot read another mart's Silver unless dependency is explicitly registered and approved.

**Exit gate:**

- A project can run without executing another project's Silver objects.
- Future mixed-frequency Silver assets have a defined skip strategy.

### Phase 11: Activate Source Contract Gate

**Purpose:** make direct shortcut reads safe enough to replace unnecessary Bronze copies.

**Create or use:**

- Existing v9 `schema_contracts` as seed.
- v10 `Meta.SourceContractRun`.
- v10 validation procedure: `Meta.usp_ValidateSourceContract`.

**Gate modes:**

```text
Off
WarnOnly
CriticalStops
```

**Steps:**

- [ ] Step 1: Load existing schema contracts into v10 metadata.
- [ ] Step 2: Add expected source object, source workspace/item, schema, column, data type, nullable flag, and grain notes.
- [ ] Step 3: Validate direct-read sources before Silver transforms.
- [ ] Step 4: Validate staged sources before staging load.
- [ ] Step 5: Record missing columns, type mismatches, unexpected columns, and inaccessible sources.
- [ ] Step 6: In DEV, start with `WarnOnly`.
- [ ] Step 7: Move to `CriticalStops` only after false positives are resolved.

**Exit gate:**

- Direct source reads are governed by contract checks.
- Staging removal is blocked if contracts fail.

### Phase 12: Activate Source-Target Reconciliation

**Purpose:** close the gap that v9 designed but did not fully activate.

**Create:**

- `Meta.ReconciliationRule`
- `Meta.ReconciliationResult`
- Procedure: `Meta.usp_RunReconciliation`

**Minimum reconciliation types:**

```text
RowCount
DistinctPrimaryKeyCount
BusinessDateRange
NullCriticalKeyCount
KpiAggregateParity
```

**Steps:**

- [ ] Step 1: Create rules for high-volume facts and EDW supplement objects first.
- [ ] Step 2: Compare v10 staged object against approved source.
- [ ] Step 3: Compare v10 Silver object against v9 Silver equivalent.
- [ ] Step 4: Compare v10 Gold object against v9 Gold equivalent.
- [ ] Step 5: Store absolute difference and percent difference.
- [ ] Step 6: Set warning and failure thresholds per object.
- [ ] Step 7: Block cutover if critical facts exceed approved thresholds.

**Exit gate:**

- No direct-only conversion is accepted without reconciliation.
- No Gold cutover is accepted without KPI parity.

### Phase 13: Activate DQ Gate Mode

**Purpose:** preserve v9 DQ engine without making the initial v10 build unstable.

**Use / create:**

- Existing DQ rule export as seed.
- v10 `Meta.DQGateRun`.
- Pipeline: `pl_sc_v10_dq_gate`.

**Steps:**

- [ ] Step 1: Import the 54 existing DQ rules into v10 metadata.
- [ ] Step 2: Keep active/inactive state from v9 export.
- [ ] Step 3: Add gate placement: post-Staging, post-Silver, post-Gold.
- [ ] Step 4: Run `WarnOnly` in the first v10 parallel runs.
- [ ] Step 5: Promote only critical checks to `CriticalStops` after business approval.
- [ ] Step 6: Record DQ status in `Meta.vw_TableDictionary`.
- [ ] Step 7: Add failed DQ summary into finalizer output.

**Exit gate:**

- DQ is not silently removed.
- DQ failure behavior is explicit and approved.

### Phase 14: Extend Enterprise Dictionary Adapter

**Purpose:** meet Bob's TableDictionary expectation without rebuilding what v9 already solved.

**Design rule:**

Do not create a single physical TableDictionary base table with 63 or 69 columns. The v10 base metadata tables should stay normalized and small. `Meta.vw_TableDictionary` is the compatibility adapter that joins, derives, and null-fills fields into the Bob/Enterprise shape.

**Create / extend:**

- `Meta.vw_TableDictionary`
- Optional physical export: `Meta.TableDictionaryExport` only if Bob/Rakesh require it.

**Adapter output target:**

- Preserve the v9 external contract: 63 Enterprise-compatible columns plus v9/v10 extension columns.
- Current v9 evidence shows `meta.vw_table_dictionary` has 69 columns: 63 Enterprise-compatible columns plus 6 v9 extension columns.
- v10 can add extension columns only after confirming Bob/Rakesh do not require a strict 63-column physical export.

**Core input fields required somewhere in v10 control-plane tables:**

```text
workspace_name
item_name
schema_name
object_name
object_type
canonical_layer
access_mode
domain_group
project
primary_key
refresh_frequency
cron_expression
next_run_time
source_objects
load_type
owner_name
approval_status
last_run_status
last_success_utc
last_success_cst
rows_loaded
dq_status
source_contract_status
security_classification
```

**Steps:**

- [ ] Step 1: Keep core metadata in normalized tables such as `Meta.AssetRegistryV10`, `Meta.AssetGovernance`, source contracts, DQ, reconciliation, and run logs.
- [ ] Step 2: Map v10 registry/governance fields to the 63 Enterprise-compatible TableDictionary columns.
- [ ] Step 3: Preserve the 6 existing v9 extension columns or replace them with approved v10 extension columns only after sign-off.
- [ ] Step 4: Preserve CST output fields from v9.
- [ ] Step 5: Derive workspace/item/access mode fields in the view rather than duplicating them into every base table.
- [ ] Step 6: Add approval status, owner, DQ status, and source contract status through joins.
- [ ] Step 7: Validate all managed v10 physical objects appear in the adapter.
- [ ] Step 8: Ask Bob/Rakesh whether a physical export/sync is required.

**Exit gate:**

- Every managed v10 object has dictionary metadata.
- `Meta.vw_TableDictionary` exposes the Bob/Enterprise-compatible output contract.
- No oversized 63/69-column physical base table is required.
- Physical sync is not built unless required.

### Phase 15: Define Security Matrix Before Cutover

**Purpose:** adapt Bob's schema security standard to Fabric's workspace/item/semantic model security model.

**Create:**

- `Meta.SecurityPolicy`
- `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/security_matrix.md`

**Security layers:**

```text
Workspace role
Item permission
Warehouse SQL endpoint permission
Lakehouse SQL endpoint permission
OneLake file/table access
Semantic model permission
RLS / OLS if required
Fixed identity if required
```

**Steps:**

- [ ] Step 1: List who can access Enterprise Lakehouse shortcuts.
- [ ] Step 2: List who can access v10 processing Warehouse.
- [ ] Step 3: List who can access v10 Gold Warehouse.
- [ ] Step 4: List who can access semantic model.
- [ ] Step 5: Decide whether SQL endpoint grants are required for non-Power-BI consumers.
- [ ] Step 6: Decide whether semantic RLS/OLS is required.
- [ ] Step 7: Do not apply grants until owner approval exists.

**Exit gate:**

- Security ownership is known before production cutover.

### Phase 16: Build Semantic Model Contract

**Purpose:** keep Direct Lake as the primary serving mode and avoid accidental view fallback.

**Create:**

- `Meta.SemanticModelContract`
- `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/direct_lake_validation.md`

**Steps:**

- [ ] Step 1: Connect semantic model only to physical Gold tables by default.
- [ ] Step 2: Validate that no semantic table uses non-materialized SQL views unless fallback is accepted.
- [ ] Step 3: Validate Direct Lake framing/refresh after Gold publish.
- [ ] Step 4: Validate relationships and one-side uniqueness.
- [ ] Step 5: Validate unsupported data types are not present in Gold semantic tables.
- [ ] Step 6: Validate KPI measures against v9 semantic outputs.
- [ ] Step 7: Keep compatibility views outside default semantic model path.

**Exit gate:**

- Semantic model remains Direct Lake or fallback is explicitly documented and approved.

### Phase 17: CI/CD And Deployment Guardrails

**Purpose:** avoid making v10 a manual-only build.

**Create:**

- `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/deployment_checklist.md`
- Optional future folder: `Enterprise_SupplyChain_Dev_architect/deployment/`

**Minimum checks:**

```text
No destructive DDL
No SELECT * in managed transforms
Primary key metadata exists
Source contract exists for direct/staged source
DQ rules classified
Reconciliation rules exist for critical facts
Object appears in TableDictionary adapter
Lineage edge exists
Security owner recorded
Approval status recorded
Semantic model impact recorded
Rollback path recorded
```

**Steps:**

- [ ] Step 1: Create deployment checklist template.
- [ ] Step 2: Add one checklist row per object.
- [ ] Step 3: Block deployment if any object lacks owner, PK metadata, source contract, or approval status.
- [ ] Step 4: Keep full Enterprise `.sqlproj` conversion as a later workstream unless Bob/Rakesh require it now.
- [ ] Step 5: Use runtime validation first if Azure DevOps/project access remains blocked.

**Exit gate:**

- Every physical object has a deployment checklist row.

### Phase 18: Parallel Run And Parity Validation

**Purpose:** prove v10 matches v9 before cutover.

**Create:**

- `Enterprise_SupplyChain_Dev_architect/build_runs/<YYYYMMDD_HHMMSS>/parallel_run_results.md`

**Validation checklist:**

- [ ] Step 1: Run v9 normally.
- [ ] Step 2: Run v10 manually after v9 completes.
- [ ] Step 3: Compare row counts for staged, Silver, and Gold objects.
- [ ] Step 4: Compare distinct primary key counts.
- [ ] Step 5: Compare business date ranges.
- [ ] Step 6: Compare null counts on critical keys.
- [ ] Step 7: Compare KPI aggregates for `FactForecastActual` and `FactForecastKpi`.
- [ ] Step 8: Compare DQ warning/error counts.
- [ ] Step 9: Compare lineage edge completeness from source shortcut to Gold.
- [ ] Step 10: Validate Direct Lake semantic model after Gold publish.
- [ ] Step 11: Repeat for at least three successful daily runs before cutover.

**Exit gate:**

- Three successful parallel runs.
- No critical DQ failure.
- Reconciliation thresholds accepted.
- Semantic model validation accepted.
- Bob/Rakesh approval captured.

### Phase 19: Cutover Plan

**Purpose:** switch consumers safely only after validation.

**Cutover actions:**

- Repoint semantic model or create v10 semantic model side-by-side.
- Repoint reports only after semantic validation.
- Disable v9 schedules only after rollback window is approved.
- Keep v9 objects available during rollback window.

**Steps:**

- [ ] Step 1: Create cutover checklist and rollback checklist.
- [ ] Step 2: Freeze v9 and v10 run status at cutover time.
- [ ] Step 3: Refresh/framing semantic model after final Gold publish.
- [ ] Step 4: Validate report smoke tests.
- [ ] Step 5: Confirm Bob/Rakesh or assigned approver signs off.
- [ ] Step 6: Disable old schedule only after explicit approval.
- [ ] Step 7: Do not delete old objects during cutover.

**Exit gate:**

- Consumers are served by v10 Gold/semantic path.
- Rollback path remains available.

### Phase 20: Post-Cutover Decommission Plan

**Purpose:** clean up only after stability, not during build.

**Decommission candidates:**

- Old v9 schedules.
- Old v9 pipeline copies.
- Obsolete v9 Bronze mirrors that passed direct-source validation.
- Compatibility views no longer used.
- Deprecated docs replaced by v10 runbook.

Detailed candidate list: `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`.

**Steps:**

- [ ] Step 1: Wait through approved rollback period.
- [ ] Step 2: Confirm no reports, semantic model tables, or external SQL consumers depend on old objects.
- [ ] Step 3: Archive object definitions and final row-count snapshots.
- [ ] Step 4: Disable old objects before deleting anything.
- [ ] Step 5: Ask for explicit destructive-operation approval before any delete/drop/truncate action.

**Exit gate:**

- Decommission is approved object-by-object.
- No irreversible action happens without explicit approval.

## 6. Object-Level Initial Mapping

### 6.1 EDW supplement / staging exceptions

| Current object | v10 target | EDW exit status | Action |
|---|---|---|---|
| `bronze.brz_saleshistory_afi__invoicedetail` | `Staging` initially, then direct shortcut if approved | `ExitCandidate` | Keep persisted fallback; run dual-read validation before cutover |
| `bronze.brz_saleshistory_afi__invoiceheader` | `Staging` | `NotReady` | Keep persisted staging until date coverage/SLA passes |
| `bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily` | `Staging` | `NotReady` | Keep persisted staging; validate grain and snapshot coverage before any cutover |
| `bronze.ref_product` | `ReferenceMaster` or EnterpriseData | `ExitCandidate` + owner decision | Keep persisted fallback; validate source and get owner approval |

Detailed exit runbook:

- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/15_v10_edw_supplement_exit_strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`

### 6.2 Logical Bronze direct-read candidates

| Current object | v10 target | Action |
|---|---|---|
| `bronze.brz_wholesale_codis_afi__codatan` | Enterprise Lakehouse shortcut | Direct-read if contract/performance passes |
| `bronze.brz_wholesale_codis_afi__comast` | Enterprise Lakehouse shortcut | Direct-read if contract/performance passes |
| `bronze.brz_wholesale_codis_afi__extord` | Enterprise Lakehouse shortcut | Direct-read if contract/performance passes |
| `bronze.brz_wholesale_codis_afi__extorit` | Enterprise Lakehouse shortcut | Direct-read if contract/performance passes |

### 6.3 Domain Silver

| Current object | v10 schema/object | Action |
|---|---|---|
| `silver.slv_invoice_detail_line_level` | `SalesHistory.InvoiceDetailLineLevel` | Build side-by-side |
| `silver.slv_invoice_weekly` | `SalesHistory.InvoiceWeekly` | Build side-by-side |
| `silver.slv_actual_demand_monthly` | `SalesHistory.ActualDemandMonthly` | Build side-by-side |
| `silver.slv_actual_demand_weekly` | `SalesHistory.ActualDemandWeekly` | Build side-by-side |
| `silver.slv_forecast_demand_monthly` | `ForecastHistory.ForecastDemandMonthly` | Build side-by-side |
| `silver.slv_naive_forecast_monthly` | `ForecastHistory.NaiveForecastMonthly` | Build side-by-side |
| `silver.slv_open_order_line_level` | `OpenOrderHistory.OpenOrderLineLevel` | Build side-by-side |
| `silver.slv_open_order_monthly` | `OpenOrderHistory.OpenOrderMonthly` | Build side-by-side |

### 6.4 Gold serving

| Current object | v10 schema/object | Action |
|---|---|---|
| `gold.gld_fact_flat_forecast_actual` | `ForecastAccuracy.FactForecastActual` | Publish physical Gold table |
| `gold.gld_fact_forecast_kpi` | `ForecastAccuracy.FactForecastKpi` | Publish physical Gold table |

## 7. Bob/Rakesh Acceptance Alignment

### Covered directly

- [Verified] Bronze mimics source structures.
- [Verified] Significant enhancements move to Silver/process schemas.
- [Verified] Silver and Gold use Pascal Case naming after approval.
- [Verified] Schemas group objects by business/process/metric area.
- [Verified] Gold is a dedicated serving boundary.
- [Verified] TableDictionary metadata remains required.
- [Verified] Technical design approval is required before production development.

### Adapted for Fabric

- [Verified] Old PowerBI-view rule becomes Gold physical tables plus semantic model contract for strict Direct Lake.
- [Verified] Old PolyBase/external-table intent becomes OneLake shortcuts plus source contracts.
- [Verified] Old SQL Agent alerting intent becomes Fabric pipeline logging, alert path, and health dashboard/runbook.
- [Verified] Old schema security intent becomes workspace/item/SQL endpoint/semantic security matrix.
- [Verified] Old ADW distribution/index standards become Fabric performance/Direct Lake validation gates.

### Not accepted blindly

- [Verified] Do not force all Supply Chain Silver into EnterpriseData. Move only reusable/conformed objects after ownership approval.
- [Verified] Do not create a PowerBI SQL view layer as default if the target is strict Direct Lake.
- [Verified] Do not remove staging capability just to reduce duplication. Remove only when direct source is stable and validated.
- [Verified] Do not rename/drop v9 objects during side-by-side build.

## 8. Build Readiness Decision

```text
Status: ready to start v10 side-by-side build planning and non-destructive scaffolding.
Status: not ready for production cutover.
Status: not ready to remove BronzeMirror/Staging.
Status: not ready to move EnterpriseData Silver objects without sign-off.
Readiness score: 88/100 for documentation and side-by-side planning; not a production cutover score.
```

Recommended first engineering unit:

```text
Build v10 metadata/control-plane compatibility layer first.
Then build access decision engine.
Then build Staging and Domain Silver side-by-side.
Then build Gold Warehouse and semantic validation.
Then run parallel parity.
```

## 9. Immediate Next File/Artifact Checklist

- [ ] `build_runs/<timestamp>/baseline_manifest.md`
- [ ] `build_runs/<timestamp>/approval_pack.md`
- [ ] `build_runs/<timestamp>/security_matrix.md`
- [ ] `build_runs/<timestamp>/deployment_checklist.md`
- [ ] `build_runs/<timestamp>/direct_lake_validation.md`
- [ ] `build_runs/<timestamp>/parallel_run_results.md`

## 10. Stop Conditions

Stop implementation and ask for decision if any of these occur:

- A required source shortcut is missing or inaccessible.
- Direct shortcut read is materially slower or unstable.
- Source contract fails for a direct-read candidate.
- DQ critical checks fail after gate mode is enabled.
- Source-target reconciliation exceeds approved threshold.
- Semantic model falls back unexpectedly from Direct Lake.
- Bob/Rakesh reject naming, placement, or Gold serving interpretation.
- Any operation would delete, drop, truncate, bulk overwrite, rename live production objects, or disable live schedules.
