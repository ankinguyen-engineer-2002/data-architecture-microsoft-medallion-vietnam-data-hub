-- Target database: SupplyChain_Processing_Warehouse
-- Mart: shared
-- Wave order: Shared W00 Staging prerequisites
-- 2026-07-09 CUTOVER: DemandForecastSnapshotDaily physical Staging load is NO LONGER required
-- for Forecast Accuracy / Inventory Health silver paths. Those views now read EL directly:
--   [$(Databricks)].SupplyChain_Enh.DemandForecastSnapshotDaily
-- This procedure is intentionally a no-op so existing pipeline/wave callers do not fail
-- and do not burn CU reloading ~10B-row staging cache.
-- Keep the procedure name for orchestration compatibility until pipeline steps are removed.
-- Optional: drop Staging.DemandForecastSnapshotDaily after DQ rules that compare
-- Staging_Wrk vs Staging physical are retired.
CREATE PROCEDURE [dbo].[Usp_Refresh_Shared_Staging]
AS
BEGIN
    SET NOCOUNT ON;

    -- Deprecated staging materialization for DemandForecastSnapshotDaily.
    -- Former body:
    -- EXEC ETL_Framework.DW_Developer.usp_UpdateCuratedTableFromView_DateRange
    --     'SupplyChain_Processing_Warehouse', 'Staging', 'DemandForecastSnapshotDaily',
    --     'dfcSnapshot', 'dfcSnapshot', -15;

    PRINT 'Usp_Refresh_Shared_Staging: no-op after 2026-07-09 DemandForecast direct-EL cutover.';
END;
