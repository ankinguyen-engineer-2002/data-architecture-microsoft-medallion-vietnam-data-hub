-- =============================================================================
-- 01_silver_vw_Calendar_extend.sql
-- Purpose: Extend Silver vw_Calendar to surface all 74 columns from v8 dim_calendar
-- Target:  ReferenceMaster_ENH.vw_Calendar (Processing WH)
-- Source:  Enterprise_Lakehouse.MasterData_DW.DimDate (Bronze shortcut)
--
-- Status:  DRAFT — needs Aric approval before execution.
-- Risk:    LOW — view replace is non-destructive (data lives in base table).
--          But dependent objects (Calendar base table, Gold vw_DimCalendar)
--          will need ALTER TABLE / ALTER VIEW too.
-- =============================================================================

-- After ALTER VIEW, also need:
-- (a) ALTER TABLE ReferenceMaster_ENH.Calendar to add 29 new cols
-- (b) Re-run usp_GenericLoad for Calendar to materialize
-- =============================================================================

CREATE OR ALTER VIEW ReferenceMaster_ENH.vw_Calendar AS
SELECT
    -- Keys (existing)
    CAST(DateKey AS INT)                          AS SKDate,
    CAST(MapicsDate AS INT)                       AS MapicsDate,
    CAST(DateID AS DATE)                          AS Date,
    CAST(DateTimeID AS DATE)                      AS Datetime,
    CAST(CalendarDate AS DATE)                    AS Calendar,

    -- Calendar Day (existing + 1 NEW)
    TRIM(CalendarDateName)                        AS CalendarDateName,
    CAST(CalendarDateIndicator AS INT)            AS CalDateIndicatorNum,        -- NEW
    CAST(CalendarDayOfWeek AS INT)                AS CalDayOfWeekNum,
    TRIM(CalendarDayOfWeekName)                   AS CalDayOfWeekName,
    CAST(CalendarDayOfMonth AS INT)               AS CalDayOfMonthNum,
    CAST(CalendarDayOfYear AS INT)                AS CalDayOfYearNum,

    -- Calendar Week (existing + 2 NEW)
    CAST(CalendarWeek AS INT)                     AS CalWeekNum,
    CAST(CalendarWeekIndicator AS INT)            AS CalWeekIndicatorNum,        -- NEW
    CAST(CalendarWeekYear AS INT)                 AS CalWeekYearNum,
    TRIM(CalendarWeekYearName)                    AS CalWeekYearName,
    CAST(CalendarWeekFirstDate AS DATE)           AS CalWeekFirst,
    CAST(CalendarWeekLastDate AS DATE)            AS CalWeekLast,
    CAST(CalendarWeekOfMonth AS INT)              AS CalWeekOfMonthNum,          -- NEW

    -- Calendar Month (existing + 1 NEW)
    CAST(CalendarMonth AS INT)                    AS CalMonthNum,
    CAST(CalendarMonthIndicator AS INT)           AS CalMonthIndicatorNum,       -- NEW
    CAST(CalendarMonthYear AS INT)                AS CalMonthYearNum,
    TRIM(CalendarMonthName)                       AS CalMonthName,
    TRIM(CalendarMonthYearName)                   AS CalMonthYearName,
    CAST(CalendarMonthFirstDate AS DATE)          AS CalMonthFirst,
    CAST(CalendarMonthLastDate AS DATE)           AS CalMonthLast,

    -- Calendar Quarter (existing + 3 NEW)
    CAST(CalendarQuarter AS INT)                  AS CalQuarterNum,
    TRIM(CalendarQuarterName)                     AS CalQuarterName,
    CAST(CalendarQuarterIndicator AS INT)         AS CalQuarterIndicatorNum,     -- NEW
    CAST(CalendarQuarterYear AS INT)              AS CalQuarterYearNum,          -- NEW
    TRIM(CalendarQuarterYearName)                 AS CalQuarterYearName,         -- NEW

    -- Calendar Semester + Year (3 NEW)
    CAST(CalendarSemester AS INT)                 AS CalSemesterNum,             -- NEW
    CAST(CalendarSemesterYear AS INT)             AS CalSemesterYearNum,         -- NEW
    CAST(CalendarYear AS INT)                     AS CalYearNum,
    TRIM(CalendarYearName)                        AS CalYearName,
    CAST(CalendarYearIndicator AS INT)            AS CalYearIndicatorNum,        -- NEW

    -- Fiscal Day (7 NEW)
    CAST(FiscalDate AS DATE)                      AS FiscalDate,                 -- NEW
    TRIM(FiscalDateName)                          AS FiscalDateName,             -- NEW
    CAST(FiscalDateIndicator AS INT)              AS FSCDateIndicatorNum,        -- NEW
    CAST(FiscalDayOfWeek AS INT)                  AS FSCDayOfWeekNum,            -- NEW
    TRIM(FiscalDayOfWeekName)                     AS FSCDayOfWeekName,           -- NEW
    CAST(FiscalDayOfMonth AS INT)                 AS FSCDayOfMonthNum,           -- NEW
    CAST(FiscalDayOfYear AS INT)                  AS FSCDayOfYearNum,            -- NEW

    -- Fiscal Week (existing + 3 NEW)
    CAST(FiscalWeek AS INT)                       AS FSCWeekNum,
    CAST(FiscalWeekIndicator AS INT)              AS FSCWeekIndicatorNum,        -- NEW
    CAST(FiscalWeekYear AS INT)                   AS FSCWeekYearNum,
    TRIM(FiscalWeekYearName)                      AS FSCWeekYearName,            -- NEW
    CAST(FiscalWeekFirstDate AS DATE)             AS FSCWeekFirst,
    CAST(FiscalWeekLastDate AS DATE)              AS FSCWeekLast,
    CAST(FiscalWeekOfMonth AS INT)                AS FSCWeekOfMonthNum,          -- NEW

    -- Fiscal Month (existing + 1 NEW)
    CAST(FiscalMonth AS INT)                      AS FSCMonthNum,
    CAST(FiscalMonthIndicator AS INT)             AS FSCMonthIndicatorNum,       -- NEW
    CAST(FiscalMonthYear AS INT)                  AS FSCMonthYearNum,
    TRIM(FiscalMonthName)                         AS FSCMonthName,
    TRIM(FiscalMonthYearName)                     AS FSCMonthYearName,
    CAST(FiscalMonthFirstDate AS DATE)            AS FSCMonthFirst,
    CAST(FiscalMonthLastDate AS DATE)             AS FSCMonthLast,

    -- Fiscal Quarter (existing + 3 NEW: indicator + first/last via window function)
    CAST(FiscalQuarter AS INT)                    AS FSCQuarterNum,
    TRIM(FiscalQuarterName)                       AS FSCQuarterName,
    CAST(FiscalQuarterIndicator AS INT)           AS FSCQuarterIndicatorNum,     -- NEW
    CAST(FiscalQuarterYear AS INT)                AS FSCQuarterYearNum,
    TRIM(FiscalQuarterYearName)                   AS FSCQuarterYearName,
    MIN(CAST(FiscalMonthFirstDate AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterFirst,            -- NEW
    MAX(CAST(FiscalMonthLastDate  AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterLast,             -- NEW

    -- Fiscal Semester + Year (5 NEW)
    CAST(FiscalSemester AS INT)                   AS FSCSemesterNum,             -- NEW
    CAST(FiscalSemesterYear AS INT)               AS FSCSemesterYearNum,         -- NEW
    CAST(FiscalYear AS INT)                       AS FSCYearNum,
    TRIM(FiscalYearName)                          AS FSCYearName,
    CAST(FiscalYearIndicator AS INT)              AS FSCYearIndicatorNum,        -- NEW
    CAST(FiscalYearFirstDate AS DATE)             AS FSCYearFirst,               -- NEW
    CAST(FiscalYearLastDate AS DATE)              AS FSCYearLast,                -- NEW

    -- Holiday + Working Day (existing)
    TRIM(HolidayIndicator)                        AS HolidayIndicatorCode,
    TRIM(HolidayName)                             AS HolidayName,
    TRIM(WorkingDayIndicator)                     AS WorkingDayCode,
    TRIM(WeekdayWeekend)                          AS WeekdayWeekendCode

FROM Enterprise_Lakehouse.MasterData_DW.DimDate
WHERE DateKey IS NOT NULL;

-- =============================================================================
-- Result: 73 data cols (matches v8 dim_calendar 74 minus LoadDT which is added on materialize)
-- After this view ALTER, the next steps:
-- 1. ALTER TABLE ReferenceMaster_ENH.Calendar (or DROP + CTAS) to expand to 73+1 cols
-- 2. EXEC Meta.usp_GenericLoad @table_name = 'Calendar', @load_pattern = 'overwrite'
-- 3. Verify row count unchanged (~21,551 rows from v8)
-- 4. Verify col count = 74 (73 data + LoadDT)
-- =============================================================================
