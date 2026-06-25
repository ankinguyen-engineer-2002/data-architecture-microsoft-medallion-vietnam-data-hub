-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [InventoryHealth_DW].[InventoryHealthSubStatusWeekly] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [SnapshotWeekEnding] date NULL,
    [SubStatus] varchar(17) NOT NULL,
    [Ranking] int NOT NULL,
    [InventoryClassification Final Status] varchar(17) NOT NULL,
    [Avg Weekly Demand] decimal(18,4) NULL,
    [SS target] decimal(18,4) NULL,
    [On Hands Qty] decimal(18,4) NULL,
    [On Order Qty] decimal(18,4) NULL,
    [AFIStatus] varchar(20) NULL,
    [LastInvoiceDate] date NULL
);
