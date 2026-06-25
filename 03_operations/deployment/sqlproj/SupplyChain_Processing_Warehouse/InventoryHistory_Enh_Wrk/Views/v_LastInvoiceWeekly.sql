-- InventoryHistory_Enh_Wrk.v_LastInvoiceWeekly
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_LastInvoiceWeekly] AS
WITH
_BaseFact AS (
    SELECT DISTINCT
        CAST(SnapshotDate AS DATE)               AS WeekEndingDate,
        CAST(TRIM(ItemSku) AS VARCHAR(50))       AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode
    FROM [InventoryHistory_Enh].[InventorySnapshotWeekly]
    WHERE SnapshotDate IS NOT NULL
      AND ItemSku IS NOT NULL
      AND TRIM(ItemSku) <> ''
      AND WarehouseCode IS NOT NULL
      AND TRIM(WarehouseCode) <> ''
),
_InvoiceDetail AS (
    SELECT
        CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InvoiceDate         AS DATE)        AS InvoiceDate
    FROM [SalesHistory_Enh].[InvoiceDetailLineLevel]
    WHERE ItemSKU IS NOT NULL
      AND WarehouseCode IS NOT NULL
      AND TRIM(ItemSKU) <> ''
      AND TRIM(WarehouseCode) <> ''
      AND InvoiceDate IS NOT NULL
),
__bob_source AS (
SELECT
    b.ItemSku,
    b.WarehouseCode,
    b.WeekEndingDate,
    CAST(MAX(i.InvoiceDate) AS DATE) AS LastInvoiceDate,
    CAST(
        CASE
            WHEN MAX(i.InvoiceDate) IS NULL THEN NULL
            ELSE DATEDIFF(week, MAX(i.InvoiceDate), b.WeekEndingDate)
        END
        AS INT
    ) AS WeeksSinceLastInvoice
FROM _BaseFact AS b
LEFT JOIN _InvoiceDetail AS i
    ON i.ItemSku = b.ItemSku
   AND i.WarehouseCode = b.WarehouseCode
   AND i.InvoiceDate <= b.WeekEndingDate
GROUP BY
    b.ItemSku,
    b.WarehouseCode,
    b.WeekEndingDate
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [WeekEndingDate] = src.[WeekEndingDate],
    [LastInvoiceDate] = src.[LastInvoiceDate],
    [WeeksSinceLastInvoice] = src.[WeeksSinceLastInvoice],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
