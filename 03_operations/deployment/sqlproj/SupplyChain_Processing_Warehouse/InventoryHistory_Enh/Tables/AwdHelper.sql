-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[AwdHelper] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [AsOfDate] date NULL,
    [HorizonStartDate] date NULL,
    [HorizonEndDate] date NULL,
    [HorizonDays] int NULL,
    [ThreeMoForecastQty] decimal(18,4) NULL,
    [ForecastSnapshotDateOrg] date NULL,
    [ThreeMoDependentDemandQty] decimal(18,4) NULL,
    [ThreeMoTotalDemandQty] decimal(18,4) NULL,
    [Fwd13WForecastQty] decimal(18,4) NULL,
    [Hist13WShippedQty] decimal(18,4) NULL,
    [DailyFcstQty] decimal(18,4) NULL,
    [DependentDemandDailyQty] decimal(18,4) NULL,
    [TotalDemandDailyQty] decimal(18,4) NULL,
    [Hist13WShippedDailyQty] decimal(18,4) NULL,
    [AwdQty] decimal(18,4) NULL,
    [AwdDailyQty] decimal(18,4) NULL,
    [AwdSource] varchar(20) NULL
);
