-- Generated from live Fabric metadata: SupplyChain_Processing_Warehouse
CREATE TABLE [ReferenceMaster_Enh].[Warehouse] (
    [AFIWarehousesKey] int NULL,
    [WarehouseCode] varchar(50) NULL,
    [IntransitWarehouse] varchar(50) NULL,
    [ContainerDirectWarehouse] varchar(50) NULL,
    [ControlledWarehouse] int NULL,
    [WarehouseLocation] varchar(100) NULL,
    [WarehouseOrderGroup] varchar(100) NULL,
    [FinanceInventoryReportFlag] int NULL,
    [LoadDT] datetime2(6) NULL
);
