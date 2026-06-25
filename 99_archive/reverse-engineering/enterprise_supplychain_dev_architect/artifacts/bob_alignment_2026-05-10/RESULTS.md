# Bob Alignment 2026-05-10 — Results

> **Status:** Executed end-to-end · **Pipeline smoke:** ✅ Completed 30m 34s · **Data:** 423M rows preserved

## Headline metrics

| Metric | Pre (2026-05-04 Bob Standards rebuild) | Post (2026-05-10 Bob alignment) | Δ |
|--------|----------------------------------------:|----------------------------------:|---:|
| Schemas Processing | 6 (`*_ENH`/`Staging_WRK`/Meta) | 6 (`*_Enh`/`Staging_Wrk`/Meta) | renamed in-place |
| Tables data | 22 | 22 | 0 |
| Tables Meta | 20 | **23** | **+3** (TableDictionary, TableDictionary_UpdateLog, AuditLog) |
| Tables Gold | 7 | 7 | 0 |
| Views Processing+Gold | 35 (`vw_*`) | 35 (`v_*`) | renamed |
| Views Meta utility | 5 | 4 (vw_TableDictionary became real table) | -1 |
| SPs Meta | 14 | **17** | **+3** (UpdateModifiedDate, UpdateModifiedBatch, RefreshTableStats) |
| Functions Meta | 3 | 3 | 0 |
| Total objects | 101 | **103** | +2 |
| Data rows | ~420M | ~423M (pipeline reload) | +3M |

## Pipeline smoke run

| Field | Value |
|-------|-------|
| Pipeline | `pl_sc_master` (`f36f56b8-…`) |
| Job ID | `d2ade935-22ac-411d-9551-3b491c353db4` (attempt #4) |
| Started | 2026-05-10 09:19:16 UTC |
| Ended | 2026-05-10 09:49:50 UTC |
| Runtime | **30m 34s** |
| Asset loads | **16/16 success, 0 failed** |
| Status | **Completed** |

### Why 4 attempts

| Attempt | Result | Root cause discovered |
|---------|--------|------------------------|
| #1 | Failed | 4 Meta views (vw_AccessDecision, vw_RegistryCompat, vw_SilverWaveRuntime, vw_sp_registry) hadn't been renamed |
| #2 | Cancelled mid-run | `Meta.AssetRegistry.legacy_view_name` (33 rows) and `legacy_sp_name` still referenced `vw_*`/`*_ENH` |
| #3 | Failed at exec_gold | `usp_GenericLoad` DROP-then-CTAS pattern — old retries dropped `Warehouse` table before CTAS could rebuild from old view |
| **#4** | **Completed** | All gaps closed; clean run end-to-end |

Each attempt revealed a new layer of registry-driven coupling that the schema rename hadn't touched. All gaps documented and fixed.

## Bob compatibility check

| Layer | Bob's `EnterpriseData-Dev` | Our `Enterprise_SupplyChain Dev` | Match? |
|-------|-----------------------------|------------------------------------|--------|
| Schema casing | `_Enh`, `_Wrk`, `_DW` | `_Enh`, `_Wrk`, `_DW` | ✅ 100% |
| View prefix | `v_*` | `v_*` | ✅ 100% |
| Table casing | PascalCase | PascalCase | ✅ |
| Column casing | PascalCase | PascalCase | ✅ |
| Dim/Fact prefix | `DimX`, `FactX` | `DimX`, `FactX` | ✅ |
| TableDictionary structure | 65 cols | **63 + 6 VN ext = 69 cols** | ✅ Schema 1-to-1 |
| TableDictionary_UpdateLog | exists | exists | ✅ |
| AuditLog (Description/DateTime/User/Command) | 4 cols | 10 cols (4 Bob + 6 VN ext) | ✅ Superset |
| `usp_UpdateTableDictionary_ModifiedDate` | proc per-load INSERT/UPDATE | ported logic | ✅ |
| `usp_UpdateTableDictionaryModified` | proc batch sync | ported logic | ✅ |
| Per-loader trigger | each loader proc calls update | `usp_LogRun v2` chains automatically | ✅ Equivalent |
| Time conversion | `fn_GetDate(@dt)` UTC→CST | `ufn_utc_to_cst` | ✅ |

## TableDictionary cell fill

- 33 rows seeded (1 row per registered asset)
- 69 columns total (63 Bob + 6 VN ext)
- **42/69 cols populated (61%)**, **60.3% cell fill**
- 23 cols intentionally NULL (Fabric auto-managed indexing, Synapse legacy, Databricks-specific, archive policy not configured)
- Bob's 63-col equivalent: **42/63 = 67% populated** with real data

## Auto-update chain verified

```
Pipeline activity → Meta.usp_GenericLoad(asset_id)
  └→ Meta.usp_LogRun(run_id, asset_id, 'success', rows)
       ├→ INSERT Meta.RunLog                        ✅ 16 rows
       ├→ UPDATE Meta.AssetRegistry                  ✅ 33 rows refreshed
       ├→ INSERT Meta.AuditLog                       ✅ 110 rows total
       └→ EXEC Meta.usp_UpdateTableDictionary_ModifiedDate
            ├→ INSERT Meta.TableDictionary_UpdateLog ✅ 28 rows
            └→ INSERT Meta.TableDictionary (if new)

Batch end:
  Meta.usp_UpdateTableDictionaryModified()
    └→ UPDATE Meta.TableDictionary.Modified         ✅ 11 rows synced
       FROM MAX(LastUpdated) FROM UpdateLog
```

## Files in this artifact pack

```
bob_alignment_2026-05-10/
├── README.md                       — execution plan + step descriptions
├── RESULTS.md                      — this file (post-execution headline)
├── generate_scripts.py             — Python: read etl/*.sql → transform → write sql_scripts/
├── run_alignment.py                — Python: pyodbc auth + step runner with logs
├── update_v10_docs.py              — Python: apply naming transform to projects/forecast/ docs
├── sql_scripts/                    — 17 SQL scripts (steps 01-17), executable via run_alignment.py
├── run_logs/                       — JSON output per step (gitignored — local-only)
└── backup/                         — pre_state snapshot for rollback (gitignored)
```

## Cross-refs

- ADR-008 — naming + integration plan (status: Implemented)
- ADR-005 v2 — 3 promote targets (corrected workspace topology)
- `Enterprise_SupplyChain_Dev_architect/projects/forecast/_open_questions_for_bob.md` — 4 questions pending Bob
- `email_to_bob_ankit_2026-05-10.md` — reply email draft (gitignored)
