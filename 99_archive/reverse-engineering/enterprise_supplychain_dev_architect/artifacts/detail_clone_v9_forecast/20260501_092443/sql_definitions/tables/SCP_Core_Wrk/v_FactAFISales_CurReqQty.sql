-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactAFISales_CurReqQty
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_FactAFISales_CurReqQty] (
    [AccountAndShipToNumber] varchar(8000) NULL,
    [ItemSKU] varchar(8000) NULL,
    [Warehouse] varchar(8000) NULL,
    [CurReqWkEnd] date NOT NULL,
    [OrderQty] decimal(38,0) NULL,
    [OrderAmt] decimal(38,2) NULL,
    [OrderStatus] varchar(8) NOT NULL
);
