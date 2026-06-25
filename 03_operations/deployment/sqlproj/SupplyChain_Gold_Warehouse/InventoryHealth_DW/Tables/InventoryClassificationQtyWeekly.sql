-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [InventoryHealth_DW].[InventoryClassificationQtyWeekly] (
    [Item] varchar(50) NULL,
    [WH] varchar(50) NULL,
    [SnapshotWeekEnding] date NULL,
    [InventoryClassification Final Status] varchar(17) NULL,
    [Qty by InventoryClassification (Inactive)] decimal(18,4) NULL,
    [Qty by InventoryClassification (SLOB)] decimal(18,4) NULL,
    [Qty by InventoryClassification (Below Target)] decimal(20,5) NULL,
    [Qty by InventoryClassification (SweetSpot)] numeric(22,5) NULL,
    [Qty by InventoryClassification (OverTarget)] numeric(23,5) NULL,
    [Qty by InventoryClassification (Excess)] decimal(23,5) NULL,
    [Qty by InventoryClassification (AE)] decimal(24,5) NULL,
    [Qty by InventoryClassification (TB Inventory)] decimal(24,5) NULL
);
