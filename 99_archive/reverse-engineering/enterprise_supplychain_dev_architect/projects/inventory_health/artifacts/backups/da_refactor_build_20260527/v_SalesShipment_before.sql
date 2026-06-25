-- ---- InventoryHistory_Enh.v_SalesShipment ----
-- v10 incremental on InvoiceDate (watermark managed by Meta.usp_GenericLoad).
-- View body does NOT filter watermark — GenericLoad appends WHERE InvoiceDate > last_wm at runtime.
CREATE   VIEW InventoryHistory_Enh.v_SalesShipment AS
-- 2026-05-21 (Giang #8): GRAIN = InvoiceNumber + ItemSequence. Different from helpers' Item-WH grain. Helpers use SUM/MAX aggregation downstream which correctly handles the cross-grain.
SELECT
    CAST(InvoiceNumber              AS DECIMAL(18,0)) AS InvoiceNumber,
    CAST(ItemSequence               AS DECIMAL(18,0)) AS ItemSequence,
    CAST(TRIM(ItemSKU)              AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(Warehouse)            AS VARCHAR(50))   AS WarehouseCode,
    CAST(InvoiceDate                AS DATE)          AS InvoiceDate,
    CAST(OrderDate                  AS DATE)          AS OrderDate,
    CAST(QuantityShipped            AS DECIMAL(18,4)) AS QuantityShipped,
    CAST(QuantityOrdered            AS DECIMAL(18,4)) AS QuantityOrdered,
    CAST(Price                      AS DECIMAL(18,4)) AS Price,
    CAST('SalesHistory_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('InvoiceDetail'     AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail]
WHERE ItemSKU IS NOT NULL AND Warehouse IS NOT NULL
  AND TRIM(ItemSKU) <> '' AND TRIM(Warehouse) <> ''