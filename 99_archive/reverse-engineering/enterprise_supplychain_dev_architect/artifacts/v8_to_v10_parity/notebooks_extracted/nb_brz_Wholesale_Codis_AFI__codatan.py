# ─── Cell 0 ───
TARGET_TABLE = "brz_wholesale_codis_afi__codatan"
SOURCE_TABLE = "Wholesale_Codis_AFI/codatan"

COLUMN_SQL = """
    SELECT
        -- Keys & Identifiers
        TRIM(ORDNO)                                         AS id_order,
        TRIM(ITNBR)                                         AS id_item_sku,
        TRIM(HOUSE)                                         AS code_warehouse,
        CAST(ITMSQ AS INT)                                  AS num_item_sequence,

        -- Quantities
        CAST(COQTY AS DECIMAL(12,3))                        AS qty_ordered,
        CAST(QTYSH AS DECIMAL(12,3))                        AS qty_shipped,
        CAST(QTYBO AS DECIMAL(12,3))                        AS qty_backordered,

        -- Pricing - Current
        CAST(INSAM AS DECIMAL(12,2))                        AS amt_extended_selling,
        CAST(ISLPR AS DECIMAL(12,4))                        AS amt_list_price,
        CAST(PRICE AS DECIMAL(12,4))                        AS amt_selling_price,
        CAST(UNITC AS DECIMAL(14,8))                        AS amt_unit_cost,
        CAST(NEGPR AS DECIMAL(12,4))                        AS amt_negotiated_price,
        CAST(UNTPO AS DECIMAL(12,4))                        AS amt_unit_purchase_order,
        CAST(PRADJ AS DECIMAL(12,2))                        AS amt_price_adjustment,
        CAST(ISCPR AS DECIMAL(14,7))                        AS amt_selling_price_current,

        -- Pricing - Original
        CAST(ISLPO AS DECIMAL(12,4))                        AS amt_list_price_original,
        CAST(INSAO AS DECIMAL(12,2))                        AS amt_extended_selling_original,

        -- Pricing - History
        CAST(PRICH AS DECIMAL(12,4))                        AS amt_price_history,
        CAST(ISLPH AS DECIMAL(12,4))                        AS amt_list_price_history,
        CAST(INSAH AS DECIMAL(12,2))                        AS amt_extended_selling_history,
        CAST(ISCPH AS DECIMAL(14,7))                        AS amt_selling_price_history,

        -- Weight
        CAST(WEGHT AS DECIMAL(12,3))                        AS val_weight,
        CAST(EXTWT AS DECIMAL(12,3))                        AS val_extended_weight,
        CAST(EXTWO AS DECIMAL(12,3))                        AS val_extended_weight_original,

        -- Dates - Integer format
        to_date(CAST(RQIDT AS STRING), 'yyyyMMdd')          AS dt_requested,
        to_date(CAST(MFIDT AS STRING), 'yyyyMMdd')          AS dt_manufactured,

        -- Dates - Timestamp format
        CAST(LSLDDTCH AS TIMESTAMP)                         AS dt_last_schedule_change,
        CAST(PRVLDDTE AS TIMESTAMP)                         AS dt_previous_load,
        CAST(PRLDDTCH AS TIMESTAMP)                         AS dt_prior_load_change,
        CAST(EARLDDT AS TIMESTAMP)                          AS dt_earliest_load,
        CAST(LATLDDT AS TIMESTAMP)                          AS dt_latest_load,
        CAST(ITMLTLDDT AS TIMESTAMP)                        AS dt_item_latest_load,

        -- Customer & Routing
        TRIM(CCUSNO)                                        AS id_customer,
        TRIM(CSHPNO)                                        AS code_ship_to,
        TRIM(MARKFOR)                                       AS name_mark_for,

        -- Item Attributes
        TRIM(ITDSC)                                         AS name_item_description,
        TRIM(ITDSI)                                         AS name_item_description_short,
        TRIM(ITCLS)                                         AS code_item_class,
        TRIM(ITTYP)                                         AS code_item_type,
        TRIM(UNMSR)                                         AS code_unit_measure,
        TRIM(RCDCD)                                         AS code_record,
        TRIM(WHSLC)                                         AS code_wholesale,
        TRIM(CRCOD)                                         AS code_carrier,
        TRIM(PTRCD)                                         AS code_pattern,
        TRIM(LSTUM)                                         AS code_last_unit_measure,
        TRIM(TXIND)                                         AS code_tax_indicator,
        TRIM(COREL)                                         AS code_correlation,
        TRIM(MORDN)                                         AS code_merge_order,
        TRIM(EXPAD)                                         AS code_expedite_ad,
        TRIM(ARRVLMODE)                                     AS code_arrival_mode,
        TRIM(ITMPRCSTS)                                     AS code_item_price_status,

        -- Counts
        CAST(NUMLDDTCHG AS INT)                             AS num_load_date_changes,
        CAST(LPMNO AS INT)                                  AS num_last_promo,
        CAST(PMULT AS INT)                                  AS num_price_multiple,
        CAST(QPDPT AS INT)                                  AS num_qty_per_dept,

        -- Flags
        TRIM(IAFLG)                                         AS code_allocation_flag,
        CASE WHEN CAST(NOINV AS INT) != 0 THEN true ELSE false END  AS is_no_invoice,
        CASE WHEN CAST(UPDMC AS INT) != 0 THEN true ELSE false END  AS is_update_mc,
        CASE WHEN CAST(UPDMP AS DECIMAL(10,3)) != 0 THEN true ELSE false END AS is_update_mp,
        CASE WHEN CAST(ORFLG AS INT) != 0 THEN true ELSE false END  AS is_order_flag,
        CASE WHEN CAST(RDOVR AS INT) != 0 THEN true ELSE false END  AS is_round_override,
        CASE WHEN CAST(MDOVR AS INT) != 0 THEN true ELSE false END  AS is_method_override,
        CASE WHEN CAST(NEGRH AS DECIMAL(10,3)) != 0 THEN true ELSE false END AS is_negotiated_history,
        CASE WHEN TRIM(MOFLG) = '1' THEN true ELSE false END        AS is_merge_order_flag,
        CASE WHEN TRIM(SAFLG) = '1' THEN true ELSE false END        AS is_sale_flag,

        -- Date - Other
        TRIM(MRDTE)                                         AS code_merge_date

    FROM raw_source
    WHERE ORDNO IS NOT NULL
"""

# ─── Cell 1 ───
notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,
        "COLUMN_SQL":   COLUMN_SQL
    }
)

