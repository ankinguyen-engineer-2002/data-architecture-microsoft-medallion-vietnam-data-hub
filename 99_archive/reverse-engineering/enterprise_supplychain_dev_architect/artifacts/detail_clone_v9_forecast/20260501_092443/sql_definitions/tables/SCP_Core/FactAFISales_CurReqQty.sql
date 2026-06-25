-- Source: SupplyChain_Warehouse.SCP_Core.FactAFISales_CurReqQty
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[FactAFISales_CurReqQty] (
    [AccountAndShipToNumber] varchar(8000) NOT NULL,
    [ItemSKU] varchar(8000) NOT NULL,
    [Warehouse] varchar(8000) NOT NULL,
    [CurReqWkEnd] date NOT NULL,
    [OrderQty] int NULL,
    [OrderAmt] decimal(18,2) NULL,
    [OrderStatus] varchar(10) NOT NULL
);
