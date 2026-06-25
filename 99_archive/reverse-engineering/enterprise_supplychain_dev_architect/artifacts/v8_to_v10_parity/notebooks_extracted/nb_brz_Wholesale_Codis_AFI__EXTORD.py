# ─── Cell 0 ───
TARGET_TABLE = "brz_wholesale_codis_afi__extord"
SOURCE_TABLE = "Wholesale_Codis_AFI/EXTORD"

COLUMN_SQL = """
    SELECT
        -- Keys & Identifiers
        TRIM(XORDNO)                                        AS id_order,
        TRIM(CUSTNO)                                        AS id_customer,
        TRIM(`SHPTO#`)                                      AS code_ship_to,
        CAST(CSRPID AS INT)                                 AS id_csr,

        -- Order Attributes
        TRIM(ORDARR)                                        AS code_order_arrangement,
        TRIM(ORTYPE)                                        AS code_order_type,
        TRIM(ORDUSE)                                        AS code_order_use,
        TRIM(ORDREF)                                        AS code_order_reference,
        CAST(ORDLNK AS INT)                                 AS num_order_link,
        CAST(NOSETS AS INT)                                 AS num_sets,
        TRIM(ORDUSR)                                        AS name_order_user,

        -- Order Type Flags
        TRIM(OTTYP1)                                        AS code_order_type_1,
        TRIM(OTTYP2)                                        AS code_order_type_2,
        TRIM(OTTYP3)                                        AS code_order_type_3,
        TRIM(OTTYP4)                                        AS code_order_type_4,

        -- Scheduling & Dates
        to_date(CAST(RQSDAT AS STRING), 'yyyyMMdd')         AS dt_requested_ship,
        to_date(CAST(TKNDAT AS STRING), 'yyyyMMdd')         AS dt_taken,
        to_date(CAST(FRZDAT AS STRING), 'yyyyMMdd')         AS dt_freeze,
        to_date(CAST(HDATE AS STRING), 'yyyyMMdd')          AS dt_hold,
        to_date(CAST(CAPRDT AS STRING), 'yyyyMMdd')         AS dt_capacity,
        to_date(CAST(CBDDAT AS STRING), 'yyyyMMdd')         AS dt_cbd,
        to_date(CAST(DATMNT AS STRING), 'yyyyMMdd')         AS dt_maintenance,
        TRIM(TIMMNT)                                        AS code_time_maintenance,

        -- Shipping & Location
        TRIM(WHSE)                                          AS code_warehouse,
        TRIM(SHPNAM)                                        AS name_ship_to,
        TRIM(ZIPCOD)                                        AS code_zip,
        TRIM(EXTCTY)                                        AS code_city,
        TRIM(EXTSTE)                                        AS code_state,
        TRIM(TERRCD)                                        AS code_territory,
        TRIM(ARZONE)                                        AS code_ar_zone,
        CAST(ARSEQ AS INT)                                  AS num_ar_sequence,
        to_date(CAST(ARDATE AS STRING), 'yyyyMMdd')         AS dt_ar,

        -- Trip & Routing
        CAST(`TRPNO` AS INT)                                AS num_trip,
        CAST(`DROP#` AS INT)                                AS num_drop,
        CAST(`TRIP#` AS INT)                                AS num_trip_sequence,
        TRIM(ADVTSP)                                        AS code_advance_transport,

        -- Contact
        TRIM(CONTAC)                                        AS name_contact,
        TRIM(`PHONE#`)                                      AS code_phone,

        -- Credit & Approval
        TRIM(CREDVW)                                        AS code_credit_review,
        TRIM(APVCHK)                                        AS code_approval_check,
        TRIM(APPROV)                                        AS name_approver,
        CAST(RCVCSH AS INT)                                 AS num_received_cash,
        TRIM(CROVRD)                                        AS code_credit_override,
        to_date(CAST(CROVDT AS STRING), 'yyyyMMdd')         AS dt_credit_override,
        TRIM(CRANOV)                                        AS code_credit_analysis_override,

        -- Pricing & Commission
        TRIM(COMMCO)                                        AS code_commission,
        TRIM(DSCNCO)                                        AS code_discount,
        TRIM(PRICCO)                                        AS code_price,
        TRIM(FRGHCO)                                        AS code_freight,
        TRIM(PRMNBR)                                        AS code_promo,

        -- Maintenance
        CAST(MNTCNT AS INT)                                 AS num_maintenance_count,
        TRIM(USRMNT)                                        AS name_maintenance_user,
        TRIM(HLDUSR)                                        AS name_hold_user,
        TRIM(REFNUM)                                        AS code_reference_number

    FROM raw_source
    WHERE XORDNO IS NOT NULL
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

