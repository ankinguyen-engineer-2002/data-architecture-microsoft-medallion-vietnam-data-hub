-- ---- InventoryHistory_Enh.v_LastInvoiceDateSnapshotWeekly ----
-- Weekly grain output for Gold fact join:
--   ItemSku + WarehouseCode + WeekEndingDate
-- Purpose:
--   Same as-of logic as v_LastInvoiceHelper, but does NOT depend on it.
--   This supports future retirement of v_LastInvoiceHelper without breaking KPI joins.
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LastInvoiceDateSnapshotWeekly AS
WITH
_BaseFact AS (
    SELECT DISTINCT
        CAST(SnapshotDate AS DATE)               AS WeekEndingDate,
        CAST(TRIM(ItemSku) AS VARCHAR(50))       AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode
    FROM InventoryHistory_Enh.v_InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate IS NOT NULL
      AND ItemSku IS NOT NULL AND TRIM(ItemSku) <> ''
      AND WarehouseCode IS NOT NULL AND TRIM(WarehouseCode) <> ''
),
_InvoiceDetail AS (
    SELECT
        CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InvoiceDate         AS DATE)        AS InvoiceDate
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
    WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
      AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
      AND InvoiceDate IS NOT NULL
)
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

GO
