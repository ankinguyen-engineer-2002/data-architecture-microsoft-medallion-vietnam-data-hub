-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[SafetyStockHelper] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [AsOfDate] date NULL,
    [SafetyStockTarget] decimal(18,4) NULL,
    [SnapshotCount] int NULL,
    [SafetyStockSource] varchar(30) NULL,
    [LoadDT] datetime2(6) NULL
);
