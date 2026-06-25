# ─── Cell 0 ───
TARGET_TABLE = 'slv_invoice_detail_line_level'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_TRANSFORM = f'''
SELECT
    /* ── Keys & Identifiers ── */
    INV.id_invoice,
    INV.id_invoice_extended,
    INV.id_order,
    INV.num_item_sequence,
    INV.id_customer,
    INV.code_ship_to,
    UPPER(RTRIM(
        CASE
            WHEN INV.code_ship_to IS NULL OR TRIM(INV.code_ship_to) = ''
                THEN TRIM(INV.id_customer)
            ELSE CONCAT(TRIM(INV.id_customer), '-', TRIM(INV.code_ship_to))
        END
    ))                                                    AS id_account_ship_to,
    INV.id_item_sku,
    INV.code_warehouse,
    UPPER(CG.code_customer_group) AS code_customer_group,
    IH.num_lead_time_days,

    /* ── Quantities ── */
    INV.qty_shipped,
    INV.qty_ordered,
    INV.qty_backordered,

    /* ── Amounts ── */
    INV.amt_invoice,
    INV.amt_net_sales,
    INV.amt_price,
    INV.amt_standard_price,
    INV.amt_contract_price,
    INV.amt_discount,
    INV.amt_price_adjustment,
    INV.amt_freight,

    /* ── Dates (from invoice) ── */
    INV.dt_invoice,
    INV.dt_order,
    INV.dt_request,
    INV.dt_current_request,
    INV.dt_current_promise,
    INV.dt_original_request,
    INV.dt_original_promise,
    INV.dt_promised_delivery,
    INV.dt_delivery,
    INV.dt_actual_delivery,

    /* ── Order attributes ── */
    INV.code_order_type,
    INV.code_order_type_3,
    INV.code_credit,
    INV.code_item_class,
    INV.code_order_item_status

FROM {DB}.brz_saleshistory_afi__invoicedetail_ver2                            AS INV
LEFT JOIN {DB}.brz_saleshistory_afi__invoiceheader_ver2 AS IH
    ON INV.id_invoice = IH.id_invoice
      AND INV.dt_invoice = IH.dt_invoice
      AND INV.dt_order = IH.dt_order
      AND INV.id_order = IH.id_order
LEFT JOIN {DB}.ref_customer_account_group                      AS CG
    ON  CG.id_customer = INV.id_customer;
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

