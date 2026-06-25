CREATE FUNCTION DW_Developer.fn_GetDate
    (
        @DateTimeValue AS DATETIME2(6)
    )
-- converts UTC date to EST, CST & PST and returns them in a Table variable.

--  Sample Call:
--    SET @DateValue = Getdate()
--     SELECT @DateValue=CSTDateValue from DW_Developer.fn_GetDate(@DateValue)

RETURNS TABLE
AS
    RETURN
        (
            SELECT
                DATEADD(
                           hh,
                           CASE
                               WHEN @DateTimeValue >= '3/'
                                                      + CAST(ABS(8
                                                                 - DATEPART(
                                                                               dw,
                                                                               '3/1/'
                                                                               + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                           )
                                                                ) % 7 + 8 AS VARCHAR) + '/'
                                                      + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                    AND @DateTimeValue < '11/'
                                                         + CAST(ABS(8
                                                                    - DATEPART(
                                                                                  dw,
                                                                                  '11/1/'
                                                                                  + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                              )
                                                                   ) % 7 + 1 AS VARCHAR) + '/'
                                                         + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                   THEN
                                   -5
                               ELSE
                                   -6
                           END, @DateTimeValue
                       ) AS CSTDateValue,
                DATEADD(
                           hh,
                           CASE
                               WHEN @DateTimeValue >= '3/'
                                                      + CAST(ABS(8
                                                                 - DATEPART(
                                                                               dw,
                                                                               '3/1/'
                                                                               + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                           )
                                                                ) % 7 + 8 AS VARCHAR) + '/'
                                                      + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                    AND @DateTimeValue < '11/'
                                                         + CAST(ABS(8
                                                                    - DATEPART(
                                                                                  dw,
                                                                                  '11/1/'
                                                                                  + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                              )
                                                                   ) % 7 + 1 AS VARCHAR) + '/'
                                                         + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                   THEN
                                   -4
                               ELSE
                                   -5
                           END, @DateTimeValue
                       ) AS ESTDateValue,
                DATEADD(
                           hh,
                           CASE
                               WHEN @DateTimeValue >= '3/'
                                                      + CAST(ABS(8
                                                                 - DATEPART(
                                                                               dw,
                                                                               '3/1/'
                                                                               + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                           )
                                                                ) % 7 + 8 AS VARCHAR) + '/'
                                                      + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                    AND @DateTimeValue < '11/'
                                                         + CAST(ABS(8
                                                                    - DATEPART(
                                                                                  dw,
                                                                                  '11/1/'
                                                                                  + CAST(YEAR(@DateTimeValue) AS VARCHAR)
                                                                              )
                                                                   ) % 7 + 1 AS VARCHAR) + '/'
                                                         + CAST(YEAR(@DateTimeValue) AS VARCHAR) + ' 2:00'
                                   THEN
                                   -7
                               ELSE
                                   -8
                           END, @DateTimeValue
                       ) AS PSTDateValue
        );
