-- SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_FactForecastKpi
CREATE   VIEW [ForecastAccuracy_DW_Wrk].[v_FactForecastKpi] AS
WITH
fc AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        TRIM(HorizonCode) AS h, CAST(Snapshot AS DATE) AS ds,
        CAST(SUM(QtyForecast) AS FLOAT) AS qf
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
    WHERE HorizonCode IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE),
        TRIM(HorizonCode), CAST(Snapshot AS DATE)
),
act AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qa
    FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE)
),
nv AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qn
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly
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
    CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon H
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
LEFT JOIN fc
    ON (sp.i = fc.i OR (sp.i IS NULL AND fc.i IS NULL))
   AND (sp.w = fc.w OR (sp.w IS NULL AND fc.w IS NULL))
   AND (sp.mf = fc.mf OR (sp.mf IS NULL AND fc.mf IS NULL))
   AND (sp.ml = fc.ml OR (sp.ml IS NULL AND fc.ml IS NULL))
   AND (sp.h = fc.h OR (sp.h IS NULL AND fc.h IS NULL))
LEFT JOIN act
    ON (sp.i = act.i OR (sp.i IS NULL AND act.i IS NULL))
   AND (sp.w = act.w OR (sp.w IS NULL AND act.w IS NULL))
   AND (sp.mf = act.mf OR (sp.mf IS NULL AND act.mf IS NULL))
   AND (sp.ml = act.ml OR (sp.ml IS NULL AND act.ml IS NULL))
LEFT JOIN nv
    ON (sp.i = nv.i OR (sp.i IS NULL AND nv.i IS NULL))
   AND (sp.w = nv.w OR (sp.w IS NULL AND nv.w IS NULL))
   AND (sp.mf = nv.mf OR (sp.mf IS NULL AND nv.mf IS NULL))
   AND (sp.ml = nv.ml OR (sp.ml IS NULL AND nv.ml IS NULL));
