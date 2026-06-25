-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[Cogs52WWeekly] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [WeekEndingDate] date NULL,
    [RollingWindowStartDate] date NULL,
    [RollingWindowEndDate] date NULL,
    [StandardCost] decimal(18,4) NULL,
    [StandardCostRevision] varchar(8000) NULL,
    [PeriodShippedQty] decimal(18,4) NULL,
    [PeriodCogs] decimal(18,4) NULL,
    [ShippedQty52W] decimal(18,4) NULL,
    [COGS52W] decimal(18,4) NULL,
    [LoadDT] datetime2(6) NULL
);
