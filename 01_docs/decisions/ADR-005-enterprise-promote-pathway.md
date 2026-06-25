# ADR-005: Enterprise Promote Pathway — US/VN Collaboration Model

Date: 2026-05-03 (v1) · 2026-05-10 (v2 — topology corrected post Bob's reply)

Status: **v2 Proposed** — naming resolved 2026-05-04 (re-aligned 2026-05-10 per ADR-008), 3 promote targets clarified per Bob's email 2026-05-09, ownership questions still pending Bob reply

## Context

Two teams collaborate to build data infrastructure for Vietnam Supply Chain on Microsoft Fabric:

- **Bob + Rakesh's team (US, Enterprise Data)**: Owns `EnterpriseData-Dev` workspace (`5360a935-…`), sets enterprise standards, manages shared infrastructure across all value streams.
- **Aric + Cherry's team (VN, Supply Chain DA)**: Builds SC data products (Forecast Accuracy, Order Management) inside `Enterprise_SupplyChain Dev` workspace (`c8d9fc83-…`) — owned by SC value stream.

**Workspace topology (corrected 2026-05-10)** — only **2 workspaces** in scope:

1. `EnterpriseData-Dev` (Bob's enterprise hub) — 11 WHs (`MasterData_Warehouse`, `Wholesale_Warehouse`, `Retail_Warehouse`, `Distribution_Warehouse`, `Quality_Warehouse`, `Centralized_Warehouse`, `ETL_Framework`, `Source_Data` + 3 staging) + 5 LHs. Does NOT currently contain a `SupplyChain_Warehouse`.
2. `Enterprise_SupplyChain Dev` (SC value stream) — hosts BOTH:
   - **v8 legacy** (Cherry's): `SupplyChain_Lakehouse` + `SupplyChain_Warehouse` (id `e146ffe2-…`, dbo schema 110M rows feed Cherry's Control Tower)
   - **v10 new** (Aric's): `SupplyChain_Processing_Warehouse` + `SupplyChain_Gold_Warehouse` + `sc_forecast_control_tower` semantic model

Key constraints:

- Timezone gap: US (CST) vs VN (ICT) = ~12h offset. Each approval loop costs 24-48h.
- VN team needs delivery speed during dev. US team needs governance control on enterprise assets.
- Aric leads VN DE — has full authority on naming, style, internal tooling. Cross-WS items (write to Bob's hub, IT permissions) require Bob/Rakesh.
- Bob's `EnterpriseData-Dev` is `ConnectedAndInitialized` to Azure DevOps `ashleyfurniture/Enterprise Data Services/Fabric-EnterpriseData` (main branch) — VN team needs ADO access to align Git-as-source-of-truth.

## Decision

### Phase 1: Dev — VN Team Full Control (current state)

Build everything inside SupplyChain workspace. No external dependencies for dev/test cycle.

```
SupplyChain Workspace (VN team owns)
├── Bronze   → Lakehouse shortcuts (read from EnterpriseData)
├── Silver   → Processing_Warehouse (domain schemas)
├── Gold     → Gold_Warehouse (dedicated, Direct Lake ready)
└── Meta     → Control plane (registry, DQ, lineage, DAG, logging)
```

Rules:
- VN team has full CRUD on all objects — no approval needed per change.
- Naming follows Bob standards from day 1 (pending confirmation on 2 items from ADR-003).
- DQ rules and source contracts are built alongside tables, not retrofitted.

### Phase 2: Promote — 3 distinct targets per Bob's email 2026-05-09

Bob's email 2026-05-09 clarified that promote does NOT mean "everything goes to one place". There are **3 destinations**, each driven by data scope (cross-team vs value-stream-specific):

```
┌─ Cross-team shared masters ──────────────────────────────────┐
│ Calendar / ItemMaster / Warehouse master                     │
│   → EnterpriseData-Dev.MasterData_Warehouse.MasterData_DW    │
│   → Existing Dim* tables (DimDate, DimItemMaster) MERGE/extend │
└──────────────────────────────────────────────────────────────┘

┌─ Cross-team forecast Silver ─────────────────────────────────┐
│ Forecast/Naive Monthly + Actual Demand                       │
│   → EnterpriseData-Dev.SupplyChain_Warehouse (DOES NOT EXIST  │
│     YET — Bob to clarify create-new vs other plan, see Q3)   │
│   Pattern: parallel sibling to Wholesale_Warehouse,          │
│   MasterData_Warehouse                                       │
└──────────────────────────────────────────────────────────────┘

┌─ Value-stream-specific Gold + serving ───────────────────────┐
│ ForecastAccuracy_DW (5 Dim + 2 Fact) + sc_forecast_control_tower │
│   → STAYS IN Enterprise_SupplyChain Dev workspace            │
│   Bob's email: "the gold layer ... in Enterprise_Supplychain's │
│   workspace might have forecast accuracy calculations in     │
│   a semantic model that would only be of value to your team" │
└──────────────────────────────────────────────────────────────┘
```

**Promote checklist (per data product)**:

```
  ✅ DQ rules active, 0 critical failures for 30+ days
  ✅ Source contracts validated (SourceContract + SourceContractRun)
  ✅ Lineage auto-built (LineageEdge complete)
  ✅ Naming convention matches Bob's actual workspace pattern (per ADR-008)
  ✅ Primary keys populated in AssetRegistry
  ✅ TableDictionary registered in EnterpriseData-Dev.ETL_Framework (post-Q1)
  ✅ Column-level documentation in Enterprise Dictionary
  ✅ Rakesh design sign-off
  ✅ PR merged via Azure DevOps Enterprise Data Services repo
```

**Post-promote ownership** (Bob's email 2026-05-09): "The Value Stream squad that builds it needs to take care of it" — VN team continues to own scheduled tasks, SLAs, DQ, alerting after promote.

**Promote mechanism** — per target:

| Target | Mechanism | Owner of execution |
|--------|-----------|---------------------|
| `MasterData_Warehouse.MasterData_DW.*` (existing dims) | MERGE pattern: VN team writes views, MERGE statement; coordinate with `MasterData_DW` schema owner | VN write, Bob's team approve |
| `SupplyChain_Warehouse` (new in EnterpriseData) | Bob's team creates WH; VN deploys SQL bundle (views + SPs) and meta config | Bob's team create infra, VN populate |
| `Enterprise_SupplyChain Dev` (current — Gold + semantic) | No movement needed — already at right WS | VN owns |

### Portability Assessment

| Component | Portability | Notes |
|---|---|---|
| View definitions (SQL) | 95% copy-paste | Pure SQL, no workspace dependency |
| SP definitions (SQL) | 95% copy-paste | `usp_GenericLoad` is generic |
| Meta config (registry, DQ) | 90% export/import | SELECT → INSERT scripts |
| Lineage edges | 100% auto-rebuild | `usp_BuildLineage` regenerates |
| Pipeline JSON | 50% — needs reconfig | Hardcoded GUIDs: workspaceId, artifactId, pipelineId |
| LinkedService connections | 40% — needs reconfig | Different workspace = different endpoint |
| Cross-DB 3-part naming | 30% — needs reconfig | `Processing_Warehouse.Schema.Table` name changes |

### Open Questions for Bob (post 2026-05-09 reply)

| # | Question | Impact | Urgency | Status |
|---|---|---|---|---|
| 1 | ~~PascalCase columns or snake_case?~~ | — | — | **RESOLVED** 2026-05-04 — PascalCase, ~1,800 cols |
| 2 | ~~Schema suffix `_DW`/`_ENH`/`_WRK`?~~ | — | — | **RESOLVED** 2026-05-04. **Re-aligned 2026-05-10** per ADR-008: `_Enh`/`_Wrk` lowercase casing (matches Bob's actual workspace; `_DW` kept ALL CAPS) |
| 3 | ~~Promote ownership: VN team deploys, or Bob's team deploys?~~ | — | — | **RESOLVED** 2026-05-09 (Bob email): Value-stream squad self-maintains; PRs reviewed by senior (Rakesh/Ankit) before merge |
| 4 | ~~Post-promote maintenance: VN team or US?~~ | — | — | **RESOLVED** 2026-05-09 (Bob email): VN team owns scheduled tasks, SLAs, DQ, alerting |
| 5 | ~~Enterprise WH target name?~~ | — | — | **RESOLVED** 2026-05-09 (Bob email): 3 distinct targets — `MasterData_Warehouse`, new `SupplyChain_Warehouse` (TBC create), `Enterprise_SupplyChain` Gold (existing) |
| 6 | ETL_Framework write permission + AuditLog DDL | Enables cross-DB write from `usp_LogRun` | High | **PENDING Bob Q1** (see `_open_questions_for_bob.md`) |
| 7 | `MasterData_DW.DimDate/DimItemMaster` owner + dependents | Drives MERGE-vs-create-new for promoted dims | High | **PENDING Bob Q2** |
| 8 | `SupplyChain_Warehouse` in EnterpriseData hub — create plan | Blocks forecast Silver promote | High | **PENDING Bob Q3** |
| 9 | Mail.Send admin consent + Azure DevOps `Enterprise Data Services` access + EnterpriseData read access | Unblocks scheduling, CI/CD, audits | Medium | **PENDING Bob/Rakesh push IT (Q4)** |

## Consequences

### Positive

- VN team retains full delivery speed during dev — no approval bottleneck.
- Bob reviews once per data product (not per commit/change).
- Quality is baked in from day 1 (DQ, contracts, lineage) — not a promote-time scramble.
- Framework is metadata-driven — 80%+ of code is portable without modification.
- Phased model reduces risk: if promote requirements change, only Phase 2 adapts.

### Costs and Risks

- Pipeline reconfiguration at promote time is manual (~1-2 day effort per data product).
- ~~If naming convention differs from current (snake_case → PascalCase), migration is significant.~~ **DONE** — full rebuild executed 2026-05-04 (22 tables, 23 views, ~1,800 columns, 7 Gold tables).
- Post-promote ownership must be clearly defined before first promote — ambiguity leads to orphaned data products.
- Cross-DB 3-part naming creates coupling to warehouse names — consider parameterizing.

### Recommended Prep Actions (v2 update 2026-05-10)

1. **Execute ADR-008 alignment** ✅ **Done 2026-05-10** — schema casing `_Enh`/`_Wrk`, view prefix `v_*`, port TableDictionary as TABLE + UpdateLog + AuditLog, enhance `usp_LogRun` v2. Pipeline `pl_sc_master` 30m34s clean run end-to-end. Artifacts: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/artifacts/bob_alignment_2026-05-10/`.
2. **Send Bob reply email** with Q1-Q4 (see `_open_questions_for_bob.md`) — ready, draft at `email_to_bob_ankit_2026-05-10.md`.
3. **Audit MasterData_DW.DimDate/DimItemMaster** column structure vs our `v_DimCalendar`/`v_DimProduct` — prep MERGE plan (needs read access on EnterpriseData-Dev).
4. **Audit Wholesale_Warehouse.SalesHistory_AFI** vs our `SalesHistory_Enh` — check if Staging_Wrk EDW supplements can be retired (ADR-002 EDW Exit pathway).
5. **Audit Source_Data.SupplyChain_Enh** — see if Bronze landing data can replace local Staging_Wrk feeds.
6. **Parameterize pipeline GUIDs** — move workspaceId/artifactId to pipeline parameters for promote portability.
7. **Build export script** `export_data_product.py` to dump all SQL + config for a given project (still TBD).
