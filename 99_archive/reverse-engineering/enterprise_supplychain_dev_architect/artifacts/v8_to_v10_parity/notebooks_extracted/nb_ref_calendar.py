# ─── Cell 0 ───
TARGET_TABLE = "ref_calendar"
SOURCE_TABLE = "MasterData_DW/DimDate"

COLUMN_SQL = """
    SELECT
        -- Keys
        CAST(DateKey AS INT)                                 AS sk_date,
        CAST(MapicsDate AS INT)                              AS id_mapics_date,
        CAST(DateID AS DATE)                                 AS dt_date,
        CAST(DateTimeID AS DATE)                             AS dt_datetime,
        CAST(CalendarDate AS DATE)                           AS dt_calendar,

        -- Calendar - Day
        TRIM(CalendarDateName)                               AS name_calendar_date,
        CAST(CalendarDateIndicator AS INT)                   AS num_cal_date_indicator,
        CAST(CalendarDayOfWeek AS INT)                       AS num_cal_day_of_week,
        TRIM(CalendarDayOfWeekName)                          AS name_cal_day_of_week,
        CAST(CalendarDayOfMonth AS INT)                      AS num_cal_day_of_month,
        CAST(CalendarDayOfYear AS INT)                       AS num_cal_day_of_year,

        -- Calendar - Week
        CAST(CalendarWeek AS INT)                            AS num_cal_week,
        CAST(CalendarWeekIndicator AS INT)                   AS num_cal_week_indicator,
        CAST(CalendarWeekYear AS INT)                        AS num_cal_week_year,
        TRIM(CalendarWeekYearName)                           AS name_cal_week_year,
        CAST(CalendarWeekFirstDate AS DATE)                  AS dt_cal_week_first,
        CAST(CalendarWeekLastDate AS DATE)                   AS dt_cal_week_last,
        CAST(CalendarWeekOfMonth AS INT)                     AS num_cal_week_of_month,

        -- Calendar - Month
        CAST(CalendarMonth AS INT)                           AS num_cal_month,
        CAST(CalendarMonthIndicator AS INT)                  AS num_cal_month_indicator,
        CAST(CalendarMonthYear AS INT)                       AS num_cal_month_year,
        TRIM(CalendarMonthName)                              AS name_cal_month,
        TRIM(CalendarMonthYearName)                          AS name_cal_month_year,
        CAST(CalendarMonthFirstDate AS DATE)                 AS dt_cal_month_first,
        CAST(CalendarMonthLastDate AS DATE)                  AS dt_cal_month_last,

        -- Calendar - Quarter
        CAST(CalendarQuarter AS INT)                         AS num_cal_quarter,
        TRIM(CalendarQuarterName)                            AS name_cal_quarter,
        CAST(CalendarQuarterIndicator AS INT)                AS num_cal_quarter_indicator,
        CAST(CalendarQuarterYear AS INT)                     AS num_cal_quarter_year,
        TRIM(CalendarQuarterYearName)                        AS name_cal_quarter_year,

        -- Calendar - Semester & Year
        CAST(CalendarSemester AS INT)                        AS num_cal_semester,
        CAST(CalendarSemesterYear AS INT)                    AS num_cal_semester_year,
        CAST(CalendarYear AS INT)                            AS num_cal_year,
        TRIM(CalendarYearName)                               AS name_cal_year,
        CAST(CalendarYearIndicator AS INT)                   AS num_cal_year_indicator,

        -- Fiscal - Day
        CAST(FiscalDate AS DATE)                             AS dt_fiscal,
        TRIM(FiscalDateName)                                 AS name_fiscal_date,
        CAST(FiscalDateIndicator AS INT)                     AS num_fsc_date_indicator,
        CAST(FiscalDayOfWeek AS INT)                         AS num_fsc_day_of_week,
        TRIM(FiscalDayOfWeekName)                            AS name_fsc_day_of_week,
        CAST(FiscalDayOfMonth AS INT)                        AS num_fsc_day_of_month,
        CAST(FiscalDayOfYear AS INT)                         AS num_fsc_day_of_year,

        -- Fiscal - Week
        CAST(FiscalWeek AS INT)                              AS num_fsc_week,
        CAST(FiscalWeekIndicator AS INT)                     AS num_fsc_week_indicator,
        CAST(FiscalWeekYear AS INT)                          AS num_fsc_week_year,
        TRIM(FiscalWeekYearName)                             AS name_fsc_week_year,
        CAST(FiscalWeekFirstDate AS DATE)                    AS dt_fsc_week_first,
        CAST(FiscalWeekLastDate AS DATE)                     AS dt_fsc_week_last,
        CAST(FiscalWeekOfMonth AS INT)                       AS num_fsc_week_of_month,

        -- Fiscal - Month
        CAST(FiscalMonth AS INT)                             AS num_fsc_month,
        CAST(FiscalMonthIndicator AS INT)                    AS num_fsc_month_indicator,
        CAST(FiscalMonthYear AS INT)                         AS num_fsc_month_year,
        TRIM(FiscalMonthName)                                AS name_fsc_month,
        TRIM(FiscalMonthYearName)                            AS name_fsc_month_year,
        CAST(FiscalMonthFirstDate AS DATE)                   AS dt_fsc_month_first,
        CAST(FiscalMonthLastDate AS DATE)                    AS dt_fsc_month_last,

        -- Fiscal - Quarter
        CAST(FiscalQuarter AS INT)                           AS num_fsc_quarter,
        TRIM(FiscalQuarterName)                              AS name_fsc_quarter,
        CAST(FiscalQuarterIndicator AS INT)                  AS num_fsc_quarter_indicator,
        CAST(FiscalQuarterYear AS INT)                       AS num_fsc_quarter_year,
        TRIM(FiscalQuarterYearName)                          AS name_fsc_quarter_year,
        MIN(CAST(FiscalMonthFirstDate AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter) AS dt_fsc_quarter_first,
        MAX(CAST(FiscalMonthLastDate AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)  AS dt_fsc_quarter_last,

        -- Fiscal - Semester & Year
        CAST(FiscalSemester AS INT)                          AS num_fsc_semester,
        CAST(FiscalSemesterYear AS INT)                      AS num_fsc_semester_year,
        CAST(FiscalYear AS INT)                              AS num_fsc_year,
        TRIM(FiscalYearName)                                 AS name_fsc_year,
        CAST(FiscalYearIndicator AS INT)                     AS num_fsc_year_indicator,
        CAST(FiscalYearFirstDate AS DATE)                    AS dt_fsc_year_first,
        CAST(FiscalYearLastDate AS DATE)                     AS dt_fsc_year_last,

        -- Holiday & Working Day
        TRIM(HolidayIndicator)                               AS code_holiday_indicator,
        TRIM(HolidayName)                                    AS name_holiday,
        TRIM(WorkingDayIndicator)                            AS code_working_day,
        TRIM(WeekdayWeekend)                                 AS code_weekday_weekend

    FROM raw_source
    WHERE DateKey IS NOT NULL
"""

# ─── Cell 1 ───
notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,
        "COLUMN_SQL":   COLUMN_SQL
    }
)

