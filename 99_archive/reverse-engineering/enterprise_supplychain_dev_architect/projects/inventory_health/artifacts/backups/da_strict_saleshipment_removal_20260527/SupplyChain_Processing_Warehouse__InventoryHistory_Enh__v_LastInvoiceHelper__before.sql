-- ---------------------------------------------------------------------
-- Last invoice candidate: DA as-of behavior + Mart A invoice source.
-- ---------------------------------------------------------------------
CREATE   VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(s.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(a.AsOfDate AS DATE) AS AsOfDate,
    CAST(MAX(s.InvoiceDate) AS DATE) AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM InventoryHistory_Enh.v_SalesShipment s
JOIN asof a
  ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate;