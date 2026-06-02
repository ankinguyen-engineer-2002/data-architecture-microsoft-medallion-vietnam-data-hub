-- ---- InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily AS
WITH _ManufacturingOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ManufacturingOrder
    SELECT
        CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END              AS DECIMAL(18,4))  AS MOOnOrderQty,
        CAST(ODUDT                        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(MoNumber                        AS VARCHAR(50))  AS MoNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(OrderQty                        AS DECIMAL(18,4)) AS OrderQty,
    CAST(ReceivedQty                     AS DECIMAL(18,4)) AS ReceivedQty,
    CAST(MOOnOrderQty                    AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM _ManufacturingOrder