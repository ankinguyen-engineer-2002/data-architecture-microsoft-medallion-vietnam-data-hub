-- SupplyChain_Processing_Warehouse.ReferenceMaster_Enh_Wrk.v_Warehouse
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_Warehouse] AS
WITH __bob_source AS (
SELECT
    CAST(LocationID AS INT) AS AFIWarehousesKey,
    CAST(RTRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode,
    CAST(RTRIM(IntransitWarehouse) AS VARCHAR(50)) AS IntransitWarehouse,
    CAST(RTRIM(ContainerDirectWhse) AS VARCHAR(50)) AS ContainerDirectWarehouse,
    CAST(CASE WHEN Controlled = 1 THEN 1 ELSE 0 END AS INT) AS ControlledWarehouse,
    CAST(COALESCE(NULLIF(RTRIM(WarehouseOrderGroup), ''), NULLIF(RTRIM(Warehouse), '')) AS VARCHAR(100)) AS WarehouseLocation,
    CAST(RTRIM(WarehouseOrderGroup) AS VARCHAR(100)) AS WarehouseOrderGroup,
    CAST(CASE WHEN ActiveRecord = 'A' THEN 1 ELSE 0 END AS INT) AS FinanceInventoryReportFlag
FROM Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
WHERE NULLIF(TRIM(Warehouse), '') IS NOT NULL
)
SELECT
    [AFIWarehousesKey] = src.[AFIWarehousesKey],
    [WarehouseCode] = src.[WarehouseCode],
    [IntransitWarehouse] = src.[IntransitWarehouse],
    [ContainerDirectWarehouse] = src.[ContainerDirectWarehouse],
    [ControlledWarehouse] = src.[ControlledWarehouse],
    [WarehouseLocation] = src.[WarehouseLocation],
    [WarehouseOrderGroup] = src.[WarehouseOrderGroup],
    [FinanceInventoryReportFlag] = src.[FinanceInventoryReportFlag],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
