-- =============================================================================
-- DataQuality.usp_GateForecastAccuracyPublish
-- Read-only publish-gate decision for the Forecast Accuracy mart.
-- Target database: SupplyChain_Processing_Warehouse, schema DataQuality.
--
-- Reads a persisted DQ run from DataQuality.DQForecastAccuracyGate and returns a
-- single publish decision. It never runs the gates and never mutates data; the
-- runner (usp_RunForecastAccuracyDQ @Persist=1) must have persisted the run first.
--
-- Decision contract (ADR-011 section 7):
--   PASS            -> every blocking check passed; publish is authorized.
--   FAIL            -> at least one blocking check FAILed.
--   ERROR           -> at least one blocking check errored, OR no run found.
--   NOT_COMPARABLE  -> a blocking reconciliation could not be proven comparable.
-- SKIPPED is allowed only for explicitly nonblocking checks and never gates.
--
-- @DQRunId NULL resolves to the latest run (max DQRunAtUTC). Output is one row:
-- the decision plus counts, so a pipeline can branch on PublishAllowed.
-- =============================================================================
CREATE OR ALTER PROCEDURE [DataQuality].[usp_GateForecastAccuracyPublish]
    @DQRunId varchar(64) = NULL,
    @ThrowOnBlocked bit = 0,
    @EmitResult bit = 1,
    @DecisionOutput varchar(32) = NULL OUTPUT,
    @PublishAllowedOutput bit = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_NAME() <> N'SupplyChain_Processing_Warehouse'
        THROW 50002, 'usp_GateForecastAccuracyPublish must run in SupplyChain_Processing_Warehouse.', 1;

    -- Resolve the target run: explicit id, else the latest persisted run.
    IF @DQRunId IS NULL
        SELECT TOP 1 @DQRunId = DQRunId
        FROM DataQuality.DQForecastAccuracyGate
        ORDER BY DQRunAtUTC DESC;

    DECLARE @RowCount int = (
        SELECT COUNT(*) FROM DataQuality.DQForecastAccuracyGate WHERE DQRunId = @DQRunId
    );

    -- No persisted run -> ERROR (nothing to gate on).
    IF @DQRunId IS NULL OR @RowCount = 0
    BEGIN
        SET @DecisionOutput = 'ERROR';
        SET @PublishAllowedOutput = 0;

        IF @EmitResult = 1
            SELECT
                CAST(NULL AS varchar(64)) AS DQRunId,
                'ERROR' AS Decision,
                CAST(0 AS bit) AS PublishAllowed,
                'no persisted DQ run found for the requested id' AS Reason,
                0 AS ResultCount, 0 AS BlockingCount,
                0 AS BlockingPass, 0 AS BlockingFail,
                0 AS BlockingError, 0 AS BlockingNotComparable,
                0 AS NonBlockingSkipped;

        IF @ThrowOnBlocked = 1
            THROW 50003, 'Forecast Accuracy publish blocked: no persisted DQ run found.', 1;
        RETURN;
    END

    -- Blocking-status rollup for the run.
    DECLARE @BlockingCount int, @bPass int, @bFail int, @bError int, @bNotComp int, @nbSkipped int;
    SELECT
        @BlockingCount = SUM(CASE WHEN IsBlocking = 1 THEN 1 ELSE 0 END),
        @bPass    = SUM(CASE WHEN IsBlocking = 1 AND Status = 'PASS' THEN 1 ELSE 0 END),
        @bFail    = SUM(CASE WHEN IsBlocking = 1 AND Status = 'FAIL' THEN 1 ELSE 0 END),
        @bError   = SUM(CASE WHEN IsBlocking = 1 AND Status = 'ERROR' THEN 1 ELSE 0 END),
        @bNotComp = SUM(CASE WHEN IsBlocking = 1 AND Status = 'NOT_COMPARABLE' THEN 1 ELSE 0 END),
        @nbSkipped = SUM(CASE WHEN IsBlocking = 0 AND Status = 'SKIPPED' THEN 1 ELSE 0 END)
    FROM DataQuality.DQForecastAccuracyGate
    WHERE DQRunId = @DQRunId;

    -- Any blocking status outside the allowed set (PASS/FAIL/ERROR/NOT_COMPARABLE)
    -- is itself an error: a blocking check may never be SKIPPED.
    DECLARE @bOther int = @BlockingCount - (@bPass + @bFail + @bError + @bNotComp);

    -- Precedence mirrors the runner decision(): ERROR > FAIL > NOT_COMPARABLE > PASS.
    DECLARE @Decision varchar(32), @Reason varchar(4000);
    IF @bError > 0 OR @bOther > 0
    BEGIN
        SET @Decision = 'ERROR';
        SET @Reason = CONCAT(@bError, ' blocking error(s), ', @bOther, ' blocking check(s) in a disallowed status');
    END
    ELSE IF @bFail > 0
    BEGIN
        SET @Decision = 'FAIL';
        SET @Reason = CONCAT(@bFail, ' blocking check(s) failed');
    END
    ELSE IF @bNotComp > 0
    BEGIN
        SET @Decision = 'NOT_COMPARABLE';
        SET @Reason = CONCAT(@bNotComp, ' blocking reconciliation(s) not comparable');
    END
    ELSE
    BEGIN
        SET @Decision = 'PASS';
        SET @Reason = 'all blocking checks passed';
    END

    SET @DecisionOutput = @Decision;
    SET @PublishAllowedOutput = CAST(CASE WHEN @Decision = 'PASS' THEN 1 ELSE 0 END AS bit);

    IF @EmitResult = 1
        SELECT
            @DQRunId AS DQRunId,
            @Decision AS Decision,
            @PublishAllowedOutput AS PublishAllowed,
            @Reason AS Reason,
            @RowCount AS ResultCount,
            @BlockingCount AS BlockingCount,
            @bPass AS BlockingPass,
            @bFail AS BlockingFail,
            @bError AS BlockingError,
            @bNotComp AS BlockingNotComparable,
            @nbSkipped AS NonBlockingSkipped;

    IF @ThrowOnBlocked = 1 AND @PublishAllowedOutput = 0
    BEGIN
        DECLARE @ThrowMessage nvarchar(2048) = CONCAT('Forecast Accuracy publish blocked for DQ run ', @DQRunId, ': ', @Reason);
        THROW 50003, @ThrowMessage, 1;
    END
END;
