# ─── Cell 0 ───
TARGET_TABLE = "brz_wholesale_codis_afi__comast"
SOURCE_TABLE = "Wholesale_Codis_AFI/COMAST"

COLUMN_SQL = """
    SELECT
        -- Keys & Identifiers
        TRIM(ACREC)                                         AS code_record_type,
        TRIM(ORDNO)                                         AS id_order,
        TRIM(CUSNO)                                         AS id_customer,
        TRIM(CUSPO)                                         AS id_customer_po,

        -- Order Info
        to_date(CAST(ORDTE AS STRING), 'yyyyMMdd')          AS dt_order,
        CAST(ORVAL AS DECIMAL(14,2))                        AS amt_order_value,
        TRIM(HOUSE)                                         AS code_warehouse,
        TRIM(SLSNO)                                         AS code_salesperson,
        TRIM(SHPNO)                                         AS code_ship_to,

        -- Scheduling & Shipping
        to_date(CAST(RQDTE AS STRING), 'yyyyMMdd')          AS dt_requested,
        CAST(SHLTC AS INT)                                  AS num_lead_time_days,
        TRIM(SHINS)                                         AS name_shipping_instructions,
        to_date(CAST(CUSPD AS STRING), 'yyyyMMdd')          AS dt_customer_paid,

        -- Flags
        TRIM(MPROR)                                         AS code_priority,
        TRIM(CMEMO)                                         AS code_memo
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

