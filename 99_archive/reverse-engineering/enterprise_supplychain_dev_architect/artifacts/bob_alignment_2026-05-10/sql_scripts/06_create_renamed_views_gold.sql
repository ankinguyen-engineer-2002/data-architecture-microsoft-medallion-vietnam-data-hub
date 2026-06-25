-- 06_create_renamed_views_gold.sql
-- 7 Gold views recreated with v_ prefix. 3-part-name refs to Processing schemas updated.
-- Source: etl/gold_views.sql, transformed.

-- ============================================================
-- Gold Views — ForecastAccuracy_DW Serving Layer
-- ============================================================
-- Layer: Gold. Pattern: cross-DB 3-part name from Processing WH + CAST FLOAT + LoadDT.
-- Source: SupplyChain_Gold_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- ForecastAccuracy_DW.v_DimCalendar ----
CREATE   VIEW ForecastAccuracy_DW.v_DimCalendar AS
SELECT
    -- Keys (existing + new)
    CAL.SKDate                          AS DateSK,
    CAL.MapicsDate                      AS MapicsDate,
    CAL.Date                            AS [Date],
    CAL.Datetime                        AS Datetime,
    CAL.Calendar                        AS Calendar,

    -- Calendar Day
    CAL.CalendarDateName                AS CalendarDateName,
    CAL.CalDateIndicatorNum             AS CalDateIndicatorNum,
    CAL.CalDayOfWeekNum                 AS CalDayOfWeekNum,
    CAL.CalDayOfWeekName                AS CalDayOfWeekName,
    CAL.CalDayOfMonthNum                AS CalDayOfMonthNum,
    CAL.CalDayOfYearNum                 AS CalDayOfYearNum,

    -- Calendar Week
    CAL.CalWeekNum                      AS CalWeekNum,
    CAL.CalWeekIndicatorNum             AS CalWeekIndicatorNum,
    CAL.CalWeekYearNum                  AS CalWeekYearNum,
    CAL.CalWeekYearName                 AS CalWeekYearName,
    CAL.CalWeekFirst                    AS CalWeekFirst,
    CAL.CalWeekLast                     AS CalWeekLast,
    CAL.CalWeekOfMonthNum               AS CalWeekOfMonthNum,

    -- Calendar Month
    CAL.CalMonthNum                     AS CalMonthNum,
    CAL.CalMonthIndicatorNum            AS CalMonthIndicatorNum,
    CAL.CalMonthYearNum                 AS CalMonthYearNum,
    CAL.CalMonthName                    AS CalMonthName,
    CAL.CalMonthYearName                AS CalMonthYearName,
    CAL.CalMonthFirst                   AS CalMonthFirst,
    CAL.CalMonthLast                    AS CalMonthLast,

    -- Calendar Quarter
    CAL.CalQuarterNum                   AS CalQuarterNum,
    CAL.CalQuarterName                  AS CalQuarterName,
    CAL.CalQuarterIndicatorNum          AS CalQuarterIndicatorNum,
    CAL.CalQuarterYearNum               AS CalQuarterYearNum,
    CAL.CalQuarterYearName              AS CalQuarterYearName,

    -- Calendar Semester + Year
    CAL.CalSemesterNum                  AS CalSemesterNum,
    CAL.CalSemesterYearNum              AS CalSemesterYearNum,
    CAL.CalYearNum                      AS CalYearNum,
    CAL.CalYearName                     AS CalYearName,
    CAL.CalYearIndicatorNum             AS CalYearIndicatorNum,

    -- Fiscal Day
    CAL.FiscalDate                      AS FiscalDate,
    CAL.FiscalDateName                  AS FiscalDateName,
    CAL.FSCDateIndicatorNum             AS FSCDateIndicatorNum,
    CAL.FSCDayOfWeekNum                 AS FSCDayOfWeekNum,
    CAL.FSCDayOfWeekName                AS FSCDayOfWeekName,
    CAL.FSCDayOfMonthNum                AS FSCDayOfMonthNum,
    CAL.FSCDayOfYearNum                 AS FSCDayOfYearNum,

    -- Fiscal Week
    CAL.FSCWeekNum                      AS FSCWeekNum,
    CAL.FSCWeekIndicatorNum             AS FSCWeekIndicatorNum,
    CAL.FSCWeekYearNum                  AS FSCWeekYearNum,
    CAL.FSCWeekYearName                 AS FSCWeekYearName,
    CAL.FSCWeekFirst                    AS FSCWeekFirst,
    CAL.FSCWeekLast                     AS FSCWeekLast,
    CAL.FSCWeekOfMonthNum               AS FSCWeekOfMonthNum,

    -- Fiscal Month (existing + new)
    CAL.FSCMonthNum                     AS FSCMonthNum,
    CAL.FSCMonthIndicatorNum            AS FSCMonthIndicatorNum,
    CAL.FSCMonthYearNum                 AS FSCMonthYearNum,
    CAL.FSCMonthName                    AS FSCMonthName,
    CAL.FSCMonthYearName                AS FSCMonthYearName,
    CAL.FSCMonthFirst                   AS FSCMonthFirst,
    CAL.FSCMonthLast                    AS FSCMonthLast,

    -- Fiscal Quarter
    CAL.FSCQuarterNum                   AS FSCQuarterNum,
    CAL.FSCQuarterName                  AS FSCQuarterName,
    CAL.FSCQuarterIndicatorNum          AS FSCQuarterIndicatorNum,
    CAL.FSCQuarterYearNum               AS FSCQuarterYearNum,
    CAL.FSCQuarterYearName              AS FSCQuarterYearName,
    CAL.FSCQuarterFirst                 AS FSCQuarterFirst,
    CAL.FSCQuarterLast                  AS FSCQuarterLast,

    -- Fiscal Semester + Year
    CAL.FSCSemesterNum                  AS FSCSemesterNum,
    CAL.FSCSemesterYearNum              AS FSCSemesterYearNum,
    CAL.FSCYearNum                      AS FSCYearNum,
    CAL.FSCYearName                     AS FSCYearName,
    CAL.FSCYearIndicatorNum             AS FSCYearIndicatorNum,
    CAL.FSCYearFirst                    AS FSCYearFirst,
    CAL.FSCYearLast                     AS FSCYearLast,

    -- Holiday + Working Day
    CAL.HolidayIndicatorCode            AS HolidayIndicatorCode,
    CAL.HolidayName                     AS HolidayName,
    CAL.WorkingDayCode                  AS WorkingDayCode,
    CAL.WeekdayWeekendCode              AS WeekdayWeekendCode,

    -- Audit
    CAST(GETUTCDATE() AS DATETIME2(6))  AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Calendar AS CAL
WHERE CAL.SKDate IS NOT NULL;

GO

-- ---- ForecastAccuracy_DW.v_DimCustomerGrouping ----
CREATE VIEW ForecastAccuracy_DW.v_DimCustomerGrouping AS
SELECT DISTINCT CustomerGroupCode, Customer,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.CustomerGrouping
WHERE CustomerGroupCode IS NOT NULL

GO

-- ---- ForecastAccuracy_DW.v_DimForecastHorizon ----

CREATE   VIEW ForecastAccuracy_DW.v_DimForecastHorizon AS
SELECT HorizonCode, [Rank], CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon

GO

-- ---- ForecastAccuracy_DW.v_DimProduct ----

CREATE VIEW ForecastAccuracy_DW.v_DimProduct AS
SELECT *, CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.Staging_Wrk.ProductEdw

GO

-- ---- ForecastAccuracy_DW.v_DimWarehouse ----
CREATE VIEW ForecastAccuracy_DW.v_DimWarehouse AS
SELECT * FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Warehouse

GO

-- ---- ForecastAccuracy_DW.v_FactForecastActual ----
CREATE VIEW ForecastAccuracy_DW.v_FactForecastActual AS
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Actual demand' AS VARCHAR(20)) AS HorizonCode, StatusCode, VersionName, CAST(QtyDemand AS FLOAT) AS Qty,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    HorizonCode, StatusCode, VersionCode, CAST(QtyForecast AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Naive forecast' AS VARCHAR(20)), StatusCode, VersionName, CAST(QtyDemand AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly

GO

-- ---- ForecastAccuracy_DW.v_FactForecastKpi ----
CREATE   VIEW ForecastAccuracy_DW.v_FactForecastKpi AS
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
LEFT JOIN fc  ON sp.i=fc.i  AND sp.w=fc.w  AND sp.mf=fc.mf  AND sp.ml=fc.ml AND sp.h=fc.h
LEFT JOIN act ON sp.i=act.i AND sp.w=act.w AND sp.mf=act.mf AND sp.ml=act.ml
LEFT JOIN nv  ON sp.i=nv.i  AND sp.w=nv.w  AND sp.mf=nv.mf  AND sp.ml=nv.ml;

GO
