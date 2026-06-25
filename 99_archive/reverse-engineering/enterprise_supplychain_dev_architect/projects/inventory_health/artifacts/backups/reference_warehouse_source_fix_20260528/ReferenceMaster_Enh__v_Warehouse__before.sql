
CREATE   VIEW ReferenceMaster_Enh.v_Warehouse AS 
SELECT 
    AFIWarehousesKey,
    RTRIM(WarehouseCode) AS WarehouseCode,
    IntransitWarehouse,
    ContainerDirectWarehouse,
    ControlledWarehouse,
    WarehouseLocation,
    WarehouseOrderGroup,
    FinanceInventoryReportFlag
FROM Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses;
