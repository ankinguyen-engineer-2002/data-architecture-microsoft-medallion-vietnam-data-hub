-- =============================================================================
-- 04_silver_vw_ForecastHorizon_extend.sql
-- Purpose: Add Rank column to ForecastHorizon (was num_rank in v8)
-- Source:  Hardcoded values (per v8 nb_ref_forecast_horizon)
--
-- Status:  DRAFT — needs Aric approval.
-- Risk:    LOW — only 8 rows in this dim.
-- =============================================================================

CREATE OR ALTER VIEW ReferenceMaster_ENH.vw_ForecastHorizon AS
SELECT 'Lag-0'          AS HorizonCode, 1 AS [Rank] UNION ALL
SELECT 'Lag-1',          2 UNION ALL
SELECT 'Lag-2',          3 UNION ALL
SELECT 'Lag-3',          4 UNION ALL
SELECT 'Lag-4',          5 UNION ALL
SELECT '>Lag-4',         6 UNION ALL
SELECT 'Actual demand',  7 UNION ALL
SELECT 'Naive forecast', 8;

-- After this:
-- 1. ALTER TABLE ReferenceMaster_ENH.ForecastHorizon ADD Rank INT
--    OR DROP + recreate (8 rows only, safe)
-- 2. Run usp_GenericLoad for ForecastHorizon
-- 3. Update Gold vw_DimForecastHorizon to expose Rank
--
-- Gold view update:
-- CREATE OR ALTER VIEW ForecastAccuracy_DW.vw_DimForecastHorizon AS
-- SELECT HorizonCode, [Rank], CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
-- FROM SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.ForecastHorizon
-- =============================================================================
