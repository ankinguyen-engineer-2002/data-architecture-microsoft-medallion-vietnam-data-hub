-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[LastInvoiceWeekly] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [WeekEndingDate] date NULL,
    [LastInvoiceDate] date NULL,
    [WeeksSinceLastInvoice] int NULL,
    [LoadDT] datetime2(6) NULL
);
