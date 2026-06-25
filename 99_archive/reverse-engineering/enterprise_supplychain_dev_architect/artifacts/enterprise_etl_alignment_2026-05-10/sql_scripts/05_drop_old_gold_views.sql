-- 05_drop_old_gold_views.sql
-- Drop 7 old Gold views (vw_*) in ForecastAccuracy_DW schema.
-- Note: Gold schema name (_DW) is NOT changed — only view prefix.

DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_DimCalendar;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_DimCustomerGrouping;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_DimForecastHorizon;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_DimProduct;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_DimWarehouse;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_FactForecastActual;
DROP VIEW IF EXISTS ForecastAccuracy_DW.vw_FactForecastKpi;
