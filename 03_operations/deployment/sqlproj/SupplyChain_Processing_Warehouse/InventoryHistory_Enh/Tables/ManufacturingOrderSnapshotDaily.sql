-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily] (
    [SnapshotDate] date NULL,
    [MoNumber] varchar(50) NULL,
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [StatusCode] varchar(10) NULL,
    [StatusName] varchar(10) NULL,
    [RemainingMOQty] decimal(18,4) NULL,
    [OrderQty] decimal(18,4) NULL,
    [DeviationQty] decimal(18,4) NULL,
    [ReceivedQty] decimal(18,4) NULL,
    [ScrapQty] decimal(18,4) NULL,
    [SplitQty] decimal(18,4) NULL,
    [DueDateKey] int NULL,
    [SourceSystem] varchar(64) NULL,
    [SourceTable] varchar(128) NULL,
    [LoadDT] datetime2(6) NULL
);
