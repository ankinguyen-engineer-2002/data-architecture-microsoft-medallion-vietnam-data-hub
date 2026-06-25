-- Source: SupplyChain_Warehouse.bronze.vw_ref_forecast_horizon
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_ref_forecast_horizon AS
SELECT 'Lag-0' AS code_horizon, 1 AS num_rank UNION ALL
SELECT 'Lag-1', 2 UNION ALL
SELECT 'Lag-2', 3 UNION ALL
SELECT 'Lag-3', 4 UNION ALL
SELECT 'Lag-4', 5 UNION ALL
SELECT '>Lag-4', 6 UNION ALL
SELECT 'Actual demand', 7 UNION ALL
SELECT 'Naive forecast', 8
