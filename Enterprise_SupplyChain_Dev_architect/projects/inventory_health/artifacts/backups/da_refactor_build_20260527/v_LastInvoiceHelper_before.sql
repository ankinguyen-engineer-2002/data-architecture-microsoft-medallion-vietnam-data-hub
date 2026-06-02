-- ---- InventoryHistory_Enh.v_LastInvoiceHelper ----
-- MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
CREATE   VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.InventoryCurrent (dropped entity)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
asof AS (
    SELECT DISTINCT SnapshotDate AS AsOfDate
    FROM _InventoryCurrent
    WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(s.WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate          AS DATE)          AS AsOfDate,
    CAST(MAX(s.InvoiceDate)  AS DATE)          AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM InventoryHistory_Enh.SalesShipment s
JOIN asof a ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate