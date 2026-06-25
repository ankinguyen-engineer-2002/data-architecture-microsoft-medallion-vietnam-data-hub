-- Source: SupplyChain_Warehouse.silver.vw_slv_open_order_line_level
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW silver.vw_slv_open_order_line_level AS
SELECT
    T1.id_order, T1.num_item_sequence, T1.id_customer, T1.code_ship_to,
    UPPER(RTRIM(
        CASE WHEN T1.code_ship_to IS NULL OR TRIM(T1.code_ship_to) = ''
            THEN TRIM(T1.id_customer)
            ELSE CONCAT(TRIM(T1.id_customer), '-', TRIM(T1.code_ship_to))
        END
    )) AS id_account_ship_to,
    T1.id_item_sku, T1.code_warehouse,
    IM.code_afi_item_status,
    CAST(T1.qty_ordered - T1.qty_shipped AS INT) AS qty_open_order,
    CAST(T1.qty_backordered AS INT) AS qty_backorder,
    CAST(
        (T1.amt_extended_selling
         / CASE WHEN T1.qty_backordered > 0 THEN T1.qty_backordered
                WHEN T1.qty_ordered > 0 THEN T1.qty_ordered ELSE 1 END
         - COALESCE(T2.amt_freight, 0))
        * CASE WHEN T1.qty_backordered > 0 THEN T1.qty_backordered
               WHEN T1.qty_ordered > 0 THEN T1.qty_ordered ELSE 1 END
        AS DECIMAL(13,2)) AS amt_open_order,
    CAST(CASE WHEN T1.qty_backordered > 0
        THEN (T1.amt_extended_selling / T1.qty_backordered - COALESCE(T2.amt_freight, 0)) * T1.qty_backordered
        ELSE 0 END AS DECIMAL(13,2)) AS amt_backorder,
    T3.dt_order AS dt_order_taken,
    T2.dt_promise AS dt_original_promise,
    T1.dt_requested AS dt_current_promise,
    T4.dt_freeze AS dt_original_request,
    T4.dt_requested_ship AS dt_current_request,
    T1.dt_manufactured AS dt_current_load,
    OT1.name_order_type AS name_primary_order_type,
    OT2.name_order_type AS name_secondary_order_type,
    OT3.name_order_type AS name_3rd_order_type,
    OT4.name_order_type AS name_4th_order_type,
    T4.code_order_arrangement AS code_order_arrival,
    T1.code_allocation_flag,
    T1.num_load_date_changes,
    T3.num_lead_time_days,
    T3.name_shipping_instructions,
    CASE WHEN T1.name_item_description_short = T1.name_item_description THEN ''
         ELSE T1.name_item_description_short END AS name_customer_sku,
    COALESCE(T2.amt_freight, 0) AS amt_order_freight,
    CASE WHEN DATEADD(DAY, 7, T4.dt_requested_ship) < CAST(GETDATE() AS DATE)
         THEN 'Past Due' ELSE 'Future Ord' END AS code_past_due_flag
FROM bronze.brz_wholesale_codis_afi__codatan AS T1
LEFT JOIN bronze.brz_wholesale_codis_afi__extorit AS T2
    ON T1.id_order = T2.id_order AND T1.num_item_sequence = T2.num_item_sequence
INNER JOIN bronze.brz_wholesale_codis_afi__comast AS T3
    ON T1.id_order = T3.id_order
INNER JOIN bronze.brz_wholesale_codis_afi__extord AS T4
    ON T1.id_order = T4.id_order
INNER JOIN bronze.ref_item_master AS IM
    ON IM.id_item_sku = T1.id_item_sku
LEFT JOIN bronze.ref_order_type AS OT1 ON OT1.code_order_type = T4.code_order_type_1
LEFT JOIN bronze.ref_order_type AS OT2 ON OT2.code_order_type = T4.code_order_type_2
LEFT JOIN bronze.ref_order_type AS OT3 ON OT3.code_order_type = T4.code_order_type_3
LEFT JOIN bronze.ref_order_type AS OT4 ON OT4.code_order_type = T4.code_order_type_4
WHERE (T1.qty_backordered <> 0 OR T1.qty_ordered <> 0)
    AND T1.amt_selling_price <> 0
    AND T3.code_record_type <> 'X'
    AND T1.qty_ordered >= 0
