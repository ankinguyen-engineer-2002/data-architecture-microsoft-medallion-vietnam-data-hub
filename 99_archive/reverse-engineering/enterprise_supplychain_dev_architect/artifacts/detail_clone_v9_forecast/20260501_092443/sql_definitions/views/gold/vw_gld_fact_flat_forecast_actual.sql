-- Source: SupplyChain_Warehouse.gold.vw_gld_fact_flat_forecast_actual
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW gold.vw_gld_fact_flat_forecast_actual AS

/* ── Actual Demand ── */
SELECT
    id_item_sku,
    code_warehouse,
    code_customer_group,
    dt_fsc_month_first,
    dt_fsc_month_last,
    CAST('Actual demand' AS VARCHAR(20)) AS code_horizon,
    code_status,
    name_version,
    CAST(qty_demand AS FLOAT) AS qty
FROM silver.slv_actual_demand_monthly

UNION ALL

/* ── Forecast Demand ── */
SELECT
    id_item_sku,
    code_warehouse,
    code_customer_group,
    dt_fsc_month_first,
    dt_fsc_month_last,
    code_horizon,
    code_status,
    code_version AS name_version,
    CAST(qty_forecast AS FLOAT) AS qty
FROM silver.slv_forecast_demand_monthly

UNION ALL

/* ── Naive Forecast ── */
SELECT
    id_item_sku,
    code_warehouse,
    code_customer_group,
    dt_fsc_month_first,
    dt_fsc_month_last,
    CAST('Naive forecast' AS VARCHAR(20)) AS code_horizon,
    code_status,
    name_version,
    CAST(qty_demand AS FLOAT) AS qty
FROM silver.slv_naive_forecast_monthly
