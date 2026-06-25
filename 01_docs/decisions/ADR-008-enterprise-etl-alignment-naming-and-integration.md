# ADR-008: Enterprise ETL Alignment — Final Naming Convention + ETL_Framework Integration

Date: 2026-05-10
Status: **Implemented** (D1-D6 executed 2026-05-10, end-to-end pipeline verified) · D7-D9 pending Enterprise ETL reply

## Context

After Enterprise ETL's reply email 2026-05-09 (response to Aric's email 2026-05-05) and a comprehensive scan of Enterprise ETL's `EnterpriseData-Dev` workspace via repo `99_archive/external_refs/_external_refs/enterprisedata-dev-01_docs/` (cloned 2026-05-10), we have evidence-based clarity on Enterprise ETL's actual Fabric naming and ETL framework patterns.

**Key evidence from Enterprise ETL's workspace** (workspace ID `5360a935-1984-4775-895f-f4c90bafa19d`):
- 11 WHs, 5 LHs, 192 stored procs, 145 views, 22 pipelines
- Schema suffix `_Enh` exists in 7+ schemas (e.g., `Source_Data.SupplyChain_Enh`, `Retail_Warehouse.MasterData_HR_UKG_Enh`, `Retail_Warehouse.Retail_Sales_Enh`) — **contradicts Enterprise ETL's email hedge "I'm not sure those ENH suffixes are needed in Fabric"**
- Schema suffix `_Wrk` (working set) used widely (`SalesHistory_AFI_Wrk`, `Retail_Sales_Wrk`)
- Schema suffix `_DW` (ALL CAPS) used for dim/fact patterns (`MasterData_DW`, `Source_Data.SupplyChain_DW`)
- View prefix `v_*` (lowercase, single char) — never `vw_*`
- Table casing PascalCase, columns PascalCase, Dim/Fact prefix
- Control plane `ETL_Framework.DW_Developer.TableDictionary` (65 cols) + `AuditLog` (4 cols observed)
- Pattern: every loader proc INSERTs `AuditLog` + UPDATEs `TableDictionary.Modified/RowCount`

## Decisions

### D1 — Schema casing alignment (UNILATERAL — no Enterprise ETL block)

| Old (v10 2026-05-04 build) | New (Enterprise ETL alignment) | Rationale |
|----------------------------|---------------------|-----------|
| `Staging_WRK` | `Staging_Wrk` | Match Enterprise ETL's `_Wrk` casing |
| `ReferenceMaster_ENH` | `ReferenceMaster_Enh` | Match Enterprise ETL's `_Enh` casing |
| `SalesHistory_ENH` | `SalesHistory_Enh` | Same |
| `ForecastHistory_ENH` | `ForecastHistory_Enh` | Same |
| `OpenOrderHistory_ENH` | `OpenOrderHistory_Enh` | Same |
| `ForecastAccuracy_DW` (Gold) | `ForecastAccuracy_DW` (kept) | Enterprise ETL uses `_DW` ALL CAPS — no change needed |
| `Meta` | `Meta` (kept) | Internal control plane, no suffix per Enterprise ETL's `DW_Developer` precedent |

**This is non-destructive**: `ALTER SCHEMA TRANSFER` preserves all data. 22 tables transferred; 28 + 7 = 35 views recreated; SPs recreated; AssetRegistry/DQRule/LineageEdge UPDATE only the `physical_schema` column.

### D2 — View prefix alignment (UNILATERAL)

`vw_*` → `v_*` for all 35 views (28 Processing + 7 Gold). Enterprise ETL's workspace uses `v_*` exclusively (e.g., `v_InvoiceDetail`, `v_Employees`, `v_OpenOrderAddress`).

### D3 — Local TableDictionary expansion (UNILATERAL)

Extend `Meta.vw_TableDictionary` from current 14-col abstraction to **65-col schema matching Enterprise ETL's `ETL_Framework.DW_Developer.TableDictionary`** exactly. Mapping derived from Enterprise ETL's observed sample row + scan of 65-col reference.

This is a view definition change only — sources still come from `Meta.AssetRegistry` (no new tables). All 65 cols are populated either from registry data or `NULL`/default values matching Enterprise ETL's pattern.

Benefit: when Enterprise ETL grants ETL_Framework write (Q1 reply), the cross-DB INSERT/UPDATE statements need zero schema translation.

### D4 — Local AuditLog clone (UNILATERAL)

Create `Meta.AuditLog` table with schema cloning Enterprise ETL's `ETL_Framework.DW_Developer.AuditLog`:

```
AuditID         BIGINT
AuditDateTime   DATETIME2(6)
UserName        VARCHAR(200)
Command         VARCHAR(8000)
Description     VARCHAR(8000)
ErrorMessage    VARCHAR(8000)   -- VN extension
AssetID         VARCHAR(128)    -- VN extension (link to AssetRegistry)
RunID           VARCHAR(128)    -- VN extension (link to RunLog)
Severity        VARCHAR(20)     -- VN extension
LoadDT          DATETIME2(6)
```

Phase 1: local writes from `Meta.usp_LogRun`. Phase 2 (post-Enterprise ETL): cross-DB INSERT to Enterprise ETL's AuditLog.

`Meta.usp_LogRun` enhanced to INSERT into `Meta.AuditLog` after each non-running status transition.

### D5 — `_DW` Gold schema casing (UNILATERAL — no change)

Enterprise ETL's `MasterData_DW`, `Source_Data.SupplyChain_DW` use ALL CAPS `_DW`. Our `ForecastAccuracy_DW` already matches. Do nothing.

### D6 — AI feature store proposal dropped (UNILATERAL)

Per Enterprise ETL: "AI projects ... will need to hit Semantic Models. Semantic Models hold the calculations, relationships, and content that AI needs". Drop `*_FS` proposal from roadmap docs. Plan: enrich `sc_forecast_control_tower` with measure descriptions/business glossary instead.

### D7 — Cross-DB integration to ETL_Framework (PENDING Enterprise ETL Q1)

Once Enterprise ETL confirms write permission + AuditLog DDL:
- `Meta.usp_LogRun` extends to also UPDATE `EnterpriseData-Dev.ETL_Framework.DW_Developer.TableDictionary` (Modified, RowCount, LastAudit) per asset
- INSERT row to `EnterpriseData-Dev.ETL_Framework.DW_Developer.AuditLog` on error/completion

Tracking: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/projects/forecast/_open_questions_for_enterprise_etl.md` Q1.

### D8 — MERGE/extend strategy for `MasterData_DW.DimDate/DimItemMaster` (PENDING Enterprise ETL Q2)

Enterprise ETL's `MasterData_Warehouse.MasterData_DW` already has `DimDate`, `DimItemMaster`, `DimRetailLocations`, `DimTime`. Our `vw_DimCalendar` (75 cols) and `vw_DimProduct` should MERGE into existing tables, not duplicate. Pending Enterprise ETL's confirmation of owner + dependents.

### D9 — `SupplyChain_Warehouse` in EnterpriseData hub (PENDING Enterprise ETL Q3)

Enterprise ETL's hub does NOT have `SupplyChain_Warehouse`. Enterprise ETL's email implies one should exist. Cannot promote forecast Silver until Enterprise ETL clarifies plan (create new sibling vs alternate).

## Consequences

### Positive

- Naming aligned to Enterprise ETL's actual workspace patterns (evidence-based, not opinion-based)
- TableDictionary + AuditLog locally cloned → frictionless integration when Enterprise ETL unblocks
- AI roadmap simplified (semantic model only, no feature store)
- VN team retains full delivery autonomy on naming + style decisions
- No data movement, no semantic model break, no Gold WH change

### Costs

- ~4 days technical work (rename + view recreate + metadata extension)
- 1 round-trip email with Enterprise ETL (24-48h) for Q1/Q2/Q3
- Pipeline activity SQL must be updated post-rename (manual, ~2h)
- ADR-003 status remains "Resolved" but with clarifying note: naming convention evolved to lowercase suffix per Enterprise ETL's actual workspace

### Risks

- If Enterprise ETL explicitly contradicts D1-D6 in reply (low probability — evidence-based decisions), partial rebuild
- Cross-DB write to ETL_Framework requires Fabric workspace federation that may not be supported under current capacity SKU — needs verification

## Implementation

Artifacts: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/artifacts/enterprise_etl_alignment_2026-05-10/`
- `README.md` — execution plan with 13 steps
- `generate_scripts.py` — Python generator (read existing DDL → transform → write)
- `sql_scripts/01..12.sql` + `13_update_pipeline_sql_refs.md`

Execution status:
- [x] Doc artifacts: open questions, ADR-008, ADR-005 v2 update
- [x] Generator script + 17 SQL scripts written
- [x] Pre-flight: backup AssetRegistry/DQRule/LineageEdge to JSON (`backup/pre_state_20260510_132309.json`)
- [x] Steps 01-09: schema rename + view recreate (22 tables transferred non-destructively, 35 views recreated)
- [x] Steps 10-12: AuditLog + extended TableDictionary view + usp_LogRun v2
- [x] Steps 14-17 (Mức B port): TableDictionary as TABLE + UpdateLog + 3 procs ported from Enterprise ETL
- [x] Pipeline activity SQL refs patched (2 of 7 pipelines via Fabric REST)
- [x] Meta views renamed `vw_*` → `v_*` (4 views: AccessDecision, RegistryCompat, SilverWaveRuntime, sp_registry)
- [x] AssetRegistry registry-driven cols updated (legacy_view_name, legacy_sp_name, legacy_target_schema)
- [x] Smoke run `pl_sc_master` end-to-end → 30m 34s, 16/16 success, 423M rows preserved (2026-05-10 09:49 UTC, job `d2ade935-22ac-411d-9551-3b491c353db4`)
- [x] Auto-update chain verified: AuditLog (110 rows), UpdateLog (28 rows), TableDictionary deferred sync (11 rows refreshed)
- [ ] Send email to Enterprise ETL with Q1/Q2/Q3/Q4 (D7/D8/D9 + IT unblock)

## References

- Enterprise ETL's reply email 2026-05-09 (in `email_to_enterprise_etl_ankit_2026-05-05.md` thread)
- Enterprise ETL's workspace scan: `99_archive/external_refs/_external_refs/enterprisedata-dev-01_docs/` (cloned 2026-05-10, gitignored)
- Enterprise ETL's DOCX: `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/SQL Server Data Warehouse Standards.docx` (local-only, gitignored)
- ADR-003 — Enterprise ETL Standards Compliance Audit (2026-05-04, status Resolved — superseded for casing only)
- ADR-005 — Enterprise Promote Pathway (v2 update concurrent with this ADR)
- Memory: `project_workspace_topology.md` (2 workspaces, not 3)
- Memory: `project_v10_architecture.md`
