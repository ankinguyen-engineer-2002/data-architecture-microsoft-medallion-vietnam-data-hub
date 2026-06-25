-- Source: SupplyChain_Warehouse.meta.ufn_utc_to_cst
-- Object type: SQL_SCALAR_FUNCTION
-- Exported read-only from sys.sql_modules.


CREATE FUNCTION meta.ufn_utc_to_cst(@dt DATETIME2(6))
RETURNS DATETIME2(6)
AS
BEGIN
    RETURN DATEADD(HOUR,
        CASE
            WHEN @dt >= CAST(
                DATEADD(DAY,
                    (8 - DATEPART(WEEKDAY, DATEFROMPARTS(YEAR(@dt),3,1))) % 7 + 7,
                    DATEFROMPARTS(YEAR(@dt),3,1)
                ) AS DATETIME2(6))
             AND @dt < CAST(
                DATEADD(DAY,
                    (8 - DATEPART(WEEKDAY, DATEFROMPARTS(YEAR(@dt),11,1))) % 7,
                    DATEFROMPARTS(YEAR(@dt),11,1)
                ) AS DATETIME2(6))
            THEN -5
            ELSE -6
        END, @dt)
END
