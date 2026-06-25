-- Source: SupplyChain_Warehouse.silver.vw_slv_invoice_weekly
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW silver.vw_slv_invoice_weekly AS
WITH current_fiscal AS (
    SELECT TOP 1 num_fsc_year FROM bronze.ref_calendar WHERE dt_date = CAST(GETDATE() AS DATE)
)
SELECT
    INV.id_account_ship_to, INV.id_item_sku, INV.code_warehouse, INV.code_customer_group,
    CAL.dt_fsc_week_first, CAL.dt_fsc_week_last,
    SUM(INV.qty_shipped) AS qty_shipped,
    SUM(INV.amt_net_sales) AS amt_net_sales,
    SUM(INV.amt_invoice) AS amt_invoice,
    SUM(INV.amt_freight) AS amt_freight,
    COUNT(*) AS num_invoice_lines,
    COUNT(DISTINCT INV.id_invoice) AS num_distinct_invoices
FROM silver.slv_invoice_detail_line_level AS INV
INNER JOIN bronze.ref_calendar AS CAL ON CAL.dt_date = INV.dt_invoice
CROSS JOIN current_fiscal AS CF
WHERE INV.qty_shipped > 0 AND CAL.num_fsc_year >= CF.num_fsc_year - 3
GROUP BY INV.id_account_ship_to, INV.id_item_sku, INV.code_warehouse,
    INV.code_customer_group, CAL.dt_fsc_week_first, CAL.dt_fsc_week_last
