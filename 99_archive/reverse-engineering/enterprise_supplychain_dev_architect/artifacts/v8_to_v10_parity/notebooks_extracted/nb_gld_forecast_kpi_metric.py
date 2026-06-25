# ─── Cell 0 ───
# ============================================================================
# [GLD] nb_gld_forecast_kpi_metric
# Gold: Forecast Accuracy KPI (error metrics + horizon analysis)
#
# Sources:
#   - slv_forecast_demand_monthly (forecast at snapshots)
#   - slv_actual_demand_monthly (actual demand)
#   - slv_naive_forecast_monthly (naive forecast baseline)
#
# Transformations:
#   - 4 CTEs: forecast, actuals, naive, spine (UNION of all dimension keys)
#   - Spine LEFT JOINs to forecast, actuals, naive
#   - Full coverage of all item × warehouse × customer × month combinations
#
# FIXES:
#   1. UPPER() on id_item_sku, code_warehouse, code_customer_group
#      to prevent case-sensitive splits (e.g. AFICONS vs AFICONs).
#   2. Null-safe equality (=) on all JOIN conditions
#      to handle NULL in code_customer_group.
#
# Load Type: overwrite (full reload every run)
# ============================================================================

TARGET_TABLE = 'gld_forecast_kpi_metric'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_AGGREGATE = f'''
WITH
/* ── Forecast: aggregate by snapshot × SKU × WH × CustGroup × FiscalMonth ── */
forecast AS (
    SELECT
        UPPER(TRIM(DFC.id_item_sku))          AS id_item_sku,
        UPPER(TRIM(DFC.code_warehouse))       AS code_warehouse,
        --UPPER(TRIM(DFC.code_customer_group))  AS code_customer_group,
        CAST(DFC.dt_fsc_month_first AS DATE)  AS dt_fsc_month_first,
        CAST(DFC.dt_fsc_month_last AS DATE)   AS dt_fsc_month_last,
        TRIM(DFC.code_horizon)                AS code_horizon,
        CAST(DFC.dt_snapshot AS DATE)         AS dt_snapshot,
        CAST(SUM(DFC.qty_forecast) AS DOUBLE) AS qty_forecast
    FROM {DB}.slv_forecast_demand_monthly AS DFC
    WHERE DFC.code_horizon IN ('Lag-0', 'Lag-1', 'Lag-2', 'Lag-3', 'Lag-4' , '>Lag-4')
    GROUP BY
        UPPER(TRIM(DFC.id_item_sku)),
        UPPER(TRIM(DFC.code_warehouse)),
        --UPPER(TRIM(DFC.code_customer_group)),
        CAST(DFC.dt_fsc_month_first AS DATE),
        CAST(DFC.dt_fsc_month_last AS DATE),
        TRIM(DFC.code_horizon),
        CAST(DFC.dt_snapshot AS DATE)
),

/* ── Actual demand: monthly by SKU × WH × CustGroup ── */
actuals AS (
    SELECT
        UPPER(TRIM(id_item_sku))              AS id_item_sku,
        UPPER(TRIM(code_warehouse))           AS code_warehouse,
        --UPPER(TRIM(code_customer_group))      AS code_customer_group,
        CAST(dt_fsc_month_first AS DATE)      AS dt_fsc_month_first,
        CAST(dt_fsc_month_last AS DATE)       AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS DOUBLE)       AS qty_actual
    FROM {DB}.slv_actual_demand_monthly
    GROUP BY
        UPPER(TRIM(id_item_sku)),
        UPPER(TRIM(code_warehouse)),
        --UPPER(TRIM(code_customer_group)),
        CAST(dt_fsc_month_first AS DATE),
        CAST(dt_fsc_month_last AS DATE)
),

/* ── Naive forecast: rolling from slv_naive_forecast_monthly ── */
naive AS (
    SELECT
        UPPER(TRIM(id_item_sku))              AS id_item_sku,
        UPPER(TRIM(code_warehouse))           AS code_warehouse,
        --UPPER(TRIM(code_customer_group))      AS code_customer_group,
        CAST(dt_fsc_month_first AS DATE)      AS dt_fsc_month_first,
        CAST(dt_fsc_month_last AS DATE)       AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS DOUBLE)       AS qty_naive_forecast
    FROM {DB}.slv_naive_forecast_monthly
    GROUP BY
        UPPER(TRIM(id_item_sku)),
        UPPER(TRIM(code_warehouse)),
        --UPPER(TRIM(code_customer_group)),
        CAST(dt_fsc_month_first AS DATE),
        CAST(dt_fsc_month_last AS DATE)
),

/* ── Spine: UNION all dimension keys from 3 sources ── */
dimkeys AS (
    SELECT id_item_sku, code_warehouse, --code_customer_group,
           dt_fsc_month_first, dt_fsc_month_last
    FROM forecast

    UNION

    SELECT id_item_sku, code_warehouse, --code_customer_group,
           dt_fsc_month_first, dt_fsc_month_last
    FROM actuals

    UNION

    SELECT id_item_sku, code_warehouse, --code_customer_group,
           dt_fsc_month_first, dt_fsc_month_last
    FROM naive
),
spine AS (
    SELECT 
        K.id_item_sku, K.code_warehouse, --K.code_customer_group,
        K.dt_fsc_month_first, K.dt_fsc_month_last, H.code_horizon
    FROM dimkeys K
    CROSS JOIN {DB}.ref_forecast_horizon H
)

/* ── Final: spine LEFT JOIN all three + compute error metrics ── */
SELECT
    SP.id_item_sku,
    SP.code_warehouse,
    --SP.code_customer_group,
    SP.dt_fsc_month_first,
    SP.dt_fsc_month_last,
    SP.code_horizon,
    FC.dt_snapshot,

    /* ── Quantities ── */
    CAST(FC.qty_forecast AS DOUBLE)        AS qty_forecast,
    CAST(ACT.qty_actual AS DOUBLE)         AS qty_actual,
    CAST(NF.qty_naive_forecast AS DOUBLE)  AS qty_naive_forecast,

    /* ── Forecast Error ── */
    CAST(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0) AS DOUBLE)
        AS qty_fcst_error,
    CAST(ABS(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0)) AS DOUBLE)
        AS qty_abs_fcst_error,

    /* ── Naive Forecast Error ── */
    CAST(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0) AS DOUBLE)
        AS qty_naive_fcst_error,
    CAST(ABS(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0)) AS DOUBLE)
        AS qty_abs_naive_fcst_error,

    /* ── Additional Components for KPI metrics ── */
    CAST(POWER(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0), 2) AS DOUBLE)
        AS qty_squared_fcst_error,
    CAST(POWER(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0), 2) AS DOUBLE)
        AS qty_squared_naive_fcst_error,
    CAST(CASE
        WHEN ACT.qty_actual IS NOT NULL AND FC.qty_forecast IS NOT NULL THEN 1
        ELSE 0
    END AS INT) AS valid_obs_flag,
    CAST(CASE
        WHEN ACT.qty_actual IS NOT NULL AND ACT.qty_actual <> 0 THEN 1
        ELSE 0
    END AS INT) AS valid_actual_nonzero_flag,
    CAST(CASE
        WHEN ACT.qty_actual IS NOT NULL AND ACT.qty_actual <> 0
            THEN ABS((COALESCE(FC.qty_forecast, 0) - ACT.qty_actual) / ACT.qty_actual)
        ELSE NULL
    END AS DOUBLE) AS abs_pct_error

FROM spine AS SP

LEFT JOIN forecast AS FC
    ON  SP.id_item_sku         <=> FC.id_item_sku
    AND SP.code_warehouse      <=> FC.code_warehouse
    --AND SP.code_customer_group <=> FC.code_customer_group
    AND SP.dt_fsc_month_first  <=> FC.dt_fsc_month_first
    AND SP.dt_fsc_month_last   <=> FC.dt_fsc_month_last
    AND SP.code_horizon        <=> FC.code_horizon

LEFT JOIN actuals AS ACT
    ON  SP.id_item_sku         <=> ACT.id_item_sku
    AND SP.code_warehouse      <=> ACT.code_warehouse
    --AND SP.code_customer_group <=> ACT.code_customer_group
    AND SP.dt_fsc_month_first  <=> ACT.dt_fsc_month_first
    AND SP.dt_fsc_month_last   <=> ACT.dt_fsc_month_last

LEFT JOIN naive AS NF
    ON  SP.id_item_sku         <=> NF.id_item_sku
    AND SP.code_warehouse      <=> NF.code_warehouse
    --AND SP.code_customer_group <=> NF.code_customer_group
    AND SP.dt_fsc_month_first  <=> NF.dt_fsc_month_first
    AND SP.dt_fsc_month_last   <=> NF.dt_fsc_month_last
'''

# ─── Cell 1 ───
notebookutils.notebook.run(
    "gld_engine",
    7200,
    {
        "TARGET_TABLE":   TARGET_TABLE,
        "SQL_AGGREGATE":  SQL_AGGREGATE
    }
)

