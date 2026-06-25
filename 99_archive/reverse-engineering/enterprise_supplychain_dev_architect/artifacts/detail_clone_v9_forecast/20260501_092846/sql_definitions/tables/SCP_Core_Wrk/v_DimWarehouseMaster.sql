-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimWarehouseMaster
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_DimWarehouseMaster] (
    [Warehouse Code] varchar(8000) NULL,
    [Warehouse Location] varchar(8000) NULL,
    [WH Desc] varchar(7) NULL,
    [WH Group] varchar(5) NULL,
    [Warehouse Name] varchar(8000) NOT NULL,
    [IntransitWarehouse] varchar(8000) NULL
);
