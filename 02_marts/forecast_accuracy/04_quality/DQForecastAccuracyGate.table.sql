-- Live T-SQL runtime result table for the Forecast Accuracy 3-gate DQ contract.
-- Target database: SupplyChain_Processing_Warehouse, schema DataQuality.
--
-- Deployed under the name DQForecastAccuracyGate (NOT DQForecastAccuracy) to
-- coexist with the pre-existing legacy 6-column DataQuality.DQForecastAccuracy
-- (523 rows, Silver/Gold qty-parity model). Option A: non-destructive coexist;
-- the legacy table/proc/view are left untouched (ADR-011, 2026-07-22).
--
-- Column contract mirrors run_forecast_dq_dev.py RESULT_COLUMNS exactly so the
-- Python oracle and the T-SQL runtime produce byte-comparable rows.
CREATE TABLE [DataQuality].[DQForecastAccuracyGate]
(
    [DQRunId] varchar(64) NOT NULL,
    [DQRunAtUTC] datetime2(6) NOT NULL,
    [LoadDT] datetime2(6) NOT NULL,
    [MartCode] varchar(64) NOT NULL,
    [PipelineRunId] varchar(128) NULL,
    [DataCutId] varchar(256) NULL,
    [RuleVersion] varchar(32) NOT NULL,
    [GateCode] varchar(32) NOT NULL,
    [CheckType] varchar(32) NOT NULL,
    [Tier] int NOT NULL,
    [RuleCode] varchar(256) NOT NULL,
    [ParentRuleCode] varchar(256) NULL,
    [ObjectOrFlow] varchar(256) NOT NULL,
    [IsBlocking] bit NOT NULL,
    [Status] varchar(32) NOT NULL,
    [SourceObject] varchar(512) NULL,
    [TargetObject] varchar(512) NULL,
    [WindowStart] date NULL,
    [WindowEnd] date NULL,
    [SourceCount] bigint NULL,
    [TargetCount] bigint NULL,
    [SourceDistinctKeyCount] bigint NULL,
    [TargetDistinctKeyCount] bigint NULL,
    [SourceMeasure] decimal(38,6) NULL,
    [TargetMeasure] decimal(38,6) NULL,
    [Difference] decimal(38,6) NULL,
    [Tolerance] decimal(38,6) NULL,
    [MissingInGold] bigint NULL,
    [ExtraInGold] bigint NULL,
    [ObservedValue] varchar(4000) NULL,
    [ExpectedValue] varchar(4000) NULL,
    [Evidence] varchar(8000) NULL,
    [ErrorMessage] varchar(4000) NULL
);
GO
