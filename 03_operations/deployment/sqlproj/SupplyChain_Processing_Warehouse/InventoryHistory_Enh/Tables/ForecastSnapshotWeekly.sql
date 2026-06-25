-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [InventoryHistory_Enh].[ForecastSnapshotWeekly] (
    [ItemSku] varchar(50) NULL,
    [WarehouseCode] varchar(50) NULL,
    [SnapshotDate] date NULL,
    [SnapshotWeekEndingDate] date NULL,
    [FiscalMonth] int NULL,
    [FiscalMonthDate] date NULL,
    [ForecastQty] decimal(18,4) NULL,
    [PromoLiftQty] decimal(18,4) NULL,
    [SourceSystem] varchar(64) NULL,
    [SourceTable] varchar(128) NULL,
    [LoadDT] datetime2(6) NULL
);
