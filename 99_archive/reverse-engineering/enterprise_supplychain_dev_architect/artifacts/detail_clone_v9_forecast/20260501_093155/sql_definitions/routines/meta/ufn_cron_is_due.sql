-- Source: SupplyChain_Warehouse.meta.ufn_cron_is_due
-- Object type: SQL_SCALAR_FUNCTION
-- Exported read-only from sys.sql_modules.


CREATE   FUNCTION meta.ufn_cron_is_due(@cron VARCHAR(100))
RETURNS INT
AS
BEGIN
    -- ═══════════════════════════════════════════════════════════════
    -- Cron parser: '*/15 8-22 * * 1-5' → 1 if now matches, 0 if not
    -- Format: minute hour day_of_month month day_of_week
    -- Supports: * (any), */N (every N), N (exact), N,M (list), N-M (range)
    -- ═══════════════════════════════════════════════════════════════

    IF @cron IS NULL OR @cron = '' RETURN 1  -- no cron = always run

    DECLARE @now DATETIME2(6) = GETUTCDATE()
    DECLARE @minute INT = DATEPART(MINUTE, @now)
    DECLARE @hour INT = DATEPART(HOUR, @now)
    DECLARE @day INT = DATEPART(DAY, @now)
    DECLARE @month INT = DATEPART(MONTH, @now)
    DECLARE @dow INT = (DATEPART(WEEKDAY, @now) + 5) % 7  -- 0=Mon, 6=Sun

    -- Parse 5 fields
    DECLARE @f1 VARCHAR(20), @f2 VARCHAR(20), @f3 VARCHAR(20), @f4 VARCHAR(20), @f5 VARCHAR(20)
    DECLARE @parts VARCHAR(100) = LTRIM(RTRIM(@cron))

    -- Split by spaces
    SET @f1 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f1) + 2, 100))
    SET @f2 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f2) + 2, 100))
    SET @f3 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f3) + 2, 100))
    SET @f4 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f4) + 2, 100))
    SET @f5 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)

    -- Check each field
    DECLARE @match_min INT = 0, @match_hr INT = 0, @match_day INT = 0, @match_mon INT = 0, @match_dow INT = 0

    -- ── MINUTE ──
    IF @f1 = '*' SET @match_min = 1
    ELSE IF @f1 LIKE '*/%' BEGIN
        DECLARE @step_min INT = CAST(SUBSTRING(@f1, 3, 10) AS INT)
        IF @minute % @step_min = 0 SET @match_min = 1
    END
    ELSE IF @f1 LIKE '%-%' BEGIN
        IF @minute >= CAST(LEFT(@f1, CHARINDEX('-', @f1) - 1) AS INT)
           AND @minute <= CAST(SUBSTRING(@f1, CHARINDEX('-', @f1) + 1, 10) AS INT)
            SET @match_min = 1
    END
    ELSE IF CHARINDEX(',', @f1) > 0 BEGIN
        IF CHARINDEX(CAST(@minute AS VARCHAR), @f1) > 0 SET @match_min = 1
    END
    ELSE IF CAST(@f1 AS INT) = @minute SET @match_min = 1

    -- ── HOUR ──
    IF @f2 = '*' SET @match_hr = 1
    ELSE IF @f2 LIKE '*/%' BEGIN
        DECLARE @step_hr INT = CAST(SUBSTRING(@f2, 3, 10) AS INT)
        IF @hour % @step_hr = 0 SET @match_hr = 1
    END
    ELSE IF @f2 LIKE '%-%' BEGIN
        IF @hour >= CAST(LEFT(@f2, CHARINDEX('-', @f2) - 1) AS INT)
           AND @hour <= CAST(SUBSTRING(@f2, CHARINDEX('-', @f2) + 1, 10) AS INT)
            SET @match_hr = 1
    END
    ELSE IF CHARINDEX(',', @f2) > 0 BEGIN
        IF CHARINDEX(CAST(@hour AS VARCHAR), @f2) > 0 SET @match_hr = 1
    END
    ELSE IF CAST(@f2 AS INT) = @hour SET @match_hr = 1

    -- ── DAY OF MONTH ──
    IF @f3 = '*' SET @match_day = 1
    ELSE IF @f3 LIKE '%-%' BEGIN
        IF @day >= CAST(LEFT(@f3, CHARINDEX('-', @f3) - 1) AS INT)
           AND @day <= CAST(SUBSTRING(@f3, CHARINDEX('-', @f3) + 1, 10) AS INT)
            SET @match_day = 1
    END
    ELSE IF CHARINDEX(',', @f3) > 0 BEGIN
        IF CHARINDEX(CAST(@day AS VARCHAR), @f3) > 0 SET @match_day = 1
    END
    ELSE IF CAST(@f3 AS INT) = @day SET @match_day = 1

    -- ── MONTH ──
    IF @f4 = '*' SET @match_mon = 1
    ELSE IF @f4 LIKE '%-%' BEGIN
        IF @month >= CAST(LEFT(@f4, CHARINDEX('-', @f4) - 1) AS INT)
           AND @month <= CAST(SUBSTRING(@f4, CHARINDEX('-', @f4) + 1, 10) AS INT)
            SET @match_mon = 1
    END
    ELSE IF CHARINDEX(',', @f4) > 0 BEGIN
        IF CHARINDEX(CAST(@month AS VARCHAR), @f4) > 0 SET @match_mon = 1
    END
    ELSE IF CAST(@f4 AS INT) = @month SET @match_mon = 1

    -- ── DAY OF WEEK (0=Mon, 6=Sun) ──
    IF @f5 = '*' SET @match_dow = 1
    ELSE IF @f5 LIKE '%-%' BEGIN
        IF @dow >= CAST(LEFT(@f5, CHARINDEX('-', @f5) - 1) AS INT)
           AND @dow <= CAST(SUBSTRING(@f5, CHARINDEX('-', @f5) + 1, 10) AS INT)
            SET @match_dow = 1
    END
    ELSE IF CHARINDEX(',', @f5) > 0 BEGIN
        IF CHARINDEX(CAST(@dow AS VARCHAR), @f5) > 0 SET @match_dow = 1
    END
    ELSE IF CAST(@f5 AS INT) = @dow SET @match_dow = 1

    -- ALL 5 must match
    IF @match_min = 1 AND @match_hr = 1 AND @match_day = 1 AND @match_mon = 1 AND @match_dow = 1
        RETURN 1

    RETURN 0
END
