-- Source: SupplyChain_Warehouse.SCP_Core.FactInvTransactionsWeekly
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[FactInvTransactionsWeekly] (
    [ItemSKU] varchar(8000) NOT NULL,
    [Warehouse] varchar(8000) NOT NULL,
    [ItemFlag] varchar(8000) NOT NULL,
    [FiscalWeekLastDate] date NOT NULL,
    [TransactionCode] char(2) NOT NULL,
    [TransactionCodeDesc] varchar(8000) NOT NULL,
    [TransactionType] varchar(20) NOT NULL,
    [TransactionQty] float NOT NULL,
    [NetChangeQty] float NOT NULL
);
