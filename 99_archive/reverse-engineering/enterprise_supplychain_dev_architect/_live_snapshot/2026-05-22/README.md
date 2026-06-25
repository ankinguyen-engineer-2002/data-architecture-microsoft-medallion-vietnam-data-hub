# Live Snapshot — 2026-05-22

**Purpose**: Point-in-time backup of live DDL + Meta control plane data on Fabric Warehouses. Use this folder to detect drift, audit changes by other team members, or restore if someone modifies objects directly via Fabric portal.

**Sources scanned**:
- `SupplyChain_Processing_Warehouse` (`c0262cef-b8a7-495f-bccc-53b098c7948c`)
- `SupplyChain_Gold_Warehouse` (`98e2a911-5af9-442e-9cc8-5d8dadb8b762`)

**Scan timestamp**: 2026-05-22 02:45 UTC (= 09:45 VN)
**Method**: Python + pyodbc + `az account get-access-token --resource https://database.windows.net/`. See `/tmp/dump_ddl.py` for the dump script (re-runnable).

## Folder contents

### `processing_wh/`
| File | Content | Count |
|---|---|---|
| `views_ddl.sql` | `OBJECT_DEFINITION()` for every VIEW | 40 views |
| `procs_functions_ddl.sql` | All PROCEDUREs + scalar/inline/table FUNCTIONs | 21 |
| `tables_ddl.sql` | Reconstructed `CREATE TABLE` from `INFORMATION_SCHEMA.COLUMNS` (no PK/FK/index detail) | 55 base tables |

### `gold_wh/`
| File | Content | Count |
|---|---|---|
| `views_ddl.sql` | All Gold view definitions (ForecastAccuracy_DW + InventoryHealth_DW + v_*) | 15 views |
| `procs_functions_ddl.sql` | Gold procs/functions (currently empty — Gold is view-driven) | 0 |
| `tables_ddl.sql` | Gold star schema CREATE TABLE | 15 base tables |

### `meta_data/`
Snapshot of key control plane tables as CSV (full content, every row):

| File | Rows |
|---|---|
| `AssetRegistry.csv` | 51 assets (29 forecast + 22 inventory_health) |
| `DQRule.csv` | 95 rules (post-2026-05-22 cleanup: 5 remapped + 7 deactivated) |
| `LineageEdge.csv` | 105 edges (98 direct + 7 semantic) |
| `SourceFeed.csv` | 52 sources |
| `SilverDagWaveRuntime.csv` | 20 wave assignments |
| `TableDictionary.csv` | 59 Bob-compat schema rows |
| `ReconciliationRule.csv` | 6 rules |
| `AssetAccessPolicy.csv` | 28 policies |

## Notable divergence captured by this snapshot

1. **`ForecastAccuracy_DW.v_DimProduct`** — live diverged from repo `etl/gold_views.sql` on 2026-05-20:
   - Old: `SELECT * FROM Staging_Wrk.ProductEdw` (table dropped)
   - New: 207-col backward-compat view from `ReferenceMaster_Enh.ItemMaster`
   - Full new definition in `gold_wh/views_ddl.sql`

2. **`Staging_Wrk` schema** — 4 BASE TABLES dropped post-EDW-Exit; only 4 VIEWS remain (`v_Codatan`, `v_Comast`, `v_Extord`, `v_Extorit`) pointing to `Enterprise_Lakehouse.Wholesale_Codis_AFI.*`.

3. **DQ rules cleanup 2026-05-22** (captured in `DQRule.csv`):
   - rule_id 5,6,7,8,15 → REMAPPED target from `Staging_Wrk.InvoiceDetailEdw` (mis-routed) → `Staging_Wrk.v_Codatan` / `v_Comast` / `v_Extord` / `v_Extorit`
   - rule_id 1,2,3,4,11,13,14 → DEACTIVATED (target dropped post-EDW-Exit, recreate on Silver targets in next iteration)

## How to re-generate

```bash
# Run from repo root, assumes `az login` is valid
python3 /tmp/dump_ddl.py
```

The script is embedded in the conversation log for 2026-05-22. To re-create:
1. Connect via pyodbc + AAD token
2. Loop through `sys.objects` + `OBJECT_DEFINITION()` for views/procs
3. Loop through `INFORMATION_SCHEMA.COLUMNS` for table DDL reconstruction
4. `SELECT *` from each Meta table → CSV

## Diff detection

To check whether someone modified live objects since this snapshot:

```bash
# 1. Generate new snapshot to a temp folder
mkdir -p /tmp/snap_now
# (modify dump_ddl.py OUT path -> /tmp/snap_now, re-run)

# 2. Diff
diff -r Enterprise_SupplyChain_Dev_architect/_live_snapshot/2026-05-22/ /tmp/snap_now/
```

Any non-zero diff = someone changed the live WH. Investigate with `git log` if the change is also in repo, or check Fabric portal Activity Log.
