-- =============================================================================
-- DataQuality.usp_RunAndGateForecastAccuracyPublish
-- Runs one persisted Forecast Accuracy DQ cut and asserts that exact run.
-- Target database: SupplyChain_Processing_Warehouse, schema DataQuality.
-- =============================================================================
CREATE PROCEDURE [DataQuality].[usp_RunAndGateForecastAccuracyPublish]
    @AsOfDate date = NULL,
    @PipelineRunId varchar(128) = NULL,
    @DQRunIdOutput varchar(64) = NULL OUTPUT,
    @DecisionOutput varchar(32) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_NAME() <> N'SupplyChain_Processing_Warehouse'
        THROW 50004, 'usp_RunAndGateForecastAccuracyPublish must run in SupplyChain_Processing_Warehouse.', 1;

    DECLARE @DQRunId varchar(64);
    DECLARE @RunnerDecision varchar(32);
    DECLARE @GateDecision varchar(32);
    DECLARE @PublishAllowed bit;

    EXEC [DataQuality].[usp_RunForecastAccuracyDQ]
        @AsOfDate = @AsOfDate,
        @PipelineRunId = @PipelineRunId,
        @Persist = 1,
        @EmitResults = 0,
        @DQRunIdOutput = @DQRunId OUTPUT,
        @DecisionOutput = @RunnerDecision OUTPUT;

    EXEC [DataQuality].[usp_GateForecastAccuracyPublish]
        @DQRunId = @DQRunId,
        @ThrowOnBlocked = 1,
        @EmitResult = 0,
        @DecisionOutput = @GateDecision OUTPUT,
        @PublishAllowedOutput = @PublishAllowed OUTPUT;

    SET @DQRunIdOutput = @DQRunId;
    SET @DecisionOutput = @GateDecision;
END;
