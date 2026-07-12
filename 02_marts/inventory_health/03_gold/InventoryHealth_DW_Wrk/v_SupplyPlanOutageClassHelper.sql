-- InventoryHealth_DW_Wrk.v_SupplyPlanOutageClassHelper
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_SupplyPlanOutageClassHelper] AS
WITH sp AS (
    SELECT
        CAST(TRIM(ItemSku) AS varchar(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS varchar(50)) AS WarehouseCode,
        CAST(SnapshotDate AS date) AS SnapshotDate,
        CAST(WeekEnding AS date) AS WeekEnding,
        CAST(COALESCE(SIQty, 0) AS decimal(18,4)) AS SIQty,
        MAX(CAST(SnapshotDate AS date)) OVER () AS LatestSnapshotDate
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SupplyPlanDetail]
    WHERE ItemSku IS NOT NULL
      AND WarehouseCode IS NOT NULL
      AND SnapshotDate IS NOT NULL
      AND WeekEnding IS NOT NULL
      AND TRIM(ItemSku) <> ''
      AND TRIM(WarehouseCode) <> ''
),

calc AS (
    SELECT
        b.ItemSku,
        b.WarehouseCode,
        b.WeekEnding,

        CAST(SUM(CASE
            WHEN p.WeekEnding >= DATEADD(week, -8, b.WeekEnding)
             AND p.WeekEnding <  b.WeekEnding
             AND p.SIQty < 0
                THEN 1
            ELSE 0
        END) AS int) AS PastNegativeWeekCount,

        CAST(SUM(CASE
            WHEN p.WeekEnding >= b.WeekEnding
             AND p.WeekEnding <= DATEADD(week, 7, b.WeekEnding)
             AND p.SIQty < 0
                THEN 1
            ELSE 0
        END) AS int) AS FutureNegativeWeekCount

    FROM sp b
    LEFT JOIN sp p
        ON p.ItemSku = b.ItemSku
       AND p.WarehouseCode = b.WarehouseCode
       AND p.WeekEnding >= DATEADD(week, -8, b.WeekEnding)
       AND p.WeekEnding <= DATEADD(week,  7, b.WeekEnding)
    GROUP BY
        b.ItemSku,
        b.WarehouseCode,
        b.WeekEnding
),

scored AS (
    SELECT
        ItemSku,
        WarehouseCode,
        WeekEnding,
        PastNegativeWeekCount,
        FutureNegativeWeekCount,
        CAST(
            (
                PastNegativeWeekCount * 0.75
                + FutureNegativeWeekCount * 1.25
            ) / 16.0
            AS decimal(18,4)
        ) AS WeightedSINegScore
    FROM calc
)

SELECT
    ItemSku,
    WarehouseCode,
    WeekEnding,
    PastNegativeWeekCount,
    FutureNegativeWeekCount,
    WeightedSINegScore,
    CAST(CASE
        WHEN WeightedSINegScore >= 0.50 THEN 'persistent'
        WHEN WeightedSINegScore >= 0.35 THEN 'semi-persistent'
        ELSE 'transient'
    END AS varchar(30)) AS OutageClass,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS LoadDT
FROM scored;
