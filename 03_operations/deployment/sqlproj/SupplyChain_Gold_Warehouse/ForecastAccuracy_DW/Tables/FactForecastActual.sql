-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [ForecastAccuracy_DW].[FactForecastActual] (
    [ItemSKU] varchar(8000) NULL,
    [WarehouseCode] varchar(8000) NULL,
    [CustomerGroupCode] varchar(8000) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [HorizonCode] varchar(20) NULL,
    [StatusCode] varchar(20) NULL,
    [VersionName] varchar(20) NULL,
    [Qty] float NULL,
    [LoadDT] datetime2(6) NULL
);
