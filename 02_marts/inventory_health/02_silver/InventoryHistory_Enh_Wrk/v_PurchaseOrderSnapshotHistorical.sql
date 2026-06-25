-- SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_PurchaseOrderSnapshotHistorical
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_PurchaseOrderSnapshotHistorical] AS
WITH __bob_source AS (
SELECT
    CAST(posSnapshot AS DATE) AS SnapshotDate,
    CAST(TRIM(posItNbr) AS VARCHAR(50)) AS ItemSku,
    CAST(TRIM(posWhse) AS VARCHAR(50)) AS WarehouseCode,
    CAST(TRIM(posVndnr) AS VARCHAR(50)) AS VendorNumber,
    CAST(posQtyOr AS DECIMAL(18,4)) AS OrderedQty,
    CAST(TRIM(posPstts) AS VARCHAR(10)) AS StatusCode,
    CASE
        WHEN TRIM(posPstts) = '05' THEN 'CFM Required'
        WHEN TRIM(posPstts) = '10' THEN 'On Order'
        WHEN TRIM(posPstts) = '20' THEN 'In Transit'
        WHEN TRIM(posPstts) = '30' THEN 'Rc. To Inspect'
        WHEN TRIM(posPstts) = '40' THEN 'Partial Rc.ToStock'
        WHEN TRIM(posPstts) = '50' THEN 'Rc. To Stock'
        WHEN TRIM(posPstts) = '99' THEN 'Cancelled'
        ELSE 'Unknown'
    END AS StatusName,
    CAST(CASE WHEN TRIM(posPstts) = '10' THEN posQtyOr ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN TRIM(posPstts) = '20' THEN posQtyOr ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
    TRY_CAST(
        DATEFROMPARTS(
            1900 + 100 * (TRY_CAST(posDueDt AS INT) / 1000000) + ((TRY_CAST(posDueDt AS INT) % 1000000) / 10000),
            (TRY_CAST(posDueDt AS INT) % 10000) / 100,
            TRY_CAST(posDueDt AS INT) % 100
        ) AS DATE
    ) AS DueDate,
    CAST(posUUD1PM AS DECIMAL(18,4)) AS UnitCost,
    CAST('Enterprise_Lakehouse' AS VARCHAR(64)) AS SourceSystem,
    CAST('SupplyChain_Enh.PurchaseOrderSnapshot' AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[PurchaseOrderSnapshot]
WHERE posItNbr IS NOT NULL
  AND posWhse IS NOT NULL
  AND TRIM(posItNbr) <> ''
  AND TRIM(posWhse) <> ''
)
SELECT
    [SnapshotDate] = src.[SnapshotDate],
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [VendorNumber] = src.[VendorNumber],
    [OrderedQty] = src.[OrderedQty],
    [StatusCode] = src.[StatusCode],
    [StatusName] = src.[StatusName],
    [POOnOrderQty] = src.[POOnOrderQty],
    [POInTransitQty] = src.[POInTransitQty],
    [DueDate] = src.[DueDate],
    [UnitCost] = src.[UnitCost],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
