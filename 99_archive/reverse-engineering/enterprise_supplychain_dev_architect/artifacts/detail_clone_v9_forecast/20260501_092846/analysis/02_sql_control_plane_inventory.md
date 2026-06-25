# SQL Control Plane Inventory

Primary evidence files:

- `sql/06_sp_registry.csv`
- `sql/08_registry_dependency_map.csv`
- `sql/10_lineage.csv`
- `sql/11_dq_rules.csv`
- `sql/13_dq_results.csv`
- `sql/14_sp_run_history.csv`
- `sql/15_pipeline_run_log.csv`
- `sql/16_slv_dag_waves_runtime.csv`
- `sql/17_table_dictionary.csv`
- `sql/meta_tables/*.csv`
- `sql_definitions/views/*/*.sql`
- `sql_definitions/routines/*/*.sql`

Important: `sql_definitions/tables/*/*.sql` are logical schema snapshots generated from `INFORMATION_SCHEMA.COLUMNS`, not exact physical deployment scripts.
