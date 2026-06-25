-- Source: SupplyChain_Warehouse.SCP_Core.FactWorkingForecastCurrent
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[FactWorkingForecastCurrent] (
    [CustomerGroup] varchar(30) NOT NULL,
    [ItemSKU] varchar(30) NOT NULL,
    [Warehouse] varchar(3) NOT NULL,
    [FiscalMonthLastDate] date NOT NULL,
    [ResultantForecastQty] int NOT NULL,
    [PromoLiftQty] int NOT NULL,
    [FutureOrderQty] int NOT NULL,
    [SnapshotDate] date NOT NULL
);
