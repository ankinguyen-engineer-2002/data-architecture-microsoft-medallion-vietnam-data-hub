-- ---- InventoryHistory_Enh.v_LastInvoiceHelper ----
-- MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(s.WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate          AS DATE)          AS AsOfDate,
    CAST(MAX(s.InvoiceDate)  AS DATE)          AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM (
    SELECT
        CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InvoiceDate         AS DATE)        AS InvoiceDate
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
    WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
      AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
      AND InvoiceDate IS NOT NULL
) s
JOIN asof a ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate

GO
