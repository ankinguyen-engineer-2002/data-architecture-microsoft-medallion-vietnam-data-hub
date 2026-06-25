-- InventoryHistory_Enh_Wrk.v_ManufacturingOrderSnapshotDaily
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_ManufacturingOrderSnapshotDaily] AS
WITH _ManufacturingOrder AS (
    SELECT
        CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
        CASE WHEN OSTAT = '10' THEN 'Released'
             WHEN OSTAT = '40' THEN 'Order started'
             WHEN OSTAT = '45' THEN 'Material receipt to stock'
             WHEN OSTAT = '55' THEN 'Complete'
             WHEN OSTAT = '99' THEN 'Cancel'
        ELSE 'Unknown' END AS StatusName,
        CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTDEV                        AS DECIMAL(18,4))  AS DeviationQty,
        CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(QTSCP                        AS DECIMAL(18,4))  AS ScrapQty,
        CAST(QTSPL                        AS DECIMAL(18,4))  AS SplitQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40')
                  THEN CAST(QTYRC - ORQTY AS DECIMAL(18,4))
             ELSE 0 END AS DECIMAL(18,4)) AS RemainingMOQty,
        CAST(ODUDT                        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
),
__bob_source AS (
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(MoNumber                        AS VARCHAR(50))  AS MoNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(StatusName                      AS VARCHAR(10))  AS StatusName,
    CAST(RemainingMOQty                  AS DECIMAL(18,4)) RemainingMOQty,  
    CAST(OrderQty                        AS DECIMAL(18,4)) AS OrderQty,
    CAST(DeviationQty                    AS DECIMAL(18,4))  AS DeviationQty,
    CAST(ReceivedQty                     AS DECIMAL(18,4))  AS ReceivedQty,
    CAST(ScrapQty                        AS DECIMAL(18,4))  AS ScrapQty,
    CAST(SplitQty                        AS DECIMAL(18,4))  AS SplitQty,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM _ManufacturingOrder
)
SELECT
    [SnapshotDate] = src.[SnapshotDate],
    [MoNumber] = src.[MoNumber],
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [StatusCode] = src.[StatusCode],
    [StatusName] = src.[StatusName],
    [RemainingMOQty] = src.[RemainingMOQty],
    [OrderQty] = src.[OrderQty],
    [DeviationQty] = src.[DeviationQty],
    [ReceivedQty] = src.[ReceivedQty],
    [ScrapQty] = src.[ScrapQty],
    [SplitQty] = src.[SplitQty],
    [DueDateKey] = src.[DueDateKey],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
