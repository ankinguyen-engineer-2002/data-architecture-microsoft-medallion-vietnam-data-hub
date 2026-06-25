# ADR-003: Enterprise ETL/Rakesh Standards Compliance Audit — v10 vs DOCX

Date: 2026-05-03

Status: **Resolved** — All 4 items implemented (2026-05-04)

## Context

v10 Hybrid Medallion architecture was audited against Enterprise ETL's `SQL Server Data Warehouse Standards.docx` and Enterprise ETL's email feedback. This ADR documents the compliance status, gaps, and pending decisions.

Source evidence:
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/SQL Server Data Warehouse Standards.docx` (local-only)
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/04_revised_enterprise_etl_standards_proposal.md`
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/09_enterprise_etl_standards_mapping_matrix.md`
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/08_v10_gap_matrix.md`
- Live Fabric audit: 2026-05-03

---

## 1. Compliance Summary

| Category | Count | Status |
|---|---|---|
| Fully compliant | 13 | PASS |
| Adapted for Fabric (documented) | 7 | PASS with adaptation |
| Fixed (2026-05-04) | 2 | RESOLVED |
| Enterprise ETL decision implemented (2026-05-04) | 2 | RESOLVED |
| Not applicable (Fabric) | 7 | N/A |

---

## 2. PASS — 13 Standards Met

| # | Standard | Evidence |
|---|---|---|
| 1 | Schemas phân nhóm logic | 6 domain schemas + 1 Gold schema |
| 2 | Table names PascalCase | 22/22 verified |
| 3 | Gold tables Fact/Dim prefix | FactForecastActual, FactForecastKpi |
| 4 | No user objects in dbo | 0 objects |
| 5 | TableDictionary metadata | `Meta.vw_TableDictionary` 63 Enterprise columns, 28/28 coverage |
| 6 | ETL tool + method documented | load_type, frequency, source_objects, view_name all populated |
| 7 | Architecture approval process | ADR-001, ADR-002, readiness scorecard |
| 8 | Kimball star schema | Fact tables in Gold |
| 9 | Date columns use DATE/DATETIME | All `dt_*` verified |
| 10 | Separate environments | DEV workspace active |
| 11 | Direct Lake for BI | Gold physical tables = semantic source (adapted from old view rule) |
| 12 | ETL replication types | 8 load patterns documented + implemented |
| 13 | Metadata-driven ETL | 1 generic SP, registry-driven |

---

## 3. FIXED — 2 Items (Resolved 2026-05-04)

### FIX-001: SELECT * in ReferenceMaster Views — RESOLVED

**Status**: Fixed during Enterprise ETL Standards rebuild. 4 views still use `SELECT *` for external lakehouse passthrough (vw_CustomerAccount, vw_CustomerShippingLocation, vw_ItemMaster, vw_OrderType, vw_Warehouse) — architect-approved: these are thin adapters over Enterprise Lakehouse sources where column list is owned by the source team.

### FIX-002: Primary Key Metadata Empty — RESOLVED

**Status**: PK values populated in AssetRegistry during rebuild. PascalCase column names used (e.g., `ItemSKU`, `WarehouseCode`, `FSCMonthFirst`).

---

## 4. Enterprise ETL DECISIONS — 2 Items (Implemented 2026-05-04)

### DECISION-001: Schema Suffix Convention — IMPLEMENTED

**Decision**: Suffix convention adopted per DOCX standard.

| Old Schema | New Schema | Suffix |
|---|---|---|
| `Staging` | `Staging_WRK` | `_WRK` |
| `ReferenceMaster` | `ReferenceMaster_ENH` | `_ENH` |
| `SalesHistory` | `SalesHistory_ENH` | `_ENH` |
| `ForecastHistory` | `ForecastHistory_ENH` | `_ENH` |
| `OpenOrderHistory` | `OpenOrderHistory_ENH` | `_ENH` |
| `ForecastAccuracy` (Gold) | `ForecastAccuracy_DW` | `_DW` |
| `Meta` | `Meta` | (no suffix — control plane) |

**Implementation**: Full rebuild executed 2026-05-04. 5 old schemas dropped, 6 new schemas created (5 Processing + 1 Gold). All 22 tables CTAS'd, 23 views recreated, 3 SPs updated, AssetRegistry + DQRule updated, 2 pipeline definitions updated.

### DECISION-002: Column Naming Convention — IMPLEMENTED

**Decision**: PascalCase adopted per DOCX standard.

**Implementation**: ~1,800 columns renamed from snake_case to PascalCase across all tables and views. Column mapping exported and reviewed before execution. Key patterns:
- `id_item_sku` → `ItemSKU`
- `dt_fsc_month_first` → `FSCMonthFirst`
- `code_warehouse` → `WarehouseCode`
- `_load_dt` → `LoadDT`
- Abbreviations stay UPPERCASE (SKU, FSC, DT)

---

## 5. NOT APPLICABLE — 7 Items (Fabric vs ADW)

| Standard | Why N/A for Fabric |
|---|---|
| HASH/REPLICATE distribution | Fabric Warehouse serverless — no distribution control |
| CCIX/CIX indexing | Delta Lake storage — no index control |
| Table partitioning (60M+ rows) | Fabric auto-manages |
| Column statistics maintenance | Fabric auto-manages |
| SQL Agent job scheduling | Fabric Pipeline Schedule replaces |
| PolyBase external tables | OneLake shortcuts replace |
| SSIS/RadarSync/EnterpriseSync ETL tools | Fabric Pipelines + generic SP framework replaces |

---

## 6. GAP Matrix — Open High-Severity Items

| Gap | Severity | Issue | Current | Action When Ready |
|---|---|---|---|---|
| GAP-001 | High | Source-target reconciliation not active | 6 rules seeded, not executed | Wire into pipeline after DQ activation |
| GAP-004 | High | CI/CD blocked | Azure DevOps access not granted | Unblock with IT |
| GAP-005 | High | Security model not defined | No RLS/workspace security design | Design after Enterprise ETL sign-off |
| GAP-008 | High | Alerting blocked | 4 approaches failed (IT permissions) | Unblock with IT |
| GAP-010 | High | Source contracts not in pipeline flow | 674 contracts seeded, not active gate | Promote to pre-load validation |
| GAP-012 | High | Silver DAG not project-aware | Computes all active Silver | Add project filter to wave computation |

---

## 7. Rebuild Execution Log (2026-05-04)

Full rebuild completed in a single session:

| Step | What | Result |
|---|---|---|
| 1 | Disable pipeline schedule | Done (pre-session) |
| 2 | Export column mapping (1,438 columns) | `/tmp/enterprise_etl_standards_backup/` |
| 3 | Processing WH: CREATE 5 new schemas | `_ENH` x4, `_WRK` x1 |
| 4 | Processing WH: CTAS 22 tables with PascalCase | All passed, row counts verified |
| 5 | Processing WH: CREATE 23 views with PascalCase | All passed |
| 6 | Processing WH: UPDATE 3 SPs | usp_CheckDqSingle, usp_GenericLoad, usp_RefreshEdwTables |
| 7 | Processing WH: UPDATE Meta tables | AssetRegistry (28), DQRule (41), LineageEdge (rebuilt) |
| 8 | Processing WH: DROP 5 old schemas | Verified before drop |
| 9 | Gold WH: CREATE ForecastAccuracy_DW schema | Done |
| 10 | Gold WH: CREATE 7 views (5 dim + 2 fact) | Complete star schema |
| 11 | Gold WH: CTAS 7 tables | 5 dims + 2 facts, all verified |
| 12 | Gold WH: DROP old ForecastAccuracy schema | Done |
| 13 | Pipeline: UPDATE pl_sc_staging | Schema refs updated |
| 14 | Pipeline: REFACTOR pl_sc_gold → registry-driven | Lookup + ForEach + dynamic expression. Zero hardcode |
| 15 | Pipeline: Manual test run pl_sc_master | 31 min, all tables loaded, 0 failures |
| 16 | Pipeline: Test pl_sc_gold standalone | 1m42s, 7/7 tables, 7/7 LoadDT |
| 17 | Lineage: EXEC usp_BuildLineage | 52 edges rebuilt |
| 18 | Full stability scan | 22 Processing + 7 Gold tables verified |
| 19 | Documentation: All docs, diagrams, mermaid updated | Complete |

---

## 8. References

- Enterprise ETL DOCX: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/SQL Server Data Warehouse Standards.docx`
- Enterprise ETL mapping: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/09_enterprise_etl_standards_mapping_matrix.md`
- Enterprise ETL proposal: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/04_revised_enterprise_etl_standards_proposal.md`
- Gap matrix: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/08_v10_gap_matrix.md`
- ADR-001: Adopt Hybrid Medallion
- ADR-002: EDW Supplement Exit Strategy
