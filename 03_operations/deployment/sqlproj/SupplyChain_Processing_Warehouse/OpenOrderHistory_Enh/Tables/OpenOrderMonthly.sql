-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [OpenOrderHistory_Enh].[OpenOrderMonthly] (
    [ItemSKU] varchar(8000) NULL,
    [WarehouseCode] varchar(8000) NULL,
    [CustomerGroupCode] varchar(8000) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [QtyOpenOrder] int NULL,
    [QtyBackorder] int NULL,
    [AmtOpenOrder] decimal(38,2) NULL,
    [AmtBackorder] decimal(38,2) NULL,
    [OrderLines] int NULL,
    [DistinctOrders] int NULL,
    [QtyPastDue] int NULL,
    [AmtPastDue] decimal(38,2) NULL,
    [LoadDT] datetime2(6) NULL
);
