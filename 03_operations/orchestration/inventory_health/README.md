# Inventory Health Orchestration

Use this when Aric asks to refresh only Inventory Health.

Current run order:

1. Silver waves (1, 2, 3, ...)
2. Gold waves (`gold_shared` -> `gold_dim` -> `gold_helper` -> `gold_fact`)
3. post-run smoke

Live REST mart-level execution through `pl_sc_mart(project_name)` is marked [Need-verify] until a parameterized API call is smoke-tested. Dry-run is always safe.

Wrapper stored procedures (SQL Agent / external scheduler):

- Active mart wrapper order lives in `manifest.json` under `wrapper_procedures`.
- The mart has exactly three active Silver wrappers: W01 then W02 then W03, followed by Gold.
- `Usp_Refresh_InventoryHealth_Silver_W01` is the first inventory source wave.
- `Usp_Refresh_InventoryHealth_Gold` includes the internal `gold_shared` phase for `Shared_DW` dimensions.
- Wrapper DDL lives under `sql/`.
- Default dry-run printer:
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/inventory_health/manifest.json`

Enterprise `_Wrk` contract:

- Orchestration targets final physical tables.
- `ETL_Framework` derives the source view as `<target_schema>_Wrk.v_<target_table>`.
- Base-schema `v_*` views have been removed from active Silver/Gold curated schemas and must not be referenced.
