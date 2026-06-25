# Architecture Blueprint: Hybrid Medallion v10

Muc tieu: nhin kien truc theo 2 lop rieng biet:

- **Logical Medallion**: Bronze / Silver / Gold theo chat luong du lieu.
- **Physical Fabric Setup**: workspace, lakehouse, warehouse, control plane, pipeline, semantic model.

Diem quan trong: **v9 control plane khong phai Bronze/Silver/Gold**. No la lop dieu khien nam ngang, quan ly orchestration, DQ, lineage, audit, scheduling cho toan bo Medallion.

## 1. Pure Mermaid Files

Neu copy len Mermaid Live Editor, hay copy truc tiep cac file `.mmd` trong folder [`diagrams`](../diagrams/), khong copy cac block `text`.

- [`../diagrams/01_super_plan_target_flow.mmd`](../diagrams/01_super_plan_target_flow.mmd)
- [`../diagrams/02_main_architecture.mmd`](../diagrams/02_main_architecture.mmd)
- [`../diagrams/03_control_plane.mmd`](../diagrams/03_control_plane.mmd)
- [`../diagrams/04_direct_vs_staging_decision.mmd`](../diagrams/04_direct_vs_staging_decision.mmd)
- [`../diagrams/05_short_term_transition.mmd`](../diagrams/05_short_term_transition.mmd)
- [`../diagrams/06_long_term_target.mmd`](../diagrams/06_long_term_target.mmd)
- [`../diagrams/07_pipeline_sequence.mmd`](../diagrams/07_pipeline_sequence.mmd)
- [`../diagrams/08_mart_schedule_smart_skip.mmd`](../diagrams/08_mart_schedule_smart_skip.mmd)
- [`../diagrams/09_v9_feature_parity_control_plane.mmd`](../diagrams/09_v9_feature_parity_control_plane.mmd)
- [`../diagrams/10_bob_standards_overlay.mmd`](../diagrams/10_bob_standards_overlay.mmd)

## 2. Overview De Nhin

Enterprise_Data:

- Upstream source products.
- Reusable enterprise Silver when cross-domain.

SupplyChain Dev:

- `Enterprise_Access_Lakehouse`: shortcut access layer, logical Bronze for Supply Chain.
- Optional `Staging` / `BronzeMirror`: only when direct shortcut is not enough.
- `EDWSupplement`: explicit staging/fallback lifecycle governed by `ADR-002`, not a permanent Bronze layer.
- Domain Silver schemas: Supply Chain-owned transformation.
- Gold serving warehouse/item: BI-ready consumption boundary.
- Semantic model / reports.

v9/v10 Control Plane:

Note: day la control-plane target can preserve/activate trong v10. Mot so capability hien tai co object/design nhung can verify hoac activate trong pipeline, dac biet `Smart Skip`, `Schema Contract Gate`, `Performance Baseline Monitor`, `Cost Monitor`, va alert/SLA hooks.

- Metadata registry.
- Generic load framework.
- Load pattern router.
- Mart routing / multi-mart orchestration.
- Schedule gate / cron evaluation.
- Smart skip by `next_run_time`.
- Execution planner for batch size and concurrency.
- DAG orchestration.
- Parent-child wave runner.
- DQ gates.
- Schema contract gate.
- Lineage.
- Audit logging.
- Retry / snapshot conflict guard.
- Smart scheduling.
- Timezone normalizer.
- Enterprise dictionary adapter.
- Performance baseline monitor.
- Cost monitor.
- Schema contracts.
- Semantic refresh controls.

## 3. Main Architecture Diagram

GitHub/Mermaid version:

Pure Mermaid file: [`../diagrams/02_main_architecture.mmd`](../diagrams/02_main_architecture.mmd)

```mermaid
flowchart LR
    subgraph ED["Enterprise_Data workspace"]
        SRC["Upstream Source Products"]
        ES["Enterprise Reusable Silver"]
    end

    subgraph SC["SupplyChain Dev workspace"]
        LH["Enterprise_Access_Lakehouse<br/>Shortcut Access<br/>Logical Bronze"]
        STG["Staging / BronzeMirror<br/>Exception Only"]
        DW["Domain Processing Warehouse"]
        SIL["Domain Silver Schemas<br/>PascalCase"]
        GWH["SupplyChain Gold Warehouse<br/>Serving Boundary"]
        SEM["Semantic Model / Reports"]
        CTRL["v9 Control Plane<br/>Metadata / DQ / Lineage / Audit"]
    end

    SRC --> LH
    SRC --> ES
    LH -->|"Direct by default"| SIL
    LH -->|"Stage only if required"| STG
    STG --> SIL
    ES -->|"Cross-domain input"| SIL
    SIL --> GWH
    GWH --> SEM

    CTRL -.->|"registry"| LH
    CTRL -.->|"load decision"| STG
    CTRL -.->|"DAG + DQ"| SIL
    CTRL -.->|"publish + reconcile"| GWH
    CTRL -.->|"refresh + monitor"| SEM

    class SRC,LH bronze
    class STG staging
    class ES,SIL silver
    class GWH,SEM gold
    class CTRL control
    class DW neutral

    classDef bronze fill:#B86B2B,stroke:#6B3A12,color:#FFFFFF
    classDef staging fill:#D9822B,stroke:#8A4A0A,color:#FFFFFF
    classDef silver fill:#C7CCD6,stroke:#687080,color:#111111
    classDef gold fill:#F2C94C,stroke:#9A6B00,color:#111111
    classDef control fill:#0B3D91,stroke:#06275F,color:#FFFFFF
    classDef neutral fill:#E8EEF7,stroke:#6C7A89,color:#111111
```

## 4. Medallion Meaning Sau Refactor

### Bronze

- [Verified] Bronze la raw/source-aligned layer.
- Trong kien truc nay, Bronze khong nen la schema `bronze` trong Warehouse nua.
- Bronze logical = `Enterprise_Access_Lakehouse` shortcuts toi source tu `Enterprise_Data`.
- Bronze phai mimic source structure, khong chua business enhancement.

### Staging / BronzeMirror

- Khong phai Medallion layer chuan.
- La lop van hanh phu tro.
- Chi dung khi direct shortcut chua du on dinh hoac can persisted state.
- Day la noi thay the tu duy "copy toan bo Bronze".

### Silver

- La layer transformation chinh.
- Voi domain Supply Chain, Silver co the nam trong `SupplyChain Dev.SupplyChain_Warehouse`.
- Neu object la cross-domain, reusable, conformed enterprise entity thi moi promote sang `Enterprise_Data`.

### Gold

- La serving layer.
- Nen tach thanh Gold Warehouse/item rieng de phuc vu semantic model va BI.
- Gold khong nen lan voi staging/control/transformation.

## 5. Physical Setup Template

Khong dung table/data thuc te, chi la template.

```text
SupplyChain Dev workspace
├── Enterprise_Access_Lakehouse
│   ├── SourceSystemA
│   ├── SourceSystemB
│   └── ReferenceDomain
│
├── SupplyChain_Processing_Warehouse
│   ├── Meta
│   ├── Staging
│   ├── ForecastHistory
│   ├── InventoryHistory
│   ├── SalesHistory
│   ├── OrderHistory
│   └── ReferenceMaster
│
├── SupplyChain_Gold_Warehouse
│   ├── ForecastAccuracy
│   ├── InventoryPerformance
│   └── ServiceLevel
│
└── SupplyChain_Semantic_Model
    ├── certified measures
    ├── relationships
    └── BI reports
```

Enterprise side:

```text
Enterprise_Data workspace
├── Source_Data / upstream source products
├── Shared_Enterprise_Silver
│   ├── Customer
│   ├── Product
│   ├── Calendar
│   └── CrossDomainSales
└── Enterprise governance / contracts / approvals
```

## 6. Control Plane Placement

Recommended:

```text
Near-term:
  Keep v9 control plane inside SupplyChain_Processing_Warehouse.Meta

Long-term:
  Option A: keep local Meta for domain autonomy
  Option B: move shared orchestration metadata to enterprise ETL framework
  Option C: split local execution metadata and enterprise governance metadata
```

Recommendation: giu `Meta` local truoc. Khong nen move control plane qua som vi de pha DAG, DQ, logging, lineage hien tai.

Control plane khong chua business fact. No chua metadata van hanh.

Pure Mermaid file: [`../diagrams/03_control_plane.mmd`](../diagrams/03_control_plane.mmd)

```mermaid
flowchart TD
    REG["Asset Registry<br/>meta.sp_registry"]
    SRC["Source Contracts"]
    DEC["Access Decision Engine<br/>DirectShortcut / StageRequired"]
    MART["Mart Routing Engine<br/>project + pl_sc_mart"]
    SCHED["Schedule Gate<br/>frequency + cron_expression"]
    SKIP["Smart Skip Engine<br/>next_run_time + ufn_should_run"]
    PLAN["Execution Planner<br/>batch size + concurrency"]
    ORCH["Pipeline Orchestrator<br/>pl_sc_master"]
    DAG["DAG / Wave Planner<br/>depends_on + slv waves"]
    LOAD["Generic SQL Load Runner<br/>usp_generic_load"]
    DQ["Data Quality Gate Engine<br/>dq_rules + pl_dq_check"]
    LIN["Lineage Builder<br/>source_objects + sp_lineage"]
    LOG["Run Audit Logger<br/>sp_run_history + pipeline_run_log"]
    PERF["Performance / Cost Monitor"]
    SEM["Semantic Refresh Controller"]

    REG --> DEC
    SRC --> DEC
    REG --> MART
    REG --> SCHED
    SCHED --> SKIP
    SKIP --> MART
    MART --> PLAN
    PLAN --> ORCH
    DEC --> ORCH
    ORCH --> DAG
    DAG --> LOAD
    LOAD --> DQ
    DQ --> LIN
    LIN --> LOG
    LOG --> PERF
    PERF --> SEM

    class REG,SRC metadata
    class DEC,MART,SCHED,SKIP,PLAN,ORCH,DAG control
    class LOAD execution
    class DQ quality
    class LIN lineage
    class LOG,PERF monitor
    class SEM semantic

    classDef metadata fill:#E8EEF7,stroke:#50627A,color:#111111
    classDef control fill:#0B3D91,stroke:#06275F,color:#FFFFFF
    classDef execution fill:#6B7280,stroke:#374151,color:#FFFFFF
    classDef quality fill:#0F766E,stroke:#064E3B,color:#FFFFFF
    classDef lineage fill:#7C3AED,stroke:#4C1D95,color:#FFFFFF
    classDef monitor fill:#334155,stroke:#0F172A,color:#FFFFFF
    classDef semantic fill:#F2C94C,stroke:#9A6B00,color:#111111
```

Dedicated multi-mart, schedule, smart-skip Mermaid:

Pure Mermaid file: [`../diagrams/08_mart_schedule_smart_skip.mmd`](../diagrams/08_mart_schedule_smart_skip.mmd)

Full v9 feature parity control-plane Mermaid:

Pure Mermaid file: [`../diagrams/09_v9_feature_parity_control_plane.mmd`](../diagrams/09_v9_feature_parity_control_plane.mmd)

## 7. Direct vs Staging Logic

Pure Mermaid file: [`../diagrams/04_direct_vs_staging_decision.mmd`](../diagrams/04_direct_vs_staging_decision.mmd)

```mermaid
flowchart TD
    A["New Source Entity"] --> X{"Known EDW supplement?"}
    X -->|"Yes"| ES["EDWSupplement<br/>keep fallback active<br/>apply ADR-002"]
    X -->|"No"| B["Check Source Contract"]
    B --> C{"Stable schema and SLA?"}
    C -->|"Yes"| D{"Performance acceptable direct?"}
    C -->|"No"| S["Use Staging / BronzeMirror"]

    D -->|"Yes"| E["Direct to Silver"]
    D -->|"No"| S
    ES --> S
    ES -.->|"ExitCandidate only<br/>after dual-read validation + approval"| E

    S --> F["Persist snapshot with audit columns"]
    F --> G["Run staging DQ"]
    G --> H["Load Silver"]

    E --> I["Run Silver DQ"]
    H --> I
    I --> J{"DQ passed?"}
    J -->|"Yes"| K["Publish Gold"]
    J -->|"No"| L["Block / Warn / Quarantine"]

    class A,B neutral
    class C,D,J,X decision
    class E,H silver
    class S,F,G,ES staging
    class I,L quality
    class K gold

    classDef neutral fill:#E8EEF7,stroke:#6C7A89,color:#111111
    classDef decision fill:#FFFFFF,stroke:#111827,color:#111111
    classDef staging fill:#D9822B,stroke:#8A4A0A,color:#FFFFFF
    classDef silver fill:#C7CCD6,stroke:#687080,color:#111111
    classDef quality fill:#0F766E,stroke:#064E3B,color:#FFFFFF
    classDef gold fill:#F2C94C,stroke:#9A6B00,color:#111111
```

Rule:

```text
Direct shortcut is default.
Staging is exception.

Use staging only when:
- source contract is not stable
- schema drift risk is high
- source coverage is incomplete
- persisted snapshot is required
- replay/debug is required
- direct query performance is not acceptable
- warehouse-native DML/CTAS/MERGE is required
- object is one of the current `_edw` supplements and has not completed the `ADR-002` lifecycle
```

## 8. Short-Term vs Long-Term

### Short-Term Target

```text
Keep v9 running
  -> classify objects
  -> introduce AccessMode metadata
  -> treat Lakehouse shortcut as logical Bronze
  -> keep current mirror only where needed
  -> create compatibility views
  -> build new Gold boundary
  -> run old and new paths in parallel
```

Short-term diagram:

Pure Mermaid file: [`../diagrams/05_short_term_transition.mmd`](../diagrams/05_short_term_transition.mmd)

```mermaid
flowchart LR
	    LH["Logical Bronze<br/>Shortcut Lakehouse"]
	    OLD["Current v9 Warehouse<br/>Compatibility Layer"]
	    EDW["EDW Supplement<br/>4 fallback objects<br/>ADR-002 lifecycle"]
	    STG["Staging Exceptions"]
    SIL["New Domain Silver"]
    GOLD["New Gold Serving"]
    CTRL["Existing v9 Control Plane"]

	    LH --> OLD
	    OLD --> STG
	    OLD --> EDW
	    EDW --> STG
	    EDW -.->|"2 ExitCandidate<br/>2 NotReady"| LH
	    OLD --> SIL
    STG --> SIL
    SIL --> GOLD
    CTRL -.->|"controls"| OLD
    CTRL -.->|"extends"| SIL
    CTRL -.->|"validates"| GOLD

    class LH bronze
    class OLD legacy
	    class EDW,STG staging
    class SIL silver
    class GOLD gold
    class CTRL control

    classDef bronze fill:#B86B2B,stroke:#6B3A12,color:#FFFFFF
    classDef legacy fill:#64748B,stroke:#334155,color:#FFFFFF
    classDef staging fill:#D9822B,stroke:#8A4A0A,color:#FFFFFF
    classDef silver fill:#C7CCD6,stroke:#687080,color:#111111
    classDef gold fill:#F2C94C,stroke:#9A6B00,color:#111111
    classDef control fill:#0B3D91,stroke:#06275F,color:#FFFFFF
```

### Long-Term Target

```text
Logical Bronze shortcut is trusted
  -> direct to Silver for most entities
  -> staging exists but only for exceptions
  -> reusable Silver promoted to Enterprise_Data
  -> Gold is clean serving layer
  -> v9 control plane remains the operating system
```

Long-term diagram:

Pure Mermaid file: [`../diagrams/06_long_term_target.mmd`](../diagrams/06_long_term_target.mmd)

```mermaid
flowchart LR
    SRC["Enterprise Source Products"]
    LB["Logical Bronze<br/>Shortcuts"]
    DS["Domain Silver<br/>SupplyChain-owned"]
    ES["Enterprise Silver<br/>Reusable entities"]
    STG["Exception Staging"]
    GOLD["Gold Serving Warehouse"]
    SEM["Semantic Model"]
    CTRL["v9 Control Plane"]

    SRC --> LB
    SRC --> ES
    LB --> DS
    LB -.->|"exception"| STG
    STG --> DS
    ES --> DS
    DS --> GOLD
    GOLD --> SEM

    CTRL -.->|"metadata"| LB
    CTRL -.->|"DQ / DAG"| DS
    CTRL -.->|"publish"| GOLD
    CTRL -.->|"monitor"| SEM

    class SRC,LB bronze
    class STG staging
    class DS,ES silver
    class GOLD,SEM gold
    class CTRL control

    classDef bronze fill:#B86B2B,stroke:#6B3A12,color:#FFFFFF
    classDef staging fill:#D9822B,stroke:#8A4A0A,color:#FFFFFF
    classDef silver fill:#C7CCD6,stroke:#687080,color:#111111
    classDef gold fill:#F2C94C,stroke:#9A6B00,color:#111111
    classDef control fill:#0B3D91,stroke:#06275F,color:#FFFFFF
```

## 9. Metadata Template

Control plane nen co metadata du de khong hardcode layer logic.

```text
Meta.AssetRegistry
  - asset_name
  - logical_layer
  - physical_workspace
  - physical_item
  - physical_schema
  - physical_object
  - domain_group
  - access_mode
  - load_pattern
  - schedule_group
  - dependency_group
  - is_enterprise_reusable
  - is_active

Meta.SourceContract
  - source_asset
  - owner
  - sla_status
  - schema_status
  - freshness_expectation
  - allowed_drift_policy
  - approval_status

Meta.StagingPolicy
  - asset_name
  - staging_required
  - staging_reason
  - snapshot_required
  - retention_policy
  - replay_required

Meta.EDWExitPolicy
  - asset_name
  - edw_exit_status
  - logical_source_reference
  - fallback_source_reference
  - coverage_status
  - grain_status
  - performance_status
  - cutover_approved_by
  - fallback_retention_until

Meta.DqRule
  - asset_name
  - rule_type
  - severity
  - gate_action
  - sql_template
  - active_flag

Meta.LineageEdge
  - source_asset
  - target_asset
  - edge_type
  - logical_layer_from
  - logical_layer_to
  - physical_item_from
  - physical_item_to

Meta.RunLog
  - run_id
  - asset_name
  - status
  - start_time
  - end_time
  - rows_read
  - rows_written
  - error_message
```

## 10. Pipeline Logic Template

```text
pl_master
  -> load active registry
  -> group by schedule / mart / domain
  -> call pl_domain_mart

pl_domain_mart
  -> source contract validation
  -> EDW supplement lifecycle check
  -> staging decision
  -> run staging loads if required
  -> compute Silver DAG waves
  -> run Silver loads by dependency wave
  -> run DQ gates
  -> publish Gold
  -> refresh semantic model
  -> finalize lineage and audit
```

Mermaid:

Pure Mermaid file: [`../diagrams/07_pipeline_sequence.mmd`](../diagrams/07_pipeline_sequence.mmd)

```mermaid
sequenceDiagram
    participant M as Master Pipeline
    participant R as Meta Registry
    participant SG as Schedule Gate
    participant MR as Mart Router
    participant C as Contract Gate
    participant S as Staging Loader
    participant D as Silver DAG
    participant Q as DQ Gate
    participant G as Gold Publisher
    participant B as Semantic Model
    participant L as Audit and Lineage

    M->>R: Read active assets
    R->>SG: Evaluate cron_expression and frequency
    SG-->>M: Keep due assets only
    M->>MR: Group due assets by project
    MR-->>M: Run pl_sc_mart per project
    R->>C: Validate source contracts
    C-->>M: Direct or Stage decision
    M->>S: Run only required staging
    M->>D: Compute Silver waves
    D->>Q: Validate each wave
    Q-->>D: Pass, warn, or block
    D->>G: Publish Gold outputs
    G->>B: Refresh semantic model
    B->>L: Log final status and lineage
```

## 11. Diem Sang v9 Duoc Giu 100%

```text
v9 strengths kept:
- Metadata-driven execution
- Generic SQL load framework
- DAG / wave orchestration
- Data Quality gates
- Auto lineage
- Run audit and finalization
- Smart scheduling
- Schema contracts
- Performance baseline
- Cost logging
- Semantic model refresh discipline
```

Diem thay doi la: v9 khong con assume "Bronze = local warehouse schema bat buoc". v9 se control bang metadata:

```text
AccessMode = DirectShortcut
AccessMode = StageRequired
AccessMode = EDWSupplement
AccessMode = ManualSeed
AccessMode = EnterpriseSilver
AccessMode = GoldServing
```

## 12. Danh Gia Kien Truc

- [Verified] Fabric medallion khuyen nghi Bronze raw, Silver enriched/validated, Gold curated.
- [Verified] Shortcuts giup query/reference data khong copy, phu hop de xem Enterprise Lakehouse shortcut la logical Bronze.
- [Verified] Lakehouse SQL Analytics Endpoint read-only, nen khong thay the hoan toan Warehouse-native processing neu can write/DML/CTAS/MERGE.
- [Likely] Hybrid la best fit cho v9 vi giu duoc diem manh van hanh nhung giam duplication.
- [Likely] Long-term nen giam staging dan, nhung khong xoa staging capability khoi framework.
- [Verified] Current documentation readiness score is `88/100`, enough for non-destructive side-by-side planning but not enough for cutover/decommission.

## 13. Nguon Chinh

- Microsoft Fabric Medallion Architecture: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- Fabric Lakehouse Shortcuts: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-shortcuts
- OneLake Shortcuts: https://learn.microsoft.com/en-us/fabric/onelake/onelake-shortcuts
- Lakehouse SQL Analytics Endpoint: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint
- Better Together Lakehouse and Warehouse: https://learn.microsoft.com/en-us/fabric/data-warehouse/get-started-lakehouse-sql-analytics-endpoint
- Warehouse vs Lakehouse Decision Guide: https://learn.microsoft.com/en-us/fabric/fundamentals/decision-guide-lakehouse-warehouse
- Fabric Warehouse T-SQL Surface Area: https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area
- ADR-002 EDW Supplement Exit Strategy: ../docs/decisions/ADR-002-edw-supplement-exit-strategy.md
- v10 Readiness Scorecard And v9 Cleanup Candidate List: 16_v10_readiness_scorecard_and_v9_cleanup.md
