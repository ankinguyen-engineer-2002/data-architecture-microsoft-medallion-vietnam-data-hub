# ─── Cell 0 ───
TARGET_TABLE = 'slv_open_order_monthly'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_TRANSFORM = f'''
WITH current_fiscal AS (
    SELECT num_fsc_year
    FROM {DB}.ref_calendar
    WHERE dt_date = CURRENT_DATE()
    LIMIT 1
)

SELECT
    /* ── Grain Keys ── */
    OO.id_item_sku,
    OO.code_warehouse,
    UPPER(CG.code_customer_group) AS code_customer_group,
    CAL.dt_fsc_month_first,
    CAL.dt_fsc_month_last,

    /* ── Quantities ── */
    SUM(OO.qty_open_order)                               AS qty_open_order,
    SUM(OO.qty_backorder)                                AS qty_backorder,

    /* ── Amounts ── */
    SUM(OO.amt_open_order)                               AS amt_open_order,
    SUM(OO.amt_backorder)                                AS amt_backorder,

    /* ── Line Counts ── */
    COUNT(*)                                             AS num_order_lines,
    COUNT(DISTINCT OO.id_order)                          AS num_distinct_orders,

    /* ── Past Due ── */
    SUM(CASE WHEN OO.code_past_due_flag = 'Past Due'
             THEN OO.qty_open_order ELSE 0 END)          AS qty_past_due,
    SUM(CASE WHEN OO.code_past_due_flag = 'Past Due'
             THEN OO.amt_open_order ELSE 0 END)          AS amt_past_due

FROM {DB}.slv_open_order_line_level                       AS OO

INNER JOIN {DB}.ref_calendar                              AS CAL
    ON  CAL.dt_date = OO.dt_current_request

LEFT JOIN {DB}.ref_customer_account_group                      AS CG
    ON  CG.id_customer = OO.id_customer

CROSS JOIN current_fiscal                                AS CF

WHERE
    CAL.num_fsc_year BETWEEN CF.num_fsc_year - 3 AND CF.num_fsc_year + 1

GROUP BY
    OO.id_item_sku,
    OO.code_warehouse,
    UPPER(CG.code_customer_group),
    CAL.dt_fsc_month_first,
    CAL.dt_fsc_month_last
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

