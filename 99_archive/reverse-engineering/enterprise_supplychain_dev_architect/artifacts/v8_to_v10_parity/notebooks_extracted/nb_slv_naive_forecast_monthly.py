# ─── Cell 0 ───
TARGET_TABLE = 'slv_naive_forecast_monthly'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_TRANSFORM = f'''
WITH
/* ── Fiscal weeks per month ── */
month_weeks AS (
    SELECT
        dt_fsc_month_first,
        COUNT(DISTINCT dt_fsc_week_first)                AS num_weeks
    FROM {DB}.ref_calendar
    GROUP BY dt_fsc_month_first
),

/* ── Actual demand aggregated to monthly grain ── */
actuals_monthly AS (
    SELECT
        id_item_sku,
        code_warehouse,
        code_customer_group,
        dt_fsc_month_first,
        dt_fsc_month_last,
        SUM(qty_demand)                                  AS qty_actual
    FROM {DB}.slv_actual_demand_monthly
    GROUP BY
        id_item_sku,
        code_warehouse,
        code_customer_group,
        dt_fsc_month_first,
        dt_fsc_month_last
),

/* ── Attach week counts + get prior month actual via LAG ── */
actuals_with_lag AS (
    SELECT
        A.id_item_sku,
        A.code_warehouse,
        A.code_customer_group,
        A.dt_fsc_month_first,
        A.dt_fsc_month_last,
        A.qty_actual,
        MW.num_weeks,
        LAG(A.qty_actual) OVER (
            PARTITION BY A.id_item_sku, A.code_warehouse, A.code_customer_group
            ORDER BY A.dt_fsc_month_first
        )                                                AS qty_actual_prior,
        LAG(MW.num_weeks) OVER (
            PARTITION BY A.id_item_sku, A.code_warehouse, A.code_customer_group
            ORDER BY A.dt_fsc_month_first
        )                                                AS num_weeks_prior
    FROM actuals_monthly                                 AS A
    INNER JOIN month_weeks                               AS MW
        ON  MW.dt_fsc_month_first = A.dt_fsc_month_first
),

current_fiscal AS (
    SELECT num_fsc_year
    FROM {DB}.ref_calendar
    WHERE dt_date = CURRENT_DATE()
    LIMIT 1
)

SELECT
    L.id_item_sku,
    L.code_warehouse,
    L.code_customer_group,
    L.dt_fsc_month_first,
    L.dt_fsc_month_last,
    CAST(
        L.qty_actual_prior / L.num_weeks_prior * L.num_weeks
        AS INT
    )                                                    AS qty_demand,
    'Naive Forecast'                                     AS code_status,
    'Naive Forecast'                                     AS name_version

FROM actuals_with_lag                                    AS L
INNER JOIN {DB}.ref_calendar                              AS CAL
    ON  CAL.dt_date = L.dt_fsc_month_first
CROSS JOIN current_fiscal                                AS CF

WHERE
    L.qty_actual_prior IS NOT NULL
    AND L.num_weeks_prior > 0
    AND L.code_warehouse NOT IN ('C', 'CNW', 'C35', '55')
    AND CAL.num_fsc_month_year >= (CF.num_fsc_year - 3) * 100
    AND CAL.num_fsc_month_year <= (CF.num_fsc_year + 1) * 100 + 1299
'''

# ─── Cell 1 ───
notebookutils.notebook.run(
    "slv_engine",
    7200,
    {
        "TARGET_TABLE":   TARGET_TABLE,
        "SQL_TRANSFORM":  SQL_TRANSFORM
    }
)

