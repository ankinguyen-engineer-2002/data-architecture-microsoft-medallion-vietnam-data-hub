# v10 Build Blueprint After Readiness Verification

Date: 2026-04-30

This file summarizes the concrete build target after completing the readiness verification pack.

## 1. Build Decision

Build **v10 side-by-side**, not in-place.

```text
v9 remains live
v10 is built in parallel
compare outputs
cut over only after sign-off and repeated successful validation
```

Current documentation readiness score is `88/100` in `16_v10_readiness_scorecard_and_v9_cleanup.md`; this permits non-destructive scaffolding/planning only, not production cutover.

## 2. Target Physical Items

### SupplyChain Dev Workspace

```text
SupplyChain Dev workspace
├── Enterprise_Access_Lakehouse
│   └── Shortcuts to EnterpriseData / source products
│       Role: logical Bronze
│
├── SupplyChain_Processing_Warehouse
│   ├── Meta
│   │   ├── Asset registry
│   │   ├── Access decision metadata
│   │   ├── DQ rules/results
│   │   ├── Schema contracts
│   │   ├── Source-target reconciliation results
│   │   ├── Lineage
│   │   ├── Run/pipeline audit logs
│   │   ├── Performance/cost monitoring
│   │   └── Enterprise Dictionary Adapter
│   │
│   ├── Staging
│   │   └── EDW supplement and other exception mirrors only
│   │
│   ├── ReferenceMaster
│   │   └── Domain references not owned by EnterpriseData
│   │
│   ├── SalesHistory
│   │   └── Supply Chain domain Silver
│   │
│   ├── ForecastHistory
│   │   └── Supply Chain domain Silver
│   │
│   └── OpenOrderHistory
│       └── Supply Chain domain Silver
│
├── SupplyChain_Gold_Warehouse
│   └── ForecastAccuracy
│       ├── FactForecastActual
│       └── FactForecastKpi
│
└── SupplyChain semantic model
    └── Direct Lake over physical Gold tables
```

### EnterpriseData Workspace

```text
EnterpriseData workspace
├── upstream source products
├── reusable/conformed Silver or reference assets
└── governed source contracts/SLA ownership
```

Only move assets into EnterpriseData when they are approved as reusable/conformed. Supply Chain-specific logic stays in SupplyChain Dev.

## 3. Control Plane To Build

Build the control plane first:

| Component | Build action |
|---|---|
| Asset Registry | Extend current `sp_registry`, keep backward compatibility |
| Access Decision Engine | Add `access_mode` routing: `DirectShortcut`, `StageRequired`, `EDWSupplement`, `ManualSeed`, `EnterpriseSilver`, `GoldServing` |
| Generic SQL Load Runner | Preserve `usp_generic_load`, extend routing instead of creating per-table SPs |
| Schedule Gate | Preserve verified Bronze/Gold `next_run_time` filters |
| Project-aware Silver DAG | Add project-aware wave runtime before real multi-mart scale |
| DQ Gate Engine | Add explicit mode: `Off`, `WarnOnly`, `CriticalStops` |
| Source Contract Gate | Promote existing 674-column contracts into pre-load validation |
| Source-target Reconciliation | Build new reconciliation for critical facts and staged exceptions |
| Lineage Builder | Add logical vs physical edge types and EDW supplement bridge |
| Finalizer | Cover Staging, DirectRead, Silver, Gold publish, monitors, and semantic refresh |
| Enterprise Dictionary Adapter | Extend existing `vw_table_dictionary`; physical sync only if Enterprise ETL/Rakesh require it |

## 4. Data Layer Build

### Logical Bronze

Do not create a new canonical Bronze Warehouse schema.

Build behavior:

- Directly reference `Enterprise_Access_Lakehouse` shortcuts where stable.
- Treat shortcuts as source-aligned logical Bronze.
- No business transformations in Bronze.

### Staging

Build `Staging` only for exceptions:

- EDW supplement.
- Missing source SLA/coverage.
- Snapshot consistency requirement.
- Replay/debug requirement.
- Performance requirement.
- Warehouse-native CTAS/DML requirement.

### Domain Silver

Build Supply Chain domain Silver schemas:

- `SalesHistory`
- `ForecastHistory`
- `OpenOrderHistory`
- `ReferenceMaster`

Rules:

- Pascal Case schema/object naming after sign-off.
- Keep business transformations here.
- Promote to EnterpriseData only after owner approval.

### Gold

Build dedicated Gold serving item:

- `SupplyChain_Gold_Warehouse`
- `ForecastAccuracy` schema/domain
- physical Gold tables for Direct Lake

Rules:

- Semantic model reads Gold physical tables by default.
- SQL compatibility views are optional and must be tested for Direct Lake fallback.

## 5. Object Movement Summary

| Current group | v10 target |
|---|---|
| 3 EDW-backed Bronze facts | `Staging` as `EDWSupplement`; 1 ExitCandidate and 2 NotReady |
| 1 EDW-backed reference object (`ref_product`) | `ReferenceMaster` or EnterpriseData after validation and owner sign-off |
| 4 direct Bronze source mirrors | Logical Bronze direct-read candidates |
| 10 monthly REF + 1 daily REF | `ReferenceMaster` or EnterpriseData reference after ownership sign-off |
| 8 Silver tables | Domain Silver schemas |
| 2 Gold tables | `SupplyChain_Gold_Warehouse.ForecastAccuracy` physical tables |
| `meta` objects | `Meta` control plane, extended not replaced |

Detailed mapping:

- `Enterprise_SupplyChain_Dev_architect/20_proposals/12_v10_object_classification_mapping.md`
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`

## 6. Validation Gates

Before cutover:

- Registry row-count baseline compared.
- Source contract validation passed.
- Source-target reconciliation passed for critical facts.
- DQ critical checks passed.
- Silver DAG execution order verified.
- Smart skip due/not-due cases tested.
- EDW supplement lineage bridge preserved.
- EDW supplement exit strategy applied object-by-object; no bulk cutover.
- Gold metrics reconciled.
- Direct Lake semantic mode validated.
- Enterprise ETL/Rakesh naming and ownership sign-off captured.

## 7. What Not To Build Yet

Do not build these until approved:

- Physical EnterpriseData Silver moves.
- Destructive rename/drop of v9 schemas/tables.
- Compatibility SQL views as default Power BI source.
- Full direct-only removal of BronzeMirror/Staging.
- CI/CD ProjectReference conversion with `$(...)` variables.
- Security grants/RLS/OLS changes.

## 8. Next Engineering Unit

Recommended first build unit:

```text
v10 metadata/control-plane compatibility layer
  -> registry extension draft
  -> access_mode routing design
  -> project-aware Silver DAG design
  -> DQ/source-contract/reconciliation gate design
```

This gives the team a safe foundation before creating or moving physical data objects.
