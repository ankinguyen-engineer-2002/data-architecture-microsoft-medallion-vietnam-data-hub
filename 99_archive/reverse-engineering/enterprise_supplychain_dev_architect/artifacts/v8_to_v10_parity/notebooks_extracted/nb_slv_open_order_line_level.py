# ─── Cell 0 ───
TARGET_TABLE = 'slv_open_order_line_level'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_TRANSFORM = f'''
SELECT
    /* ── Keys & Identifiers ── */
    T1.id_order,
    T1.num_item_sequence,
    T1.id_customer,
    T1.code_ship_to,
    UPPER(RTRIM(
        CASE
            WHEN T1.code_ship_to IS NULL OR TRIM(T1.code_ship_to) = ''
                THEN TRIM(T1.id_customer)
            ELSE CONCAT(TRIM(T1.id_customer), '-', TRIM(T1.code_ship_to))
        END
    ))                                                    AS id_account_ship_to,
    T1.id_item_sku,
    T1.code_warehouse,

    /* ── Item Status (from Item Master) ── */
    IM.code_afi_item_status,

    /* ── Quantities ── */
    CAST(T1.qty_ordered - T1.qty_shipped AS INT)         AS qty_open_order,
    CAST(T1.qty_backordered AS INT)                      AS qty_backorder,

    /* ── Amounts ── */
    CAST(
        (
            T1.amt_extended_selling
            / CASE
                WHEN T1.qty_backordered > 0 THEN T1.qty_backordered
                WHEN T1.qty_ordered > 0     THEN T1.qty_ordered
                ELSE 1
              END
            - COALESCE(T2.amt_freight, 0)
        )
        * CASE
            WHEN T1.qty_backordered > 0 THEN T1.qty_backordered
            WHEN T1.qty_ordered > 0     THEN T1.qty_ordered
            ELSE 1
          END
        AS DECIMAL(13,2)
    )                                                    AS amt_open_order,

    CAST(
        CASE
            WHEN T1.qty_backordered > 0
                THEN (T1.amt_extended_selling / T1.qty_backordered
                      - COALESCE(T2.amt_freight, 0))
                     * T1.qty_backordered
            ELSE 0
        END
        AS DECIMAL(13,2)
    )                                                    AS amt_backorder,

    /* ── Dates ── */
    T3.dt_order                                          AS dt_order_taken,
    T2.dt_promise                                        AS dt_original_promise,
    T1.dt_requested                                      AS dt_current_promise,
    T4.dt_freeze                                         AS dt_original_request,
    T4.dt_requested_ship                                 AS dt_current_request,
    T1.dt_manufactured                                   AS dt_current_load,

    /* ── Order Type (4 levels) ── */
    OT1.name_order_type                                  AS name_primary_order_type,
    OT2.name_order_type                                  AS name_secondary_order_type,
    OT3.name_order_type                                  AS name_3rd_order_type,
    OT4.name_order_type                                  AS name_4th_order_type,

    /* ── Scheduling & Shipping ── */
    T4.code_order_arrangement                            AS code_order_arrival,
    T1.code_allocation_flag,
    T1.num_load_date_changes,
    T3.num_lead_time_days,                                    
    T3.name_shipping_instructions,

    /* ── Customer SKU ── */
    CASE
        WHEN T1.name_item_description_short = T1.name_item_description
            THEN ''
        ELSE T1.name_item_description_short
    END                                                  AS name_customer_sku,

    /* ── Freight ── */
    COALESCE(T2.amt_freight, 0)                          AS amt_order_freight,

    /* ── Past Due Flag ── */
    CASE
        WHEN DATE_ADD(T4.dt_requested_ship, 7) < CURRENT_DATE()
            THEN 'Past Due'
        ELSE 'Future Ord'
    END                                                  AS code_past_due_flag

FROM {DB}.brz_wholesale_codis_afi__codatan                       AS T1 -- order detail

LEFT JOIN {DB}.brz_wholesale_codis_afi__extorit    AS T2 -- order item detail extended
    ON  T1.id_order          = T2.id_order
    AND T1.num_item_sequence  = T2.num_item_sequence

INNER JOIN {DB}.brz_wholesale_codis_afi__comast                 AS T3 -- order header
    ON  T1.id_order          = T3.id_order

INNER JOIN {DB}.brz_wholesale_codis_afi__extord        AS T4 -- order header extended
    ON  T1.id_order          = T4.id_order

INNER JOIN {DB}.ref_item_master                       AS IM
    ON  IM.id_item_sku       = T1.id_item_sku

LEFT JOIN {DB}.ref_order_type                         AS OT1 -- order type
    ON  OT1.code_order_type  = T4.code_order_type_1

LEFT JOIN {DB}.ref_order_type                         AS OT2 -- order type
    ON  OT2.code_order_type  = T4.code_order_type_2

LEFT JOIN {DB}.ref_order_type                         AS OT3 -- order type
    ON  OT3.code_order_type  = T4.code_order_type_3

LEFT JOIN {DB}.ref_order_type                         AS OT4 -- order type
    ON  OT4.code_order_type  = T4.code_order_type_4

WHERE
    (T1.qty_backordered <> 0 OR T1.qty_ordered <> 0)
    AND T1.amt_selling_price <> 0
    AND T3.code_record_type <> 'X'
    AND T1.qty_ordered >= 0
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

