# Silver Objects

This layer follows the Enterprise `_Wrk` contract:

- `<Schema>/<TableName>.table.sql` documents the physical final Silver table.
- `<Schema>_Wrk/v_<TableName>.sql` stores the work/source view used by `ETL_Framework`.
- `TableDictionary` rows should target the final schema/table, not the `_Wrk` view.
- Base-schema duplicate `v_*` views are legacy compatibility only.
