-- Generated from repo contract: SupplyChain_Gold_Warehouse
CREATE TABLE [ForecastAccuracy_DW].[DQForecastAccuracy] (
    [RuleName] varchar(200) NULL,
    [RuleDescription] varchar(8000) NULL,
    [Result] varchar(10) NULL,
    [LoadDT] datetime2(6) NULL,
    [DQRunId] uniqueidentifier NULL,
    [DQRunAtUTC] datetime2(6) NULL
);
