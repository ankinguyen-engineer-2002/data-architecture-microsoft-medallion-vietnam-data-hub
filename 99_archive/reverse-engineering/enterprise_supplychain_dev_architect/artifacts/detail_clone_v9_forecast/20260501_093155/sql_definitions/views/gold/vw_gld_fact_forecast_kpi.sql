-- Source: SupplyChain_Warehouse.gold.vw_gld_fact_forecast_kpi
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW gold.vw_gld_fact_forecast_kpi AS
WITH
forecast AS (
    SELECT
        UPPER(TRIM(DFC.id_item_sku))          AS id_item_sku,
        UPPER(TRIM(DFC.code_warehouse))       AS code_warehouse,
        CAST(DFC.dt_fsc_month_first AS DATE)  AS dt_fsc_month_first,
        CAST(DFC.dt_fsc_month_last AS DATE)   AS dt_fsc_month_last,
        TRIM(DFC.code_horizon)                AS code_horizon,
        CAST(DFC.dt_snapshot AS DATE)         AS dt_snapshot,
        CAST(SUM(DFC.qty_forecast) AS FLOAT)  AS qty_forecast
    FROM silver.slv_forecast_demand_monthly AS DFC
    WHERE DFC.code_horizon IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY
        UPPER(TRIM(DFC.id_item_sku)),
        UPPER(TRIM(DFC.code_warehouse)),
        CAST(DFC.dt_fsc_month_first AS DATE),
        CAST(DFC.dt_fsc_month_last AS DATE),
        TRIM(DFC.code_horizon),
        CAST(DFC.dt_snapshot AS DATE)
),

actuals AS (
    SELECT
        UPPER(TRIM(id_item_sku))              AS id_item_sku,
        UPPER(TRIM(code_warehouse))           AS code_warehouse,
        CAST(dt_fsc_month_first AS DATE)      AS dt_fsc_month_first,
        CAST(dt_fsc_month_last AS DATE)       AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS FLOAT)        AS qty_actual
    FROM silver.slv_actual_demand_monthly
    GROUP BY
        UPPER(TRIM(id_item_sku)),
        UPPER(TRIM(code_warehouse)),
        CAST(dt_fsc_month_first AS DATE),
        CAST(dt_fsc_month_last AS DATE)
),

naive AS (
    SELECT
        UPPER(TRIM(id_item_sku))              AS id_item_sku,
        UPPER(TRIM(code_warehouse))           AS code_warehouse,
        CAST(dt_fsc_month_first AS DATE)      AS dt_fsc_month_first,
        CAST(dt_fsc_month_last AS DATE)       AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS FLOAT)        AS qty_naive_forecast
    FROM silver.slv_naive_forecast_monthly
    GROUP BY
        UPPER(TRIM(id_item_sku)),
        UPPER(TRIM(code_warehouse)),
        CAST(dt_fsc_month_first AS DATE),
        CAST(dt_fsc_month_last AS DATE)
),

dimkeys AS (
    SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last
    FROM forecast
    UNION
    SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last
    FROM actuals
    UNION
    SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last
    FROM naive
),

spine AS (
    SELECT
        K.id_item_sku, K.code_warehouse,
        K.dt_fsc_month_first, K.dt_fsc_month_last,
        H.code_horizon
    FROM dimkeys K
    CROSS JOIN bronze.ref_forecast_horizon H
)

SELECT
    SP.id_item_sku,
    SP.code_warehouse,
    SP.dt_fsc_month_first,
    SP.dt_fsc_month_last,
    SP.code_horizon,
    FC.dt_snapshot,

    /* ── Quantities ── */
    CAST(FC.qty_forecast AS FLOAT)                       AS qty_forecast,
    CAST(ACT.qty_actual AS FLOAT)                        AS qty_actual,
    CAST(NF.qty_naive_forecast AS FLOAT)                 AS qty_naive_forecast,

    /* ── Forecast Error ── */
    CAST(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0) AS FLOAT)
        AS qty_fcst_error,
    CAST(ABS(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0)) AS FLOAT)
        AS qty_abs_fcst_error,

    /* ── Naive Forecast Error ── */
    CAST(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0) AS FLOAT)
        AS qty_naive_fcst_error,
    CAST(ABS(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0)) AS FLOAT)
        AS qty_abs_naive_fcst_error,

    /* ── NEW: 5 extra KPI columns (match v8 notebook) ── */
    CAST(POWER(COALESCE(FC.qty_forecast, 0) - COALESCE(ACT.qty_actual, 0), 2) AS FLOAT)
        AS qty_squared_fcst_error,
    CAST(POWER(COALESCE(NF.qty_naive_forecast, 0) - COALESCE(ACT.qty_actual, 0), 2) AS FLOAT)
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
    END AS FLOAT) AS abs_pct_error

FROM spine AS SP

LEFT JOIN forecast AS FC
    ON  SP.id_item_sku        = FC.id_item_sku
    AND SP.code_warehouse     = FC.code_warehouse
    AND SP.dt_fsc_month_first = FC.dt_fsc_month_first
    AND SP.dt_fsc_month_last  = FC.dt_fsc_month_last
    AND SP.code_horizon       = FC.code_horizon

LEFT JOIN actuals AS ACT
    ON  SP.id_item_sku        = ACT.id_item_sku
    AND SP.code_warehouse     = ACT.code_warehouse
    AND SP.dt_fsc_month_first = ACT.dt_fsc_month_first
    AND SP.dt_fsc_month_last  = ACT.dt_fsc_month_last

LEFT JOIN naive AS NF
    ON  SP.id_item_sku        = NF.id_item_sku
    AND SP.code_warehouse     = NF.code_warehouse
    AND SP.dt_fsc_month_first = NF.dt_fsc_month_first
    AND SP.dt_fsc_month_last  = NF.dt_fsc_month_last
