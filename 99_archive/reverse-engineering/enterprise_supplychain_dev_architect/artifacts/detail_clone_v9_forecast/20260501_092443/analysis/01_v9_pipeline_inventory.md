# V9 Pipeline Inventory

| Pipeline | Activities | SQL queries | SP activities | Invokes | Smart skip | Project filter |
| --- | --- | --- | --- | --- | --- | --- |
| pl_sc_master | 7 | 1 | 3 | 0 | False | True |
| pl_sc_mart | 3 | 0 | 0 | 0 | False | False |
| pl_sc_bronze | 3 | 1 | 1 | 0 | True | True |
| pl_sc_silver | 4 | 1 | 1 | 0 | False | False |
| pl_sc_silver_wave | 3 | 1 | 1 | 0 | False | False |
| pl_sc_gold | 3 | 1 | 1 | 0 | True | True |
| pl_dq_check | 3 | 1 | 1 | 0 | False | False |

Detailed CSV files:

- `pipeline_activity_summary.csv`
- `pipeline_sql_queries.csv`
- `pipeline_stored_procedures.csv`
- `pipeline_invocations.csv`
- `pipeline_parameters.csv`
