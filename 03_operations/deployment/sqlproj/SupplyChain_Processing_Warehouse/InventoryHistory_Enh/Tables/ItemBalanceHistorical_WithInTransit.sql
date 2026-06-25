-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[ItemBalanceHistorical_WithInTransit] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [WeekEndingDate] date NULL,
    [OnHandQty] decimal(18,4) NULL,
    [InTransitQty] decimal(18,4) NULL,
    [TotalAvailQty] decimal(18,4) NULL,
    [ItemStatus] varchar(10) NULL,
    [SourceSystem] varchar(64) NULL,
    [SourceTable] varchar(128) NULL,
    [LoadDT] datetime2(6) NULL
);
