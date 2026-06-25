# ─── Cell 0 ───
TARGET_TABLE = "brz_wholesale_codis_afi__extorit"
SOURCE_TABLE = "Wholesale_Codis_AFI/EXTORIT"

COLUMN_SQL = """
    SELECT
        -- Keys & Identifiers
        TRIM(IORD)                                          AS id_order,
        CAST(ISEQ AS INT)                                   AS num_item_sequence,
        TRIM(IITEM)                                         AS id_item_sku,
        CAST(IEXCID AS INT)                                 AS id_exception,
        CAST(IGRPID AS INT)                                 AS id_group,
        CAST(IGRPNO AS INT)                                 AS num_group,

        -- Salesperson
        CAST(ISLSN1 AS INT)                                 AS id_salesperson_1,
        CAST(ISLSN2 AS INT)                                 AS id_salesperson_2,

        -- Pricing & Discount
        CAST(IPRICE AS DECIMAL(14,4))                       AS amt_fob_price,
        CAST(IDSCNT AS DECIMAL(12,2))                       AS amt_discount,
        CAST(IDFIDC AS DECIMAL(12,2))                       AS amt_discount_fid,
        CAST(IFRGHT AS DECIMAL(12,2))                       AS amt_freight,
        CAST(IHDFRT AS DECIMAL(12,2))                       AS amt_handling_freight,
        CAST(ITDSCT AS DECIMAL(14,4))                       AS pct_total_discount,
        CAST(IFOBPR AS DECIMAL(12,2))                       AS amt_fob_price_base,
        CAST(IREDUS AS STRING)                              AS code_reduce,
        CAST(ICMADJ AS DECIMAL(12,2))                       AS amt_commission_adjustment,
        CAST(IPALLW AS DECIMAL(14,4))                       AS amt_price_allowance,
        CAST(ICONPR AS DECIMAL(12,2))                       AS amt_contract_price,
        CAST(ICOOPA AS DECIMAL(12,2))                       AS amt_coop_allowance,

        -- Quantities
        CAST(IATPQY AS DECIMAL(12,3))                       AS qty_atp,
        CAST(IATPQS AS DECIMAL(12,3))                       AS qty_atp_shipped,
        CAST(IATPWH AS DECIMAL(12,3))                       AS qty_atp_warehouse,

        -- Codes & Classification
        TRIM(IDSCCD)                                        AS code_discount,
        TRIM(IDSCSC)                                        AS code_discount_schedule,
        TRIM(ICOMCD)                                        AS code_commission,
        TRIM(IPRCCD)                                        AS code_price,
        TRIM(IFRTCD)                                        AS code_freight_type,
        TRIM(IGBCOD)                                        AS code_global,
        TRIM(IORDST)                                        AS code_order_status,

        -- Routing & Shipping
        TRIM(IRTECD)                                        AS code_route,
        TRIM(IFSLSC)                                        AS code_first_sales_class,
        TRIM(ICSLSC)                                        AS code_current_sales_class,
        TRIM(IARVLMD)                                       AS code_arrival_mode,
        TRIM(IPRCSTS)                                       AS code_price_status,
        TRIM(ICUS)                                          AS id_customer,
        TRIM(ISTATE)                                        AS code_state,
        TRIM(IWHSOP)                                        AS code_warehouse_operation,

        -- Trip & Control
        CAST(ITRIP AS INT)                                  AS num_trip,
        CAST(IDROP AS INT)                                  AS num_drop,
        CAST(ICNTL AS INT)                                  AS num_control,
        CAST(IPRI AS INT)                                   AS num_priority,
        TRIM(ISTAT)                                         AS code_status,
        TRIM(IREF)                                          AS code_reference,
        CAST(IORDPRTY AS INT)                               AS num_order_priority,

        -- Scheduling Counts
        CAST(IPRGCNT AS INT)                                AS num_progress_count,
        CAST(ISCHCNT AS INT)                                AS num_schedule_count,
        CAST(ICNLCNT AS INT)                                AS num_cancel_count,
        CAST(IFRZCNT AS INT)                                AS num_freeze_count,
        CAST(ICDKCNT AS INT)                                AS num_cross_dock_count,

        -- Line Rule & Comments
        TRIM(ILNRL)                                         AS code_line_rule,
        TRIM(IERRCM)                                        AS code_error_comment,
        CAST(ISLCM1 AS DECIMAL(14,4))                       AS val_sales_comment_1,
        CAST(ISLCM2 AS DECIMAL(14,4))                       AS val_sales_comment_2,

        -- Dates
        to_date(CAST(IPRMDT AS STRING), 'yyyyMMdd')         AS dt_promise,
        to_date(CAST(IOISDT AS STRING), 'yyyyMMdd')         AS dt_original_issue,
        to_date(CAST(IMRDDT AS STRING), 'yyyyMMdd')         AS dt_merge,
        to_date(CAST(IREDRT AS STRING), 'yyyyMMdd')         AS dt_reduce,
        to_date(CAST(IARDTE AS STRING), 'yyyyMMdd')         AS dt_arrival,
        CAST(IORINV AS INT)                                 AS num_original_invoice,

        -- Delivery Dates
        to_date(CAST(IORGDLV AS STRING), 'yyyyMMdd')        AS dt_delivery_original,
        to_date(CAST(ICNFDLV AS STRING), 'yyyyMMdd')        AS dt_delivery_confirmed,
        to_date(CAST(IFRZDLV AS STRING), 'yyyyMMdd')        AS dt_delivery_frozen,
        to_date(CAST(IFINDLV AS STRING), 'yyyyMMdd')        AS dt_delivery_final,
        CAST(IPRTY AS INT)                                  AS num_delivery_priority,

        -- Package
        TRIM(IPKGID)                                        AS id_package,
        CAST(IPKGDA AS DECIMAL(12,3))                       AS val_package_data,
        CAST(IPKGPRC AS DECIMAL(12,2))                      AS amt_package_price,
        TRIM(IITMSTS)                                       AS code_item_status,
        CAST(`IPKITM$` AS DECIMAL(12,2))                    AS amt_package_item,
        CAST(IPKITMDS AS DECIMAL(12,3))                     AS val_package_item_discount,
        TRIM(IACHORITM)                                     AS code_anchor_item,
        TRIM(IPKGDES)                                       AS name_package_description,

        -- Flags
        TRIM(IPDISD)                                        AS code_price_discount,
        TRIM(IPRCDT)                                        AS code_price_date,
        TRIM(IOCOMR)                                        AS code_original_commission,

        -- Job
        TRIM(IJOBID)                                        AS id_job

    FROM raw_source
    WHERE IORD IS NOT NULL
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

