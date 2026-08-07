-- Generated from live Fabric metadata: Enterprise_Lakehouse
CREATE TABLE [SupplyChain_Enh].[CurFcstSnapshotWeekly] (
    [ItemSku] varchar(8000) NULL,
    [Warehouse] varchar(8000) NULL,
    [FiscalMonthLastDate] datetime2(6) NULL,
    [FiscalMonthYear] decimal(6,0) NULL,
    [ResultantForecast] decimal(9,0) NULL,
    [PromoLift] decimal(9,0) NULL,
    [TotalForecast] decimal(9,0) NULL,
    [SnapshotDate] datetime2(6) NULL
);
