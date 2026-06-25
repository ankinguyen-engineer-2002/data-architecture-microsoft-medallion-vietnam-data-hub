# V9 Delete Candidates Review

No deletion has been executed.

This is only an inventory of live v9-related objects that may need migration, archive, rename, or delete decisions later. Do not delete anything in this list until Aric approves the exact action in the same conversation.

## Confirmed V9 Pipeline Items

| Pipeline | ID | Action status |
| --- | --- | --- |
| pl_sc_master | 319a8160-3f3a-4b87-8ad6-75ac4f3ec184 | candidate inventory only; no delete approval |
| pl_sc_mart | 9a1e7a12-30ab-465c-a45d-b051619193ac | candidate inventory only; no delete approval |
| pl_sc_bronze | 1bdbaebb-7222-4e9c-a45d-3e632bba846d | candidate inventory only; no delete approval |
| pl_sc_silver | 46437ae6-3a15-4697-957d-f1f44ba10633 | candidate inventory only; no delete approval |
| pl_sc_silver_wave | 57a09720-21a2-49b5-a472-1e19abd14f76 | candidate inventory only; no delete approval |
| pl_sc_gold | 94fc130e-f327-46a9-b7ba-cd2aa328c0da | candidate inventory only; no delete approval |
| pl_dq_check | c32dc18d-d027-4672-9872-f73404cd7c6f | candidate inventory only; no delete approval |

## SQL Objects In V9 Layer Schemas

| Schema | Object | Type | Action status |
| --- | --- | --- | --- |
| bronze | usp_refresh_edw_tables | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| bronze | brz_saleshistory_afi__invoicedetail | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_saleshistory_afi__invoicedetail_edw | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_saleshistory_afi__invoiceheader | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_saleshistory_afi__invoiceheader_edw | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_supplychain_enh_1__demandforecastsnapshotdaily | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_supplychain_enh_1__demandforecastsnapshotdaily_edw | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_wholesale_codis_afi__codatan | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_wholesale_codis_afi__comast | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_wholesale_codis_afi__extord | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | brz_wholesale_codis_afi__extorit | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_calendar | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_customer_account | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_customer_account_group | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_customer_grouping | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_customer_shipping_location | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_forecast_cycle | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_forecast_horizon | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_item_master | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_order_type | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_product | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_product_edw | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | ref_warehouse | USER_TABLE | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_saleshistory_afi__invoicedetail | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_saleshistory_afi__invoiceheader | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_supplychain_enh_1__demandforecastsnapshotdaily | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_wholesale_codis_afi__codatan | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_wholesale_codis_afi__comast | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_wholesale_codis_afi__extord | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_brz_wholesale_codis_afi__extorit | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_calendar | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_customer_account | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_customer_account_group | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_customer_grouping | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_customer_shipping_location | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_forecast_cycle | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_forecast_horizon | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_item_master | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_order_type | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_product | VIEW | inventory-only; do not delete without Aric approval |
| bronze | vw_ref_warehouse | VIEW | inventory-only; do not delete without Aric approval |
| gold | gld_fact_flat_forecast_actual | USER_TABLE | inventory-only; do not delete without Aric approval |
| gold | gld_fact_forecast_kpi | USER_TABLE | inventory-only; do not delete without Aric approval |
| gold | vw_gld_fact_flat_forecast_actual | VIEW | inventory-only; do not delete without Aric approval |
| gold | vw_gld_fact_forecast_kpi | VIEW | inventory-only; do not delete without Aric approval |
| meta | ufn_cron_is_due | SQL_SCALAR_FUNCTION | inventory-only; do not delete without Aric approval |
| meta | ufn_should_run | SQL_SCALAR_FUNCTION | inventory-only; do not delete without Aric approval |
| meta | ufn_utc_to_cst | SQL_SCALAR_FUNCTION | inventory-only; do not delete without Aric approval |
| meta | usp_build_lineage | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_check_dq | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_check_dq_single | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_compute_slv_waves | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_debug_loop | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_finalize_pipeline | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_generic_load | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_log_pipeline_run | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_log_run | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_run_silver_dag | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | usp_validate_schema_contracts | SQL_STORED_PROCEDURE | inventory-only; do not delete without Aric approval |
| meta | dq_results | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | dq_rules | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | performance_baseline | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | pipeline_cost_log | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | pipeline_run_log | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | schema_contracts | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | slv_dag_waves_runtime | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | sp_lineage | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | sp_registry | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | sp_run_history | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | view_definitions | USER_TABLE | inventory-only; do not delete without Aric approval |
| meta | vw_run_history_tz | VIEW | inventory-only; do not delete without Aric approval |
| meta | vw_table_dictionary | VIEW | inventory-only; do not delete without Aric approval |
| silver | slv_actual_demand_monthly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_actual_demand_weekly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_forecast_demand_monthly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_invoice_detail_line_level | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_invoice_weekly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_naive_forecast_monthly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_open_order_line_level | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | slv_open_order_monthly | USER_TABLE | inventory-only; do not delete without Aric approval |
| silver | vw_slv_actual_demand_monthly | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_actual_demand_weekly | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_forecast_demand_monthly | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_invoice_detail_line_level | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_invoice_weekly | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_naive_forecast_monthly | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_open_order_line_level | VIEW | inventory-only; do not delete without Aric approval |
| silver | vw_slv_open_order_monthly | VIEW | inventory-only; do not delete without Aric approval |

## Explicit Do-Not-Touch Boundary

- Do not touch v8/production assets.
- Do not touch non-`pl_sc_*` legacy/notebook pipelines unless separately classified and approved.
- Do not drop `Enterprise_Lakehouse`, shortcuts, semantic models, reports, or any Warehouse until v10 cutover is approved.
