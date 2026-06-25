-- Source: SupplyChain_Warehouse.silver.vw_slv_forecast_demand_monthly
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW silver.vw_slv_forecast_demand_monthly AS
WITH RawForecast AS (
    SELECT 
        f.id_item_sku, f.code_warehouse,
        UPPER(f.code_customer_group) AS code_customer_group,
        DATEFROMPARTS(CAST(f.num_fiscal_month / 100 AS INT), CAST(f.num_fiscal_month % 100 AS INT), 1) AS dt_fiscal_month,
        CAST(f.ts_snapshot AS DATE) AS dt_snapshot,
        f.qty_resultant_forecast, f.qty_promotional_lift
    FROM bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily AS f
    INNER JOIN bronze.ref_forecast_cycle AS c
        ON CAST(f.ts_snapshot AS DATE) = c.dt_forecast_snapshot
),
CalculatedForecast AS (
    SELECT 
        FC.id_item_sku, FC.code_warehouse, FC.code_customer_group,
        CAL.dt_fsc_month_first, CAL.dt_fsc_month_last, FC.dt_snapshot,
        CASE 
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 0 THEN 'Lag-0'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 1 THEN 'Lag-1'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 2 THEN 'Lag-2'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 3 THEN 'Lag-3'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 4 THEN 'Lag-4'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month)) - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) > 4 THEN '>Lag-4'
        END AS code_horizon,
        CAST(SUM(FC.qty_resultant_forecast + FC.qty_promotional_lift) AS FLOAT) AS qty_forecast,
        CAST(CONCAT('V ', FORMAT(FC.dt_snapshot, 'yyyy.MM')) AS VARCHAR(20)) AS code_version,
        'Forecast' AS code_status
    FROM RawForecast AS FC
    INNER JOIN bronze.ref_calendar AS CAL ON CAL.dt_date = FC.dt_fiscal_month
    WHERE FC.dt_fiscal_month >= DATEADD(MONTH, -36, DATETRUNC(YEAR, DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))))
      AND FC.dt_fiscal_month <= DATEADD(MONTH, 12, DATETRUNC(YEAR, DATEADD(MONTH, 6, CAST(GETDATE() AS DATE))))
    GROUP BY FC.id_item_sku, FC.code_warehouse, FC.code_customer_group,
        CAL.dt_fsc_month_first, CAL.dt_fsc_month_last, FC.dt_snapshot, FC.dt_fiscal_month
)
SELECT 
    CAST(TRIM(id_item_sku) AS VARCHAR(50)) AS id_item_sku,
    CAST(TRIM(code_warehouse) AS VARCHAR(10)) AS code_warehouse,
    CAST(TRIM(code_customer_group) AS VARCHAR(50)) AS code_customer_group,
    CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first,
    CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
    CAST(dt_snapshot AS DATE) AS dt_snapshot,
    CAST(TRIM(code_horizon) AS VARCHAR(10)) AS code_horizon,
    CAST(qty_forecast AS FLOAT) AS qty_forecast,
    CAST(TRIM(code_version) AS VARCHAR(20)) AS code_version,
    CAST(TRIM(code_status) AS VARCHAR(20)) AS code_status
FROM CalculatedForecast
