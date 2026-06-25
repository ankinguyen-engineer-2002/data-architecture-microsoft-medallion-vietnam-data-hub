-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [SalesHistory_Enh].[ActualDemandWeekly] (
    [ItemSKU] varchar(8000) NULL,
    [WarehouseCode] varchar(8000) NULL,
    [CustomerGroupCode] varchar(8000) NULL,
    [FSCWeekFirst] date NULL,
    [FSCWeekLast] date NULL,
    [QtyDemand] decimal(38,0) NULL,
    [AmtDemand] decimal(38,2) NULL,
    [StatusCode] varchar(10) NOT NULL,
    [VersionName] varchar(13) NOT NULL,
    [LoadDT] datetime2(6) NULL
);
