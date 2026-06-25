-- InventoryHistory_Enh_Wrk.v_Cogs52WWeekly
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_Cogs52WWeekly] AS
WITH base_fact AS (
    SELECT DISTINCT
        TRIM(ItemSku) AS ItemSku,
        TRIM(WarehouseCode) AS WarehouseCode,
        CAST(SnapshotWeekEndingDate AS DATE) AS WeekEndingDate
    FROM [InventoryHistory_Enh].[InventorySnapshotWeekly]
    WHERE ItemSku IS NOT NULL
      AND WarehouseCode IS NOT NULL
      AND SnapshotWeekEndingDate IS NOT NULL
),
calendar_source AS (
    SELECT
        CAST([Date] AS DATE) AS CalendarDate,
        CAST(FSCWeekLast AS DATE) AS WeekEndingDate
    FROM [ReferenceMaster_Enh].[Calendar]
    WHERE [Date] IS NOT NULL
      AND FSCWeekLast IS NOT NULL
),
standard_cost AS (
    SELECT
        x.ItemSku,
        x.StandardCost,
        x.StandardCostRevision
    FROM (
        SELECT
            TRIM(ITNBR) AS ItemSku,
            CAST(UCDEF AS DECIMAL(18,4)) AS StandardCost,
            ITRV AS StandardCostRevision,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(STID), TRIM(ITNBR)
                ORDER BY ITRV DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL
          AND ITNBR IS NOT NULL
          AND UCDEF IS NOT NULL
          AND TRIM(STID) = '000'
          AND TRIM(ITNBR) <> ''
    ) x
    WHERE x.rn = 1
),
invoice_line_scoped AS (
    SELECT
        TRIM(i.ItemSKU) AS ItemSku,
        TRIM(i.WarehouseCode) AS WarehouseCode,
        c.WeekEndingDate,
        CAST(i.QtyShipped AS DECIMAL(18,4)) AS QtyShipped,
        sc.StandardCost,
        sc.StandardCostRevision
    FROM [SalesHistory_Enh].[InvoiceDetailLineLevel] i
    INNER JOIN calendar_source c
        ON c.CalendarDate = CAST(i.InvoiceDate AS DATE)
    LEFT JOIN standard_cost sc
        ON sc.ItemSku = TRIM(i.ItemSKU)
    WHERE i.ItemSKU IS NOT NULL
      AND i.WarehouseCode IS NOT NULL
      AND i.InvoiceDate IS NOT NULL
      AND i.QtyShipped IS NOT NULL
      AND TRIM(i.ItemSKU) <> ''
      AND TRIM(i.WarehouseCode) <> ''
),
invoice_weekly AS (
    SELECT
        ItemSku,
        WarehouseCode,
        WeekEndingDate,
        MAX(StandardCost) AS StandardCost,
        MAX(StandardCostRevision) AS StandardCostRevision,
        SUM(QtyShipped) AS PeriodShippedQty,
        SUM(QtyShipped * COALESCE(StandardCost, 0)) AS PeriodCogs
    FROM invoice_line_scoped
    GROUP BY
        ItemSku,
        WarehouseCode,
        WeekEndingDate
),
cogs52w AS (
    SELECT
        b.ItemSku,
        b.WarehouseCode,
        b.WeekEndingDate,
        DATEADD(week, -51, b.WeekEndingDate) AS RollingWindowStartDate,
        b.WeekEndingDate AS RollingWindowEndDate,
        MAX(sc.StandardCost) AS StandardCost,
        MAX(sc.StandardCostRevision) AS StandardCostRevision,
        COALESCE(MAX(cw.PeriodShippedQty), 0) AS PeriodShippedQty,
        COALESCE(MAX(cw.PeriodCogs), 0) AS PeriodCogs,
        COALESCE(SUM(rw.PeriodShippedQty), 0) AS ShippedQty52W,
        COALESCE(SUM(rw.PeriodCogs), 0) AS COGS52W
    FROM base_fact b
    LEFT JOIN standard_cost sc
        ON sc.ItemSku = b.ItemSku
    LEFT JOIN invoice_weekly cw
        ON cw.ItemSku = b.ItemSku
       AND cw.WarehouseCode = b.WarehouseCode
       AND cw.WeekEndingDate = b.WeekEndingDate
    LEFT JOIN invoice_weekly rw
        ON rw.ItemSku = b.ItemSku
       AND rw.WarehouseCode = b.WarehouseCode
       AND rw.WeekEndingDate BETWEEN DATEADD(week, -51, b.WeekEndingDate) AND b.WeekEndingDate
    GROUP BY
        b.ItemSku,
        b.WarehouseCode,
        b.WeekEndingDate
)
SELECT
    ItemSku,
    WarehouseCode,
    WeekEndingDate,
    RollingWindowStartDate,
    RollingWindowEndDate,
    CAST(StandardCost AS DECIMAL(18,4)) AS StandardCost,
    StandardCostRevision,
    CAST(PeriodShippedQty AS DECIMAL(18,4)) AS PeriodShippedQty,
    CAST(PeriodCogs AS DECIMAL(18,4)) AS PeriodCogs,
    CAST(ShippedQty52W AS DECIMAL(18,4)) AS ShippedQty52W,
    CAST(COGS52W AS DECIMAL(18,4)) AS COGS52W,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM cogs52w;
