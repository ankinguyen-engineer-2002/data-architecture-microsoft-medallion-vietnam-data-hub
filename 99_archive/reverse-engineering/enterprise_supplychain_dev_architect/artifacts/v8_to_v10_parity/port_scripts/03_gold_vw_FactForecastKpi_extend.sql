-- =============================================================================
-- 03_gold_vw_FactForecastKpi_extend.sql
-- Purpose: Extend Gold vw_FactForecastKpi to compute 7 missing derived metrics
-- Target:  ForecastAccuracy_DW.vw_FactForecastKpi (Gold WH)
-- Source:  Same as current view (no new sources)
--
-- Status:  DRAFT — needs Aric approval.
-- Risk:    LOW — view replace, no data loss. ALTER TABLE FactForecastKpi
--          needed afterward to receive new cols from pl_sc_gold rerun.
-- Cols added: 7 (QtyNaiveFcstError, QtyAbsNaiveFcstError, QtySquaredFcstError,
--                QtySquaredNaiveFcstError, ValidObsFlag, ValidActualNonzeroFlag,
--                AbsPctError) — exact business logic from v8 nb_gld_forecast_kpi_metric
-- =============================================================================

CREATE OR ALTER VIEW ForecastAccuracy_DW.vw_FactForecastKpi AS
WITH
fc AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        TRIM(HorizonCode) AS h, CAST(Snapshot AS DATE) AS ds,
        CAST(SUM(QtyForecast) AS FLOAT) AS qf
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.ForecastDemandMonthly
    WHERE HorizonCode IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE),
        TRIM(HorizonCode), CAST(Snapshot AS DATE)
),
act AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qa
    FROM SupplyChain_Processing_Warehouse.SalesHistory_ENH.ActualDemandMonthly
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE)
),
nv AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qn
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.NaiveForecastMonthly
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE)
),
dk AS (
    SELECT i, w, mf, ml FROM fc
    UNION SELECT i, w, mf, ml FROM act
    UNION SELECT i, w, mf, ml FROM nv
),
sp AS (
    SELECT K.i, K.w, K.mf, K.ml, H.HorizonCode AS h
    FROM dk K
    CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.ForecastHorizon H
)
SELECT
    sp.i AS ItemSKU,
    sp.w AS WarehouseCode,
    sp.mf AS FSCMonthFirst,
    sp.ml AS FSCMonthLast,
    sp.h AS HorizonCode,
    fc.ds AS Snapshot,

    -- Quantities (existing 3)
    CAST(fc.qf AS FLOAT)            AS QtyForecast,
    CAST(act.qa AS FLOAT)           AS QtyActual,
    CAST(nv.qn AS FLOAT)            AS QtyNaiveForecast,

    -- Forecast error (existing 2)
    CAST(COALESCE(fc.qf,0) - COALESCE(act.qa,0) AS FLOAT)
                                    AS QtyFcstError,
    CAST(ABS(COALESCE(fc.qf,0) - COALESCE(act.qa,0)) AS FLOAT)
                                    AS QtyAbsFcstError,

    -- ── NEW: Naive forecast error (2 cols) ──
    CAST(COALESCE(nv.qn,0) - COALESCE(act.qa,0) AS FLOAT)
                                    AS QtyNaiveFcstError,
    CAST(ABS(COALESCE(nv.qn,0) - COALESCE(act.qa,0)) AS FLOAT)
                                    AS QtyAbsNaiveFcstError,

    -- ── NEW: Squared error components for RMSE (2 cols) ──
    CAST(POWER(COALESCE(fc.qf,0) - COALESCE(act.qa,0), 2) AS FLOAT)
                                    AS QtySquaredFcstError,
    CAST(POWER(COALESCE(nv.qn,0) - COALESCE(act.qa,0), 2) AS FLOAT)
                                    AS QtySquaredNaiveFcstError,

    -- ── NEW: Validity flags (2 cols) ──
    CAST(CASE WHEN act.qa IS NOT NULL AND fc.qf IS NOT NULL THEN 1 ELSE 0 END AS INT)
                                    AS ValidObsFlag,
    CAST(CASE WHEN act.qa IS NOT NULL AND act.qa <> 0       THEN 1 ELSE 0 END AS INT)
                                    AS ValidActualNonzeroFlag,

    -- ── NEW: Absolute percentage error (MAPE component) (1 col) ──
    CAST(CASE
        WHEN act.qa IS NOT NULL AND act.qa <> 0
            THEN ABS((COALESCE(fc.qf,0) - act.qa) / act.qa)
        ELSE NULL
    END AS FLOAT)                   AS AbsPctError,

    -- Audit
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT

FROM sp
LEFT JOIN fc  ON sp.i=fc.i  AND sp.w=fc.w  AND sp.mf=fc.mf  AND sp.ml=fc.ml AND sp.h=fc.h
LEFT JOIN act ON sp.i=act.i AND sp.w=act.w AND sp.mf=act.mf AND sp.ml=act.ml
LEFT JOIN nv  ON sp.i=nv.i  AND sp.w=nv.w  AND sp.mf=nv.mf  AND sp.ml=nv.ml;

-- =============================================================================
-- Output: 18 data cols (matches v8 fact_forecast_kpi exact) + LoadDT = 19 total
-- After this view ALTER:
-- 1. Drop ForecastAccuracy_DW.FactForecastKpi base table (or ALTER ADD cols)
-- 2. Run pl_sc_gold to repopulate FactForecastKpi via CTAS from extended view
-- 3. Verify row count ≈ 36.4M (unchanged), col count = 19
-- =============================================================================
