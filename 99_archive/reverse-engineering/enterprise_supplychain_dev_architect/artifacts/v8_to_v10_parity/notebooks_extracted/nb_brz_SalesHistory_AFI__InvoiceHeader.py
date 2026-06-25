# ─── Cell 0 ───
TARGET_TABLE = "brz_saleshistory_afi__invoiceheader"
SOURCE_TABLE = "SalesHistory_AFI/InvoiceHeader"

COLUMN_SQL = """
    SELECT
        -- Business Keys / IDs (Sử dụng prefix id_)
        CAST(InvoiceNumber AS STRING)        AS id_invoice,
        CAST(CustomerNumber AS STRING)       AS id_customer,
        CAST(ShiptoNumber AS STRING)         AS id_ship_to,
        CAST(OrderNumber AS STRING)          AS id_order,
        CAST(PurchaseOrder AS STRING)        AS id_purchase_order,
        CAST(Warehouse AS STRING)            AS id_warehouse,
        CAST(ShiptoSalesman AS STRING)       AS id_salesman,
        CAST(TripNumber AS STRING)           AS id_trip,
        CAST(DropNumber AS STRING)           AS id_drop,
        CAST(PromotionNumber AS STRING)      AS id_promotion,
        CAST(CreditApprovalNBR AS STRING)    AS id_credit_approval,

        -- Dates (Sử dụng prefix dt_ và xử lý lỗi so sánh kiểu dữ liệu)
        CAST(InvoiceDate AS DATE)            AS dt_invoice,
        -- Chuyển về String trước khi so sánh với '0' hoặc '0.0' để tránh lỗi Mismatch
        CAST(CASE 
            WHEN CAST(RequestDate AS STRING) IN ('0', '0.0', '') THEN NULL 
            ELSE RequestDate 
        END AS DATE)                         AS dt_request,
        
        CAST(CASE 
            WHEN CAST(OrderDate AS STRING) IN ('0', '0.0', '') THEN NULL 
            ELSE OrderDate 
        END AS DATE)                         AS dt_order,
        
        CAST(CASE 
            WHEN CAST(TripCreatedDate AS STRING) IN ('0', '0.0', '') THEN NULL 
            ELSE TripCreatedDate 
        END AS DATE)                         AS dt_trip_created,

        -- Amounts (Sử dụng prefix amt_)
        CAST(InvoiceAmount AS DECIMAL(18,2)) AS amt_invoice,
        CAST(TaxAmount AS DECIMAL(18,2))     AS amt_tax,
        CAST(TermsDiscount AS DECIMAL(18,2)) AS amt_terms_discount,

        -- Names & Descriptions (Sử dụng prefix name_)
        TRIM(ShiptoName)                     AS name_ship_to,
        TRIM(ShiptoAddress1)                 AS name_ship_to_address_1,
        TRIM(ShiptoAddress2)                 AS name_ship_to_address_2,
        TRIM(ShiptoCity)                     AS name_ship_to_city,
        TRIM(SoldtoName)                     AS name_sold_to,
        TRIM(ShiptoCountryName)              AS name_ship_to_country,
        TRIM(ShipInstructions)               AS name_ship_instructions,

        -- Codes & Flags (Sử dụng prefix code_)
        TRIM(ShiptoState)                    AS code_ship_to_state,
        TRIM(ShiptoZipCode)                  AS code_ship_to_zip,
        TRIM(OrderArrivalCode)               AS code_order_arrival,
        TRIM(AdvertisingFlag)                AS code_advertising_flag,
        TRIM(OrderType)                      AS code_order_type,
        TRIM(OrderTypePrimary)               AS code_order_type_primary,
        TRIM(OrderTypeSecondary)             AS code_order_type_secondary,
        TRIM(OrderTypeUsrDefine3)            AS code_order_type_usr_3,
        TRIM(OrderTypeUsrDefine4)            AS code_order_type_usr_4,
        TRIM(CreditCode)                     AS code_credit,
        TRIM(CurrencyCode)                   AS code_currency,

        -- Numeric / Quantities / Values (Sử dụng prefix num_ hoặc val_)
        CAST(PostingMonth AS INT)            AS num_posting_month,
        CAST(LeadTime AS INT)                AS num_lead_time_days,
        CAST(Sequence AS INT)                AS num_sequence,
        CAST(ShipWeight AS DECIMAL(18,4))    AS val_ship_weight

    FROM raw_source
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

