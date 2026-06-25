-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [ForecastHistory_Enh].[ForecastDemandMonthly] (
    [ItemSKU] varchar(50) NULL,
    [WarehouseCode] varchar(10) NULL,
    [CustomerGroupCode] varchar(50) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [Snapshot] date NULL,
    [HorizonCode] varchar(10) NULL,
    [QtyForecast] float NULL,
    [VersionCode] varchar(20) NULL,
    [StatusCode] varchar(20) NULL,
    [LoadDT] datetime2(6) NULL
);
