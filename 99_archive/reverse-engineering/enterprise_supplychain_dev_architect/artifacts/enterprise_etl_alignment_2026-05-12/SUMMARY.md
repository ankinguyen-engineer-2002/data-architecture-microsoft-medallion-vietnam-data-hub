# Enterprise ETL alignment — Post-rebuild case drift cleanup (2026-05-12)

## Why

The Enterprise ETL alignment rebuild on 2026-05-04 renamed schema containers
`_ENH` → `_Enh` and `_WRK` → `_Wrk` (PascalCase per ADR-008). DDL (tables/views/SPs)
and pipeline definitions were rewritten with new casing, BUT 8 Meta tables
holding asset_id text references were not cascaded — leaving the logical key
out of sync with the physical schema.

Discovered 2026-05-12 while investigating `lineage_explorer/data/lineage.csv`
showing UPPERCASE schema labels long after the rename.

## What was fixed

Two SQL passes via pyodbc (`/tmp/fix_case_cascade.py` + `/tmp/fix_depends_on.py`):

| Pass | Tables/Columns | Rows updated |
|------|---------------|--------------|
| 1 (cascade) | AssetRegistry.asset_id, RunLog.asset_id+object_name, ReconciliationRule.asset_id, SourceFeed.asset_id, AuditLog.AssetID | 761 |
| 2 (depends_on) | AssetRegistry.depends_on (JSON text) | 7 |
| Rebuild | EXEC Meta.usp_BuildLineage + Meta.usp_ComputeSilverWaves | LineageEdge 60 (53 direct + 7 semantic), SilverDagWaveRuntime 8 entries (waves 0/1/2) |

Final verify: 15 audit columns × 0 UPPERCASE = fully clean.

## Side effects

- `usp_ComputeSilverWaves` correctly recomputed max wave from 1 → 2
  (DAG was previously broken because `depends_on` didn't match `asset_id`)
- GH Action workflow_dispatch run 25711670159 + 25712090xxx auto-refreshed
  `lineage_explorer/data/{lineage,registry}.csv` with new PascalCase strings
- Streamlit app `https://sc-lineage.streamlit.app/` now renders consistent
  PascalCase schema labels across all tabs

## Code changes committed

- `lineage_explorer/app.py` — `endswith` case-insensitive (forward-compatible
  if any future rename happens)
- `Enterprise_SupplyChain_Dev_architect/05_tools/stability_scan.py` — SQL
  filter `LOWER(s.name) LIKE '%[_]enh'` + NEW_SCHEMAS set to PascalCase

## Validated clean (post-fix, 2026-05-12)

- 7/7 v10 pipeline definitions: zero `_ENH/_WRK` (already aligned at rebuild)
- All deployed SP/view/function DDL in Processing + Gold WH: zero `_ENH/_WRK`
- All source .sql files: zero `_ENH/_WRK`
- 8 Meta tables, 15 audit columns: zero UPPERCASE remaining

## Backup snapshots (gitignored — local only)

- `lineage_case_fix_20260512_031550/` — AssetRegistry + LineageEdge BEFORE/AFTER
- `case_cascade_fix_20260512_033149/` — 5 Meta tables BEFORE/AFTER

Backups can be replayed if rollback needed by re-importing CSVs to AssetRegistry.

## Lesson learned

Future schema-rename refactors must also UPDATE every text column referencing
the schema name (asset_id, depends_on, source_objects, RunLog history, audit log).
The Enterprise ETL alignment rebuild script SHOULD have included this cascade. Consider
adding a post-rebuild verification script that scans all Meta.* text columns
for legacy schema names.
