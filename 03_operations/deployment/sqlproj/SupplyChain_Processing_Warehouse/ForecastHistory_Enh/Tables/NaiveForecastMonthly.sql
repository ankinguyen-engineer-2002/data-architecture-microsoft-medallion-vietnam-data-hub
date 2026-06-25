-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [ForecastHistory_Enh].[NaiveForecastMonthly] (
    [ItemSKU] varchar(8000) NULL,
    [WarehouseCode] varchar(8000) NULL,
    [CustomerGroupCode] varchar(8000) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [QtyDemand] int NULL,
    [StatusCode] varchar(14) NOT NULL,
    [VersionName] varchar(14) NOT NULL,
    [LoadDT] datetime2(6) NULL
);
