-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_WorkingForecastCurrent
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_WorkingForecastCurrent] (
    [CustomerGroup] varchar(8000) NULL,
    [ItemSKU] varchar(8000) NULL,
    [Warehouse] varchar(8000) NULL,
    [FiscalMonthLastDate] date NULL,
    [ResultantForecastQty] decimal(9,0) NULL,
    [PromoLiftQty] decimal(9,0) NULL,
    [FutureOrderQty] decimal(9,0) NOT NULL,
    [SnapshotDate] date NULL
);
