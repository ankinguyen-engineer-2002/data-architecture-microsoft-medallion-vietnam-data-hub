-- InventoryHealth_DW_Wrk.v_FactInventoryHealthFutureWeekEnding
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_FactInventoryHealthFutureWeekEnding] AS
WITH projected_base AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS Item,
        CAST(WarehouseCode AS VARCHAR(50)) AS WH,
        CAST(FutureWeekEndingDate AS DATE) AS WeekEnding,
        CAST(FactAsOfDate AS DATE) AS SnapshotDate,
        CAST(SupplyPlanSnapshotDate AS DATE) AS SupplyPlanSnapshotDate,
        CAST(ProjectedInventoryQty AS DECIMAL(18,4)) AS TotalInvCommitmentInFuture,
        CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SSTarget,
        CAST(FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(NetFcstQty AS DECIMAL(18,4)) AS NetFcstQty,
        CAST(FirmDemandQtyAtRisk AS DECIMAL(18,4)) AS FirmDemandQtyAtRisk,
        CAST(NetFcstQtyAtRisk AS DECIMAL(18,4)) AS NetFcstQtyAtRisk,
        CAST(IsActiveItemWhIn7DNext AS INT) AS IsActiveItemWhIn7DNext,
        CAST(IsActiveItemWhIn14DNext AS INT) AS IsActiveItemWhIn14DNext,
        CAST(LatestSupplyPlanSnapshotDate AS DATE) AS LatestSupplyPlanSnapshotDate,
        CAST(AvgWeeklyDemand AS DECIMAL(18,4)) AS AvgWeeklyDemand,
        CAST(AwdAsOfDate AS DATE) AS AwdAsOfDate,
        CAST(AFIStatus AS VARCHAR(20)) AS AFIStatus,
        CAST(AfiStatusAsOfDate AS DATE) AS AfiStatusAsOfDate,
        CAST(ProjectedInventoryClassificationFinalStatus AS VARCHAR(30))
            AS ProjectedInventoryClassification
    FROM [InventoryHealth_DW].[ProjectedInventoryHealthSubStatus]
),
-- Only the future weeks required by the Gold projection.
future_weeks AS (
    SELECT DISTINCT
        WeekEnding
    FROM projected_base
    WHERE WeekEnding IS NOT NULL
),
inventory_latest AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(SnapshotWeekEndingDate AS DATE)
            AS InventorySnapshotDate,
        CAST(MakeBuyCode AS VARCHAR(10))
            AS MakeBuyCode,
        CAST(PrimaryVendorName AS VARCHAR(200))
            AS PrimaryVendorName,
        CAST(SecondaryVendorName AS VARCHAR(200))
            AS SecondaryVendorName,
        CAST(ReplenishmentLeadTime AS DECIMAL(18,4))
            AS ReplenishmentLeadTime
    FROM [InventoryHealth_Internal].[InventorySnapshotWeeklyBase]
    WHERE SnapshotType = 'LATEST'
),
-- Read Silver ATP only for weeks required by Gold Future.
atp_future_weeks AS (
    SELECT
        CAST(atp.ItemSku AS VARCHAR(50)) AS Item,
        CAST(atp.WarehouseCode AS VARCHAR(50)) AS WH,
        CAST(atp.SnapshotDate AS DATE) AS AtpSnapshotDate,
        CAST(atp.WeekEndingDate AS DATE) AS WeekEnding,
        SUM(COALESCE(atp.AtpQty, 0)) AS AtpQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AtpWeekEnding] AS atp
    INNER JOIN future_weeks AS fw
        ON fw.WeekEnding = CAST(atp.WeekEndingDate AS DATE)
    GROUP BY
        atp.ItemSku,
        atp.WarehouseCode,
        atp.SnapshotDate,
        atp.WeekEndingDate
),
standard_cost AS (
    SELECT
        ItemSku,
        StandardCost,
        StandardCostRevision
    FROM (
        SELECT
            CAST(TRIM(ITNBR) AS VARCHAR(50)) AS ItemSku,
            CAST(UCDEF AS DECIMAL(18,4)) AS StandardCost,
            CAST(ITRV AS VARCHAR(20)) AS StandardCostRevision,
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
    ) ranked_cost
    WHERE rn = 1
),
joined AS (
    SELECT
        p.Item,
        p.WH,
        p.WeekEnding,
        p.SnapshotDate,
        p.TotalInvCommitmentInFuture,
        COALESCE(atp.AtpQty, 0) AS AtpQty,
        inv.MakeBuyCode,
        inv.PrimaryVendorName,
        inv.SecondaryVendorName,
        inv.ReplenishmentLeadTime,
        p.AvgWeeklyDemand,
        p.SSTarget,
        p.AFIStatus,
        dp.Cubes,
        cost.StandardCost,
        dp.FOBArcPrice AS FobArcPrice,
        inv.InventorySnapshotDate,
        p.SupplyPlanSnapshotDate,
        atp.AtpSnapshotDate,
        p.ProjectedInventoryClassification,
        p.FirmDemandQty,
        p.NetFcstQty,
        p.FirmDemandQtyAtRisk,
        p.NetFcstQtyAtRisk,
        p.IsActiveItemWhIn7DNext,
        p.IsActiveItemWhIn14DNext,
        p.LatestSupplyPlanSnapshotDate,
        p.AwdAsOfDate,
        p.AfiStatusAsOfDate
    FROM projected_base AS p
    LEFT JOIN inventory_latest AS inv
        ON inv.ItemSku = p.Item
       AND inv.WarehouseCode = p.WH
    LEFT JOIN atp_future_weeks AS atp
        ON atp.Item = p.Item
       AND atp.WH = p.WH
       AND atp.WeekEnding = p.WeekEnding
    LEFT JOIN standard_cost AS cost
        ON cost.ItemSku = p.Item
    LEFT JOIN [Shared_DW].[DimProduct] AS dp
        ON dp.ItemSKU COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8 = p.Item COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8
)
SELECT
    CAST(Item AS VARCHAR(50)) AS ItemSku,
    CAST(WH AS VARCHAR(50)) AS WarehouseCode,
    CAST(WeekEnding AS DATE) AS [FutureWeekEnding],
    CAST(SnapshotDate AS DATE) AS SnapshotDate,
    CAST(TotalInvCommitmentInFuture AS DECIMAL(18,4)) AS [SIQty],
    CAST(AtpQty AS DECIMAL(18,4)) AS [ATPQty],
    CAST(
        CASE
            WHEN ProjectedInventoryClassification IN (
                'TB_INVENTORY',
                'AGGRESSIVE_EXCESS',
                'EXCESS',
                'OVER_TARGET',
                'INACTIVE'
            ) THEN 'SURPLUS'
            WHEN ProjectedInventoryClassification IN (
                'BELOW_TARGET',
                'SWEET_SPOT'
            ) THEN
                CASE
                    WHEN COALESCE(TotalInvCommitmentInFuture, 0) < 0 THEN 'SHORTAGE'
                    ELSE 'IN_STOCK'
                END
            WHEN ProjectedInventoryClassification = 'SLOB' THEN
                CASE
                    WHEN COALESCE(TotalInvCommitmentInFuture, 0) < 0 THEN 'SHORTAGE'
                    ELSE 'SURPLUS'
                END
            ELSE 'UNCLASSIFIED'
        END AS VARCHAR(30)
    ) AS [IsShortage/Surplus/InStock],
    CAST(
        CASE
            WHEN ProjectedInventoryClassification IN (
                'BELOW_TARGET',
                'SWEET_SPOT',
                'SLOB'
            )
             AND COALESCE(TotalInvCommitmentInFuture, 0) < 0
                THEN ABS(COALESCE(TotalInvCommitmentInFuture, 0))
            WHEN ProjectedInventoryClassification IN (
                'TB_INVENTORY',
                'AGGRESSIVE_EXCESS',
                'EXCESS',
                'OVER_TARGET',
                'INACTIVE',
                'BELOW_TARGET',
                'SWEET_SPOT',
                'SLOB'
            ) THEN COALESCE(TotalInvCommitmentInFuture, 0)
            ELSE 0
        END AS DECIMAL(18,4)
    ) AS [Shortage/SurplusQty],
    CAST(MakeBuyCode AS VARCHAR(10)) AS MakeBuyCode,
    CAST(PrimaryVendorName AS VARCHAR(200)) AS PrimaryVendorName,
    CAST(SecondaryVendorName AS VARCHAR(200)) AS [SecondaryVendorName],
    CAST(ReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime,
    CAST(COALESCE(TotalInvCommitmentInFuture, 0) * COALESCE(Cubes, 0) AS DECIMAL(18,4)) AS UsedStoreCube,
    CAST(
        CASE
            WHEN ProjectedInventoryClassification IN (
                'BELOW_TARGET',
                'SWEET_SPOT',
                'SLOB'
            )
             AND COALESCE(TotalInvCommitmentInFuture, 0) < 0
                THEN ABS(COALESCE(TotalInvCommitmentInFuture, 0)) * COALESCE(FobArcPrice, 0)
            ELSE 0
        END AS DECIMAL(18,4)
    ) AS ProjectedShortageValue,
    CAST(
        CASE
            WHEN COALESCE(AvgWeeklyDemand, 0) <= 0 THEN NULL
            WHEN TotalInvCommitmentInFuture <= 0 THEN 0
            ELSE TotalInvCommitmentInFuture / AvgWeeklyDemand
        END AS DECIMAL(18,4)
    ) AS ProjectedWOS,
    CAST(ProjectedInventoryClassification AS VARCHAR(30)) AS ProjectedInventoryClassification,
    CAST(AvgWeeklyDemand AS DECIMAL(18,4)) AS [AwdQty],
    CAST(SSTarget AS DECIMAL(18,4)) AS [SafetyStockTarget],
    CAST(AFIStatus AS VARCHAR(20)) AS [AFIStatus],
    CAST(Cubes AS DECIMAL(18,4)) AS Cubes,
    CAST(StandardCost AS DECIMAL(18,4)) AS StandardCost,
    CAST(FobArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
    CAST(InventorySnapshotDate AS DATE) AS InventorySnapshotDate,
    CAST(SupplyPlanSnapshotDate AS DATE) AS SupplyPlanSnapshotDate,
    CAST(AtpSnapshotDate AS DATE) AS ATPSnapshotDate,
    CAST(FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(NetFcstQty AS DECIMAL(18,4)) AS NetFcstQty,
    CAST(FirmDemandQtyAtRisk AS DECIMAL(18,4)) AS FirmDemandQtyAtRisk,
    CAST(NetFcstQtyAtRisk AS DECIMAL(18,4)) AS NetFcstQtyAtRisk,
    CAST(IsActiveItemWhIn7DNext AS INT) AS IsActiveItemWhIn7DNext,
    CAST(IsActiveItemWhIn14DNext AS INT) AS IsActiveItemWhIn14DNext,
    CAST(LatestSupplyPlanSnapshotDate AS DATE) AS LatestSupplyPlanSnapshotDate,
    CAST(AwdAsOfDate AS DATE) AS AwdAsOfDate,
    CAST(AfiStatusAsOfDate AS DATE) AS AfiStatusAsOfDate
FROM joined;

GO
