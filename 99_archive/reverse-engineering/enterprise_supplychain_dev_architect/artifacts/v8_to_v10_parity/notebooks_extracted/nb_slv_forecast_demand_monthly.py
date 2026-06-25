# ─── Cell 0 ───
# ============================================================================
# [SLV] nb_etl_slv_forecast_demand_monthly
# Silver: Forecast Demand Monthly (aggregate + horizon calculation)
#
# Sources:
#   - brz_supplychain_enh_1__demandforecastsnapshotdaily (incremental)
#   - ref_forecast_cycle (snapshot date mapping)
#   - ref_calendar (fiscal month calendar)
#
# Transformations:
#   - INNER JOINs with forecast cycle + calendar
#   - Aggregate by Item/Warehouse/CustomerGroup/FiscalMonth/Snapshot
#   - Calculate Horizon (month difference logic)
#   - Filter: fiscal month 3 years past to 1 year ahead
#
# Load Type: overwrite (full aggregate each run, no incremental aggregation)
# ============================================================================

TARGET_TABLE = 'slv_forecast_demand_monthly'

LAKEHOUSE = "SupplyChain_Lakehouse"
SCHEMA    = "dbo"
DB        = f'{LAKEHOUSE}.{SCHEMA}'

SQL_TRANSFORM = f'''
WITH RawForecast AS (
    SELECT 
        f.id_item_sku,
        f.code_warehouse,
        UPPER(f.code_customer_group) AS code_customer_group,
        -- Convert YYYYMM (int) to DATE (1st of month)
        MAKE_DATE(
            CAST(f.num_fiscal_month / 100 AS INT), 
            CAST(f.num_fiscal_month % 100 AS INT), 
            1
        ) AS dt_fiscal_month,
        CAST(f.ts_snapshot AS DATE) AS dt_snapshot,
        f.qty_resultant_forecast,
        f.qty_promotional_lift
    FROM {DB}.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2 AS f
    INNER JOIN {DB}.ref_forecast_cycle AS c
        ON CAST(f.ts_snapshot AS DATE) = c.dt_forecast_snapshot
),

CalculatedForecast AS (
    SELECT 
        FC.id_item_sku,
        FC.code_warehouse,
        FC.code_customer_group,
        CAL.dt_fsc_month_first,
        CAL.dt_fsc_month_last,
        FC.dt_snapshot,

        -- Horizon = month difference between FiscalMonth and SnapshotDate
        CASE 
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 0  THEN 'Lag-0'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 1  THEN 'Lag-1'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 2  THEN 'Lag-2'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 3  THEN 'Lag-3'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) = 4  THEN 'Lag-4'
            WHEN (YEAR(FC.dt_fiscal_month)*12 + MONTH(FC.dt_fiscal_month))
               - (YEAR(FC.dt_snapshot)*12 + MONTH(FC.dt_snapshot)) > 4  THEN '>Lag-4'
        END AS code_horizon,

        CAST(SUM(FC.qty_resultant_forecast + FC.qty_promotional_lift) AS DOUBLE) AS qty_forecast,

        CONCAT('V ', DATE_FORMAT(FC.dt_snapshot, 'yyyy.MM')) AS code_version,
        'Forecast' AS code_status

    FROM RawForecast AS FC
    INNER JOIN {DB}.ref_calendar AS CAL
        ON CAL.dt_date = FC.dt_fiscal_month
    WHERE 
        -- Filter: fiscal month from 3 fiscal years ago to 1 fiscal year ahead
        FC.dt_fiscal_month >= ADD_MONTHS(
            DATE_TRUNC('year', ADD_MONTHS(CURRENT_DATE(), -6)), -36
        )
        AND FC.dt_fiscal_month <= ADD_MONTHS(
            DATE_TRUNC('year', ADD_MONTHS(CURRENT_DATE(), 6)), 12
        )
    GROUP BY 
        FC.id_item_sku, FC.code_warehouse, FC.code_customer_group, 
        CAL.dt_fsc_month_first, CAL.dt_fsc_month_last, FC.dt_snapshot, FC.dt_fiscal_month
)

SELECT 
    TRIM(id_item_sku) AS id_item_sku,
    TRIM(code_warehouse) AS code_warehouse,
    TRIM(code_customer_group) AS code_customer_group,
    CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first,
    CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
    CAST(dt_snapshot AS DATE) AS dt_snapshot,
    TRIM(code_horizon) AS code_horizon,
    CAST(qty_forecast AS DOUBLE) AS qty_forecast,
    TRIM(code_version) AS code_version,
    TRIM(code_status) AS code_status
FROM CalculatedForecast
'''


# ─── Cell 1 ───
notebookutils.notebook.run(
    "slv_engine",
    7200,
    {
        "TARGET_TABLE":   TARGET_TABLE,
        "SQL_TRANSFORM":  SQL_TRANSFORM
    }
)

