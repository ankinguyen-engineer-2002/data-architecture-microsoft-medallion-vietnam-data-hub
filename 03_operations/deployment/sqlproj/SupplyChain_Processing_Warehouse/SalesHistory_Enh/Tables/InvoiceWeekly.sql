-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [SalesHistory_Enh].[InvoiceWeekly] (
    [AccountShipTo] varchar(8000) NULL,
    [ItemSKU] varchar(8000) NOT NULL,
    [WarehouseCode] varchar(8000) NOT NULL,
    [CustomerGroupCode] varchar(8000) NULL,
    [FSCWeekFirst] date NULL,
    [FSCWeekLast] date NULL,
    [QtyShipped] decimal(38,0) NULL,
    [AmtNetSales] decimal(38,3) NULL,
    [AmtInvoice] decimal(38,2) NULL,
    [AmtFreight] decimal(38,2) NULL,
    [InvoiceLines] int NULL,
    [DistinctInvoices] int NULL,
    [LoadDT] datetime2(6) NULL
);
