-- Source: SupplyChain_Warehouse.bronze.vw_brz_wholesale_codis_afi__comast
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_brz_wholesale_codis_afi__comast AS
SELECT
    TRIM(ACREC)                                         AS code_record_type,
    TRIM(ORDNO)                                         AS id_order,
    TRIM(CUSNO)                                         AS id_customer,
    TRIM(CUSPO)                                         AS id_customer_po,
    TRY_CONVERT(DATE, CAST(ORDTE AS VARCHAR(20)))       AS dt_order,
    CAST(ORVAL AS DECIMAL(14,2))                        AS amt_order_value,
    TRIM(HOUSE)                                         AS code_warehouse,
    CAST(SLSNO AS VARCHAR(200))                         AS code_salesperson,
    TRIM(SHPNO)                                         AS code_ship_to,
    TRY_CONVERT(DATE, CAST(RQDTE AS VARCHAR(20)))       AS dt_requested,
    CAST(SHLTC AS INT)                                  AS num_lead_time_days,
    TRIM(SHINS)                                         AS name_shipping_instructions,
    TRY_CONVERT(DATE, CAST(CUSPD AS VARCHAR(20)))       AS dt_customer_paid,
    TRIM(MPROR)                                         AS code_priority,
    TRIM(CMEMO)                                         AS code_memo
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST
WHERE ORDNO IS NOT NULL
