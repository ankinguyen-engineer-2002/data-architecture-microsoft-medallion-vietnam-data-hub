-- ReferenceMaster_Enh_Wrk.v_Calendar
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_Calendar] AS
WITH __bob_source AS (
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
WHERE DateKey IS NOT NULL
)
SELECT
    [SKDate] = src.[SKDate],
    [MapicsDate] = src.[MapicsDate],
    [Date] = src.[Date],
    [Datetime] = src.[Datetime],
    [Calendar] = src.[Calendar],
    [CalendarDateName] = src.[CalendarDateName],
    [CalDateIndicatorNum] = src.[CalDateIndicatorNum],
    [CalDayOfWeekNum] = src.[CalDayOfWeekNum],
    [CalDayOfWeekName] = src.[CalDayOfWeekName],
    [CalDayOfMonthNum] = src.[CalDayOfMonthNum],
    [CalDayOfYearNum] = src.[CalDayOfYearNum],
    [CalWeekNum] = src.[CalWeekNum],
    [CalWeekIndicatorNum] = src.[CalWeekIndicatorNum],
    [CalWeekYearNum] = src.[CalWeekYearNum],
    [CalWeekYearName] = src.[CalWeekYearName],
    [CalWeekFirst] = src.[CalWeekFirst],
    [CalWeekLast] = src.[CalWeekLast],
    [CalWeekOfMonthNum] = src.[CalWeekOfMonthNum],
    [CalMonthNum] = src.[CalMonthNum],
    [CalMonthIndicatorNum] = src.[CalMonthIndicatorNum],
    [CalMonthYearNum] = src.[CalMonthYearNum],
    [CalMonthName] = src.[CalMonthName],
    [CalMonthYearName] = src.[CalMonthYearName],
    [CalMonthFirst] = src.[CalMonthFirst],
    [CalMonthLast] = src.[CalMonthLast],
    [CalQuarterNum] = src.[CalQuarterNum],
    [CalQuarterName] = src.[CalQuarterName],
    [CalQuarterIndicatorNum] = src.[CalQuarterIndicatorNum],
    [CalQuarterYearNum] = src.[CalQuarterYearNum],
    [CalQuarterYearName] = src.[CalQuarterYearName],
    [CalSemesterNum] = src.[CalSemesterNum],
    [CalSemesterYearNum] = src.[CalSemesterYearNum],
    [CalYearNum] = src.[CalYearNum],
    [CalYearName] = src.[CalYearName],
    [CalYearIndicatorNum] = src.[CalYearIndicatorNum],
    [FiscalDate] = src.[FiscalDate],
    [FiscalDateName] = src.[FiscalDateName],
    [FSCDateIndicatorNum] = src.[FSCDateIndicatorNum],
    [FSCDayOfWeekNum] = src.[FSCDayOfWeekNum],
    [FSCDayOfWeekName] = src.[FSCDayOfWeekName],
    [FSCDayOfMonthNum] = src.[FSCDayOfMonthNum],
    [FSCDayOfYearNum] = src.[FSCDayOfYearNum],
    [FSCWeekNum] = src.[FSCWeekNum],
    [FSCWeekIndicatorNum] = src.[FSCWeekIndicatorNum],
    [FSCWeekYearNum] = src.[FSCWeekYearNum],
    [FSCWeekYearName] = src.[FSCWeekYearName],
    [FSCWeekFirst] = src.[FSCWeekFirst],
    [FSCWeekLast] = src.[FSCWeekLast],
    [FSCWeekOfMonthNum] = src.[FSCWeekOfMonthNum],
    [FSCMonthNum] = src.[FSCMonthNum],
    [FSCMonthIndicatorNum] = src.[FSCMonthIndicatorNum],
    [FSCMonthYearNum] = src.[FSCMonthYearNum],
    [FSCMonthName] = src.[FSCMonthName],
    [FSCMonthYearName] = src.[FSCMonthYearName],
    [FSCMonthFirst] = src.[FSCMonthFirst],
    [FSCMonthLast] = src.[FSCMonthLast],
    [FSCQuarterNum] = src.[FSCQuarterNum],
    [FSCQuarterName] = src.[FSCQuarterName],
    [FSCQuarterIndicatorNum] = src.[FSCQuarterIndicatorNum],
    [FSCQuarterYearNum] = src.[FSCQuarterYearNum],
    [FSCQuarterYearName] = src.[FSCQuarterYearName],
    [FSCQuarterFirst] = src.[FSCQuarterFirst],
    [FSCQuarterLast] = src.[FSCQuarterLast],
    [FSCSemesterNum] = src.[FSCSemesterNum],
    [FSCSemesterYearNum] = src.[FSCSemesterYearNum],
    [FSCYearNum] = src.[FSCYearNum],
    [FSCYearName] = src.[FSCYearName],
    [FSCYearIndicatorNum] = src.[FSCYearIndicatorNum],
    [FSCYearFirst] = src.[FSCYearFirst],
    [FSCYearLast] = src.[FSCYearLast],
    [HolidayIndicatorCode] = src.[HolidayIndicatorCode],
    [HolidayName] = src.[HolidayName],
    [WorkingDayCode] = src.[WorkingDayCode],
    [WeekdayWeekendCode] = src.[WeekdayWeekendCode],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
