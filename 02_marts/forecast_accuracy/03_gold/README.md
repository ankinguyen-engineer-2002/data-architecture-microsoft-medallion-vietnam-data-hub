# Gold Objects

This layer follows the Enterprise `_Wrk` contract:

- `<Schema>/<TableName>.table.sql` documents the physical final Gold table.
- `<Schema>_Wrk/v_<TableName>.sql` stores the work/source view used by `ETL_Framework`.
- `TableDictionary` rows should target the final schema/table, not the `_Wrk` view.
- Base-schema duplicate `v_*` views are legacy compatibility only.
- `DQForecastAccuracy` is a Gold-side DQ history table. It is loaded by a direct `INSERT ... SELECT` from `_Wrk.v_DQForecastAccuracy` at the tail of the Gold wrapper, outside the generic `ETL_Framework` loader. `DQRunId` (uniqueidentifier) tags each run and `DQRunAtUTC`/`LoadDT` are the run timestamps. The object is included in mart catalog lineage as a terminal Gold DQ history node because it is a live final table even though it is not loaded through `usp_RefreshCuratedTableFromView`.
