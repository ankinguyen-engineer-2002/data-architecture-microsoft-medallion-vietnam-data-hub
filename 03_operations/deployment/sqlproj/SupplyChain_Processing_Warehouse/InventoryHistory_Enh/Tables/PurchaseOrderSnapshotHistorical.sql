-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[PurchaseOrderSnapshotHistorical] (
    [SnapshotDate] date NULL,
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [VendorNumber] varchar(50) NULL,
    [OrderedQty] decimal(18,4) NULL,
    [StatusCode] varchar(10) NULL,
    [StatusName] varchar(18) NOT NULL,
    [POOnOrderQty] decimal(18,4) NULL,
    [POInTransitQty] decimal(18,4) NULL,
    [DueDate] date NULL,
    [UnitCost] decimal(18,4) NULL,
    [SourceSystem] varchar(64) NULL,
    [SourceTable] varchar(128) NULL,
    [LoadDT] datetime2(6) NULL
);
