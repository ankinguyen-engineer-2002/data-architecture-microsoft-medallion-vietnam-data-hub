# Enterprise ETL Alignment 2026-05-10 — Execution Pack

> **Status:** ✅ Executed end-to-end · See [`RESULTS.md`](RESULTS.md) for headline metrics.

Purpose: align v10 naming + metadata layer with Enterprise ETL's actual `EnterpriseData-Dev` workspace pattern (scanned via `_external_refs/enterprisedata-dev-01_docs/`, gitignored).

Trigger: Enterprise ETL's reply email 2026-05-09 to Aric's email 2026-05-05 → ADR-008.

## Scope

| Change | Old | New | Affected objects |
|--------|-----|-----|------------------|
| Schema casing | `*_ENH` (5 schemas) | `*_Enh` | `ReferenceMaster_Enh`, `SalesHistory_Enh`, `ForecastHistory_Enh`, `OpenOrderHistory_Enh` |
| Schema casing | `Staging_WRK` | `Staging_Wrk` | (above) |
| View prefix | `vw_*` (35 + 4 Meta = 39 total) | `v_*` | 28 Processing + 7 Gold + 4 Meta utility views |
| TableDictionary | n/a (was placeholder view) | TABLE 69 cols (63 Enterprise ETL + 6 VN) | `Meta.TableDictionary` |
| TableDictionary_UpdateLog | n/a | TABLE (event log mirror Enterprise ETL's pattern) | `Meta.TableDictionary_UpdateLog` |
| AuditLog | n/a | TABLE 10 cols (4 Enterprise ETL + 6 VN) | `Meta.AuditLog` |
| usp_LogRun | v1 (RunLog only) | v2 (5-sink chain incl. AuditLog + TableDictionary) | `Meta.usp_LogRun` |
| TableDictionary helper procs | n/a | 3 ported from Enterprise ETL | `Meta.usp_UpdateTableDictionary_ModifiedDate`, `Meta.usp_UpdateTableDictionaryModified`, `Meta.usp_RefreshTableStats` |
| AssetRegistry | physical_schema = `*_ENH` + legacy_view_name = old | new naming everywhere (33 rows) | All registry-driven cols |

## NOT in scope

- Gold WH `ForecastAccuracy_DW` — `_DW` suffix kept ALL CAPS (matches Enterprise ETL's `MasterData_DW`)
- Data — 423M rows preserved end-to-end via `ALTER SCHEMA TRANSFER` (non-destructive)
- Semantic model `sc_forecast_control_tower` — references Gold (unchanged)
- v8 legacy (Cherry's `SCP_Core/_Wrk/test_sp`) — FORBIDDEN per Aric directive
- Cross-DB integration to `ETL_Framework.DW_Developer.*` — pending Enterprise ETL Q1 (locally cloned to enable easy switch)

## Scripts (executed in order)

| # | Script | Purpose | Risk |
|---|--------|---------|------|
| 01 | `01_create_new_schemas.sql` | CREATE 5 new lowercase-suffix schemas | Low |
| 02 | `02_transfer_tables.sql` | ALTER SCHEMA TRANSFER 22 tables (non-destructive) | Low |
| 03 | `03_drop_old_views.sql` | DROP 28 Processing views in old schemas | Medium |
| 04 | `04_create_renamed_views_processing.sql` | CREATE 28 views with new schema + `v_` prefix | Low |
| 05 | `05_drop_old_gold_views.sql` | DROP 7 Gold views | Medium |
| 06 | `06_create_renamed_views_gold.sql` | CREATE 7 Gold views with `v_` prefix | Low |
| 07 | `07_drop_recreate_sps.sql` | DROP + CREATE Meta SPs with new refs | Medium |
| 08 | `08_update_asset_registry.sql` | UPDATE physical_schema in AssetRegistry/DQRule/LineageEdge | Low |
| 09 | `09_drop_empty_old_schemas.sql` | DROP 5 empty old `*_ENH/_WRK` schemas | Medium |
| 10 | `10_extend_table_dictionary.sql` | (Mức 1) Initial 65-col view shim | Low |
| 11 | `11_create_audit_log.sql` | CREATE `Meta.AuditLog` | Low |
| 12 | `12_enhance_usp_logrun.sql` | usp_LogRun v2 (write AuditLog) | Low |
| 13 | `13_update_pipeline_sql_refs.md` | Manual checklist — pipeline activity SQL refs (executed via Fabric REST in `run_alignment.py` extension) | Medium |
| 14 | `14_tabledictionary_table_seed.sql` | (Mức B) Convert to real TABLE + UpdateLog table + initial seed | Low |
| 15 | `15_tabledictionary_procs.sql` | Port 3 procs from Enterprise ETL: ModifiedDate, Modified batch sync, RefreshStats | Low |
| 16 | `16_usp_logrun_v2.sql` | usp_LogRun final — chains to TableDictionary update | Low |
| 17 | `17_enrich_tabledictionary.sql` | Fill derivable cols (CreatedBy, UpdateQuery, SourceDatabase, Fabric defaults) | Low |

Plus runtime patches not in SQL scripts (executed inline via Python):
- 4 Meta views renamed `vw_*` → `v_*` (AccessDecision, RegistryCompat, SilverWaveRuntime, sp_registry)
- AssetRegistry `legacy_view_name`/`legacy_sp_name`/`legacy_target_schema` updated (77 rows)
- DQRule `target_table` renamed (`vw_*` → `v_*`)
- `Staging_WRK.usp_RefreshEdwTables` migrated to `Staging_Wrk` schema
- 2 pipelines patched via Fabric REST API (`pl_sc_staging`, `pl_sc_silver_wave`)
- `Meta.TableDictionary` enriched per row from client-side INFORMATION_SCHEMA probe

## How it ran (4 attempts to find all gaps)

| Attempt | Job ID | Result | Gap discovered |
|---------|--------|--------|-----------------|
| #1 | `b628e27c-…` | Failed | 4 Meta views unrenamed |
| #2 | `904da38d-…` | Cancelled | AssetRegistry legacy_view_name pointed to old `vw_*` |
| #3 | `e0f715ae-…` | Failed at exec_gold | DROP-then-CTAS in usp_GenericLoad lost `Warehouse` table during retries |
| #4 | `d2ade935-…` | **✅ Completed 30m 34s, 16/16 success** | — clean run |

## Re-run

```bash
# Re-generate SQL scripts from etl/*.sql sources
python3 generate_scripts.py

# Execute in order (requires az login)
python3 run_alignment.py backup        # snapshot pre-state
python3 run_alignment.py step 1        # ... step 14, 15, 16, 17
python3 run_alignment.py verify        # row count parity check

# Apply naming transforms to v10 forecast docs
python3 update_v10_docs.py
```

## Rollback

Each step has a paired reversal. Worst case: restore from `backup/pre_state_*.json`.

- Steps 01-09 reversal: re-create old schemas, ALTER SCHEMA TRANSFER reverse, restore views from `etl/*.sql` (pre-rename copies via git)
- Steps 14-17 reversal: DROP TABLE Meta.TableDictionary{,_UpdateLog,AuditLog}, restore old `vw_TableDictionary` from step 10 SQL

## ADR cross-refs

- [ADR-005 v2](../../../docs/decisions/ADR-005-enterprise-promote-pathway.md) — Enterprise Promote Pathway
- [ADR-008](../../../docs/decisions/ADR-008-enterprise_etl-alignment-naming-and-integration.md) — Enterprise ETL Alignment (this work)
- [Open questions](../../projects/forecast/_open_questions_for_enterprise_etl.md) — 4 questions pending Enterprise ETL
- Workspace topology: `~/.claude/projects/.../memory/project_workspace_topology.md`
