# Inventory Health Source Inputs

This folder keeps Mart B source-of-truth inputs used during DA-first refactor and source readiness review.

| File | Purpose |
|---|---|
| `inventory_health_project_resources_2026-06-02.xlsx` | DA workbook input; includes `Silver_Check` source feedback. |
| `inventory_health_source_kpi_mapping_2026-05-12.xlsx` | Inventory Health source/KPI mapping workbook used by dataflow setup. |
| `inventoryhistory_enh_silver_view_sql_export_2026-06-02.md` | DA SQL export applied to local source and live Fabric views on 2026-05-28. |

These are provenance artifacts, not deployable ETL code. Active ETL definitions remain in `../../etl/`.
