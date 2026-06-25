-- ---- Shared_DW.v_DimCalendar ----
-- 2026-05-29: moved from ForecastAccuracy_DW to Shared_DW so Forecast Accuracy
-- and Inventory Health bind to one conformed Gold calendar.
CREATE   VIEW Shared_DW.v_DimCalendar AS
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
