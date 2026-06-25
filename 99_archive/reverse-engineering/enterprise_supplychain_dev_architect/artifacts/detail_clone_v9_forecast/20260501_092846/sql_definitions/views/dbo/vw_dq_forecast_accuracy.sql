-- Source: SupplyChain_Warehouse.dbo.vw_dq_forecast_accuracy
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

-- ============================================================================
-- VIEW: vw_data_quality_checks
-- Returns 13 DQ checks, each as one row: check_id, check_name, is_pass (1/0)
-- ============================================================================

CREATE     VIEW dbo.vw_dq_forecast_accuracy
AS

-- ================================================================
-- DQ_01: Actual qty — Gold KPI vs Silver Actual Demand
-- ================================================================
SELECT
    'DQ_01' AS check_id,
    'Actual qty: Gold KPI vs Silver Actual Demand' AS check_name,
    CASE WHEN mismatch.cnt = 0 THEN 1 ELSE 0 END AS is_pass
FROM (
    SELECT COUNT(*) AS cnt
    FROM (
        SELECT
            TRIM(id_item_sku)                AS id_item_sku,
            TRIM(code_warehouse)             AS code_warehouse,
            --TRIM(code_customer_group)        AS code_customer_group,
            CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first,
            CAST(dt_fsc_month_last AS DATE)  AS dt_fsc_month_last,
            SUM(qty_demand)                  AS qty_actual_slv
        FROM SupplyChain_Lakehouse.dbo.slv_actual_demand_monthly
        GROUP BY TRIM(id_item_sku), TRIM(code_warehouse), --TRIM(code_customer_group),
                 CAST(dt_fsc_month_first AS DATE), CAST(dt_fsc_month_last AS DATE)
    ) s
    FULL OUTER JOIN (
        SELECT
            id_item_sku, code_warehouse, --code_customer_group,
            dt_fsc_month_first, dt_fsc_month_last,
            MAX(qty_actual) AS qty_actual_kpi
        FROM SupplyChain_Lakehouse.dbo.gld_forecast_kpi_metric
        GROUP BY id_item_sku, code_warehouse, --code_customer_group,
                 dt_fsc_month_first, dt_fsc_month_last
    ) k
        ON  ISNULL(s.id_item_sku, '')         = ISNULL(k.id_item_sku, '')
        AND ISNULL(s.code_warehouse, '')      = ISNULL(k.code_warehouse, '')
        --AND ISNULL(s.code_customer_group, '') = ISNULL(k.code_customer_group, '')
        AND s.dt_fsc_month_first              = k.dt_fsc_month_first
        AND s.dt_fsc_month_last               = k.dt_fsc_month_last
    WHERE ISNULL(s.qty_actual_slv, 0) <> ISNULL(k.qty_actual_kpi, 0)
) mismatch

UNION ALL

-- ================================================================
-- DQ_02: Naive forecast qty — Gold KPI vs Silver Naive
-- ================================================================
SELECT
    'DQ_02',
    'Naive forecast qty: Gold KPI vs Silver Naive',
    CASE WHEN mismatch.cnt = 0 THEN 1 ELSE 0 END
FROM (
    SELECT COUNT(*) AS cnt
    FROM (
        SELECT
            TRIM(id_item_sku)                AS id_item_sku,
            TRIM(code_warehouse)             AS code_warehouse,
            --TRIM(code_customer_group)        AS code_customer_group,
            CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first,
            CAST(dt_fsc_month_last AS DATE)  AS dt_fsc_month_last,
            SUM(qty_demand)                  AS qty_naive_slv
        FROM SupplyChain_Lakehouse.dbo.slv_naive_forecast_monthly
        GROUP BY TRIM(id_item_sku), TRIM(code_warehouse), --TRIM(code_customer_group),
                 CAST(dt_fsc_month_first AS DATE), CAST(dt_fsc_month_last AS DATE)
    ) s
    FULL OUTER JOIN (
        SELECT
            id_item_sku, code_warehouse, --code_customer_group,
            dt_fsc_month_first, dt_fsc_month_last,
            MAX(qty_naive_forecast) AS qty_naive_kpi
        FROM SupplyChain_Lakehouse.dbo.gld_forecast_kpi_metric
        GROUP BY id_item_sku, code_warehouse, --code_customer_group,
                 dt_fsc_month_first, dt_fsc_month_last
    ) k
        ON  ISNULL(s.id_item_sku, '')         = ISNULL(k.id_item_sku, '')
        AND ISNULL(s.code_warehouse, '')      = ISNULL(k.code_warehouse, '')
        --AND ISNULL(s.code_customer_group, '') = ISNULL(k.code_customer_group, '')
        AND s.dt_fsc_month_first              = k.dt_fsc_month_first
        AND s.dt_fsc_month_last               = k.dt_fsc_month_last
    WHERE ISNULL(s.qty_naive_slv, 0) <> ISNULL(k.qty_naive_kpi, 0)
) mismatch

UNION ALL

-- ================================================================
-- DQ_03: Duplicate qty_actual per key in Gold KPI
-- ================================================================
SELECT
    'DQ_03',
    'No duplicate qty_actual per key in Gold KPI',
    CASE WHEN dup.cnt = 0 THEN 1 ELSE 0 END
FROM (
    SELECT COUNT(*) AS cnt
    FROM (
        SELECT id_item_sku, code_warehouse, --code_customer_group,
               dt_fsc_month_first, dt_fsc_month_last
        FROM SupplyChain_Lakehouse.dbo.gld_forecast_kpi_metric
        GROUP BY id_item_sku, code_warehouse, --code_customer_group,
                 dt_fsc_month_first, dt_fsc_month_last
        HAVING COUNT(DISTINCT qty_actual) > 1
    ) t
) dup

UNION ALL

-- ================================================================
-- DQ_04: Gold Flat (Naive) vs Silver Naive — rows & qty
-- ================================================================
SELECT
    'DQ_04',
    'Gold Flat (Naive) vs Silver Naive: rows & qty',
    CASE
        WHEN g.total_rows = s.total_rows
         AND ABS(ISNULL(g.total_qty, 0) - ISNULL(s.total_qty, 0)) < 0.01
        THEN 1 ELSE 0
    END
FROM (
    SELECT COUNT(*) AS total_rows, SUM(qty) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.gld_flat_forecast_actual
    WHERE code_horizon = 'Naive forecast'
       OR name_version = 'Naive Forecast'
) g
CROSS JOIN (
    SELECT COUNT(*) AS total_rows, SUM(qty_demand) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.slv_naive_forecast_monthly
) s

UNION ALL

-- ================================================================
-- DQ_05: Gold Flat (Actual) vs Silver Actual — qty
-- ================================================================
SELECT
    'DQ_05',
    'Gold Flat (Actual) vs Silver Actual: qty',
    CASE
        WHEN ABS(ISNULL(g.total_qty, 0) - ISNULL(s.total_qty, 0)) < 0.001
        THEN 1 ELSE 0
    END
FROM (
    SELECT SUM(qty) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.gld_flat_forecast_actual
    WHERE code_horizon = 'Actual demand'
) g
CROSS JOIN (
    SELECT SUM(qty_demand) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.slv_actual_demand_monthly
) s

UNION ALL

-- ================================================================
-- DQ_06: Gold Flat (Forecast) vs Silver Forecast — rows & qty
-- ================================================================
SELECT
    'DQ_06',
    'Gold Flat (Forecast) vs Silver Forecast: rows & qty',
    CASE
        WHEN g.total_rows = s.total_rows
         AND ABS(ISNULL(g.total_qty, 0) - ISNULL(s.total_qty, 0)) < 0.01
        THEN 1 ELSE 0
    END
FROM (
    SELECT COUNT(*) AS total_rows, SUM(qty) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.gld_flat_forecast_actual
    WHERE code_status = 'Forecast'
) g
CROSS JOIN (
    SELECT COUNT(*) AS total_rows, SUM(qty_forecast) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.slv_forecast_demand_monthly
) s

UNION ALL

-- ================================================================
-- DQ_07: Open Order — Bronze vs Silver
-- ================================================================
SELECT
    'DQ_07',
    'Open Order: Bronze vs Silver (rows, open qty, backorder qty)',
    CASE
        WHEN b.total_rows = s.total_rows
         AND b.sum_qty_open = s.sum_qty_open
         AND b.sum_qty_backorder = s.sum_qty_backorder
        THEN 1 ELSE 0
    END
FROM (
    SELECT
        COUNT(*)                                           AS total_rows,
        SUM(CAST(T1.qty_ordered - T1.qty_shipped AS INT)) AS sum_qty_open,
        SUM(CAST(T1.qty_backordered AS INT))               AS sum_qty_backorder
    FROM SupplyChain_Lakehouse.dbo.brz_wholesale_codis_afi__codatan T1
    INNER JOIN SupplyChain_Lakehouse.dbo.brz_wholesale_codis_afi__comast T3
        ON T1.id_order = T3.id_order
    WHERE (T1.qty_backordered <> 0 OR T1.qty_ordered <> 0)
      AND T1.amt_selling_price <> 0
      AND T3.code_record_type <> 'X'
      AND T1.qty_ordered >= 0
) b
CROSS JOIN (
    SELECT
        COUNT(*)            AS total_rows,
        SUM(qty_open_order) AS sum_qty_open,
        SUM(qty_backorder)  AS sum_qty_backorder
    FROM SupplyChain_Lakehouse.dbo.slv_open_order_line_level
) s

UNION ALL

-- ================================================================
-- DQ_08: Invoice Detail — Silver vs Bronze source
-- ================================================================
SELECT
    'DQ_08',
    'Invoice Detail: Silver vs Bronze source (rows, qty, amt)',
    CASE
        WHEN t.total_rows = s.total_rows
         AND ISNULL(t.total_qty, 0) = ISNULL(s.total_qty, 0)
         AND ABS(ISNULL(t.total_amt, 0) - ISNULL(s.total_amt, 0)) < 0.01
        THEN 1 ELSE 0
    END
FROM (
    SELECT COUNT(*) AS total_rows, SUM(qty_shipped) AS total_qty, SUM(amt_net_sales) AS total_amt
    FROM SupplyChain_Lakehouse.dbo.slv_invoice_detail_line_level
) t
CROSS JOIN (
    SELECT COUNT(*) AS total_rows, SUM(INV.qty_shipped) AS total_qty, SUM(INV.amt_net_sales) AS total_amt
    FROM SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2 AS INV
    LEFT JOIN SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2 AS IH
        ON INV.id_invoice = IH.id_invoice
        AND INV.dt_invoice = IH.dt_invoice
        AND INV.dt_order   = IH.dt_order
        AND INV.id_order   = IH.id_order
    WHERE INV.id_invoice IS NOT NULL
      AND INV.dt_invoice >= '2023-01-01'
) s

UNION ALL

-- ================================================================
-- DQ_09: Forecast Demand — Bronze vs Silver total qty
-- ================================================================
SELECT
    'DQ_09',
    'Forecast Demand: Bronze vs Silver total qty',
    CASE
        WHEN ABS(ISNULL(b.total_qty, 0) - ISNULL(s.total_qty, 0)) < 0.01
        THEN 1 ELSE 0
    END
FROM (
    SELECT SUM(qty_resultant_forecast + qty_promotional_lift) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2 AS f
    INNER JOIN SupplyChain_Lakehouse.dbo.ref_forecast_cycle AS c
        ON CAST(f.ts_snapshot AS DATE) = c.dt_forecast_snapshot
    WHERE
        DATEFROMPARTS(CAST(f.num_fiscal_month / 100 AS INT), CAST(f.num_fiscal_month % 100 AS INT), 1)
            >= DATEADD(MONTH, -36, DATEADD(YEAR, DATEDIFF(YEAR, 0, DATEADD(MONTH, -6, GETDATE())), 0))
        AND DATEFROMPARTS(CAST(f.num_fiscal_month / 100 AS INT), CAST(f.num_fiscal_month % 100 AS INT), 1)
            <= DATEADD(MONTH, 12, DATEADD(YEAR, DATEDIFF(YEAR, 0, DATEADD(MONTH, 6, GETDATE())), 0))
) b
CROSS JOIN (
    SELECT SUM(qty_forecast) AS total_qty
    FROM SupplyChain_Lakehouse.dbo.slv_forecast_demand_monthly
) s

UNION ALL

-- ================================================================
-- DQ_10: Null customer_group in slv_actual_demand_monthly
-- ================================================================
SELECT
    'DQ_10',
    'No null customer_group in slv_actual_demand_monthly',
    CASE WHEN SUM(CASE WHEN code_customer_group IS NULL THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END
FROM SupplyChain_Lakehouse.dbo.slv_actual_demand_monthly

UNION ALL

-- ================================================================
-- DQ_11: Null customer_group in slv_invoice_detail_line_level
-- ================================================================
SELECT
    'DQ_11',
    'No null customer_group in slv_invoice_detail_line_level',
    CASE WHEN SUM(CASE WHEN code_customer_group IS NULL THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END
FROM SupplyChain_Lakehouse.dbo.slv_invoice_detail_line_level

UNION ALL

-- ================================================================
-- DQ_12: Null customer_group in slv_forecast_demand_monthly
-- ================================================================
SELECT
    'DQ_12',
    'No null customer_group in slv_forecast_demand_monthly',
    CASE WHEN SUM(CASE WHEN code_customer_group IS NULL THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END
FROM SupplyChain_Lakehouse.dbo.slv_forecast_demand_monthly

UNION ALL

-- ================================================================
-- DQ_13: Actual Demand = Invoice + Open Order (qty match)
-- ================================================================
SELECT
    'DQ_13',
    'Actual Demand = Invoice + Open Order (qty match)',
    CASE
        WHEN ABS(ISNULL(t.target_invoice_qty, 0)   - ISNULL(si.source_invoice_qty, 0))   < 0.01
         AND ABS(ISNULL(t.target_open_order_qty, 0) - ISNULL(so.source_open_order_qty, 0)) < 0.01
        THEN 1 ELSE 0
    END
FROM (
    SELECT
        SUM(CASE WHEN code_status = 'Invoice'   THEN qty_demand ELSE 0 END) AS target_invoice_qty,
        SUM(CASE WHEN code_status = 'Open Order' THEN qty_demand ELSE 0 END) AS target_open_order_qty
    FROM SupplyChain_Lakehouse.dbo.slv_actual_demand_monthly
) t
CROSS JOIN (
    SELECT SUM(INV.qty_shipped) AS source_invoice_qty
    FROM SupplyChain_Lakehouse.dbo.slv_invoice_detail_line_level AS INV
    INNER JOIN SupplyChain_Lakehouse.dbo.ref_calendar AS CAL
        ON CAL.dt_date = DATEADD(DAY, -INV.num_lead_time_days, INV.dt_current_request)
    CROSS JOIN (
        SELECT TOP 1 num_fsc_year
        FROM SupplyChain_Lakehouse.dbo.ref_calendar
        WHERE dt_date = CAST(GETDATE() AS DATE)
        ORDER BY dt_date DESC
    ) CF
    WHERE INV.qty_shipped > 0
      AND CAL.num_fsc_year BETWEEN CF.num_fsc_year - 3 AND CF.num_fsc_year + 1
) si
CROSS JOIN (
    SELECT SUM(OO.qty_open_order) AS source_open_order_qty
    FROM SupplyChain_Lakehouse.dbo.slv_open_order_line_level AS OO
    INNER JOIN SupplyChain_Lakehouse.dbo.ref_calendar AS CAL
        ON CAL.dt_date = DATEADD(DAY, -OO.num_lead_time_days, OO.dt_current_request)
    CROSS JOIN (
        SELECT TOP 1 num_fsc_year
        FROM SupplyChain_Lakehouse.dbo.ref_calendar
        WHERE dt_date = CAST(GETDATE() AS DATE)
        ORDER BY dt_date DESC
    ) CF
    WHERE OO.code_allocation_flag = '2'
      AND CAL.num_fsc_year BETWEEN CF.num_fsc_year - 3 AND CF.num_fsc_year + 1
) so;
