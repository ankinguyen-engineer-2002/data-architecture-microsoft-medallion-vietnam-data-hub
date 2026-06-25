-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [Shared_DW].[DimWarehouse] (
    [WarehouseCode] varchar(50) NULL,
    [WarehouseGroup] varchar(50) NULL,
    [AFIWarehousesKey] int NULL,
    [IntransitWarehouse] varchar(50) NULL,
    [ContainerDirectWarehouse] varchar(50) NULL,
    [ControlledWarehouse] int NULL,
    [WarehouseLocation] varchar(100) NULL,
    [WarehouseOrderGroup] varchar(100) NULL,
    [FinanceInventoryReportFlag] int NULL,
    [WarehouseName] varchar(50) NULL,
    [WarehouseType] varchar(100) NULL,
    [WarehouseSourceId] varchar(50) NULL,
    [SellableWarehouseFlag] bit NULL,
    [ControlledFlag] bit NULL,
    [WhereMadeCode] varchar(50) NULL,
    [ManufacturingSite] varchar(50) NULL,
    [IntransitWarehouseCode] varchar(50) NULL,
    [IsFinishedGoodsWarehouse] bit NULL,
    [IsManufacturingWarehouse] bit NULL,
    [TotalAvailableWarehouseCube] decimal(18,4) NULL,
    [LoadDT] datetime2(6) NULL
);
