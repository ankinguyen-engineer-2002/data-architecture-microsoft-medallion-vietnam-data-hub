-- ---- InventoryHistory_Enh.v_ManufacturingOrder ----
-- L3 (deferred): OSTAT firm list ('10','40','45') needs Robert sign-off.
CREATE VIEW InventoryHistory_Enh.v_ManufacturingOrder AS
SELECT
    CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
    CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
    CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
    CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
    CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
    CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
    -- L3 PENDING: firm OSTAT list ('10','40','45') awaiting Robert sign-off
    CAST(CASE WHEN TRIM(OSTAT) IN ('10', '40', '45')
              THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
              ELSE 0
         END                          AS DECIMAL(18,4))  AS MOOnOrderQty,
    CAST(ODUDT                        AS INT)            AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
  AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''

GO
