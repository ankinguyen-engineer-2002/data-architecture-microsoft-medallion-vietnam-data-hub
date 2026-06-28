-- InventoryHistory_Enh_Wrk.v_SafetyStockHelper
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_SafetyStockHelper] AS
WITH asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(
            MONTH,
            3,
            DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)
        ) AS HorizonEndDate
    FROM asof_dates
),
latest_snap AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotWeekEndingDate) AS LatestSnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
        ON isw.SnapshotWeekEndingDate <= a.AsOfDate
       AND isw.SnapshotWeekEndingDate > DATEADD(WEEK,-13,a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate
),
fiscal_ss AS (
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM latest_snap ls
    JOIN asof a
        ON a.AsOfDate = ls.AsOfDate
    JOIN InventoryHistory_Enh.InventorySnapshotWeekly isw
        ON isw.ItemSku = ls.ItemSku
       AND isw.WarehouseCode = ls.WarehouseCode
       AND isw.SnapshotWeekEndingDate = ls.LatestSnapshotDate
       AND isw.FiscalMonthDate >= a.HorizonStartDate
       AND isw.FiscalMonthDate <  a.HorizonEndDate
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate
)
SELECT
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate AS DATE) AS AsOfDate,
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(SnapshotCount AS INT) AS SnapshotCount,
    CAST('Next3FiscalMonths' AS VARCHAR(30)) AS SafetyStockSource,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM fiscal_ss;
