-- ---- InventoryHistory_Enh.v_MovementFlagHelper ----
-- HasMovementLast17W: InvoiceDetail as movement signal per BRD §6 (only sales count for SLOB).
CREATE OR ALTER VIEW InventoryHistory_Enh.v_MovementFlagHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
moves AS (
    SELECT
        s.ItemSku, s.WarehouseCode, a.AsOfDate,
        MAX(CASE WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                  AND s.InvoiceDate <= a.AsOfDate
                 THEN 1 ELSE 0 END) AS HasMovementLast17W,
        COUNT(*)                    AS MovementCountLast17W
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
    JOIN asof a
         ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(ItemSku                AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode          AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate               AS DATE)        AS AsOfDate,
    CAST(HasMovementLast17W     AS BIT)         AS HasMovementLast17W,
    CAST(MovementCountLast17W   AS INT)         AS MovementCountLast17W
FROM moves

GO
