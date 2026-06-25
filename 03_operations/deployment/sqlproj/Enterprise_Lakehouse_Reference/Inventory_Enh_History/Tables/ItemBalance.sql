-- Generated from live Fabric metadata: Enterprise_Lakehouse
CREATE TABLE [Inventory_Enh_History].[ItemBalance] (
    [ItemNumber] varchar(8000) NOT NULL,
    [Warehouse] varchar(8000) NOT NULL,
    [DateWeekEnding] date NULL,
    [OnHandQty] decimal(10,3) NULL,
    [ItemStatus] varchar(8000) NULL
);
