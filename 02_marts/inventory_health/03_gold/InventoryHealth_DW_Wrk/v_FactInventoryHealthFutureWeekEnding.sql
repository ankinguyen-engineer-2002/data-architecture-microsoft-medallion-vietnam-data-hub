-- SupplyChain_Gold_Warehouse.InventoryHealth_DW_Wrk.v_FactInventoryHealthFutureWeekEnding
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_FactInventoryHealthFutureWeekEnding] AS
WITH sp_base AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS Item,
        CAST(WarehouseCode AS VARCHAR(50)) AS WH,
        CAST(WeekEnding AS DATE) AS WeekEnding,
        CAST(SnapshotDate AS DATE) AS SnapshotDate,
        CAST(SnapshotDate AS DATE) AS SupplyPlanSnapshotDate,
        CAST(SIQty AS DECIMAL(18,4)) AS TotalInvCommitmentInFuture,
        CAST(SafetyStockQty AS DECIMAL(18,4)) AS SSTarget,
        CAST(FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(NetFcstQty AS DECIMAL(18,4)) AS NetFcstQty,
        CAST(FirmDemandQtyAtRisk AS DECIMAL(18,4)) AS FirmDemandQtyAtRisk,
        CAST(NetFcstQtyAtRisk AS DECIMAL(18,4)) AS NetFcstQtyAtRisk,
        CAST(IsActiveItemWhIn7DNext AS INT) AS IsActiveItemWhIn7DNext,
        CAST(IsActiveItemWhIn14DNext AS INT) AS IsActiveItemWhIn14DNext,
        CAST(LatestSupplyPlanSnapshotDate AS DATE) AS LatestSupplyPlanSnapshotDate
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SupplyPlanDetail]
    WHERE IsLatestSupplyPlanSnapshot = 1
),
inventory_latest AS (
    SELECT
        ItemSku,
        WarehouseCode,
        InventorySnapshotDate,
        MakeBuyCode,
        PrimaryVendorName,
        SecondaryVendorName,
        ReplenishmentLeadTime
    FROM (
        SELECT
            CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
            CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
            CAST(SnapshotWeekEndingDate AS DATE) AS InventorySnapshotDate,
            CAST(MakeBuyCode AS VARCHAR(10)) AS MakeBuyCode,
            CAST(PrimaryVendorName AS VARCHAR(200)) AS PrimaryVendorName,
            CAST(SecondaryVendorName AS VARCHAR(200)) AS SecondaryVendorName,
            CAST(ReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode
                ORDER BY SnapshotWeekEndingDate DESC, FiscalMonthDate ASC
            ) AS rn
        FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeekly]
        WHERE IsLatestInventorySnapshot = 1
    ) ranked_inv
    WHERE rn = 1
),
atp_latest AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS Item,
        CAST(WarehouseCode AS VARCHAR(50)) AS WH,
        CAST(SnapshotDate AS DATE) AS AtpSnapshotDate,
        CAST(WeekEndingDate AS DATE) AS WeekEnding,
        SUM(COALESCE(AtpQty, 0)) AS AtpQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AtpWeekEnding]
    WHERE IsLatestAtpSnapshot = 1
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        WeekEndingDate
),
awd_ranked AS (
    SELECT
        sp.Item,
        sp.WH,
        sp.SnapshotDate,
        sp.WeekEnding,
        CAST(awd.AsOfDate AS DATE) AS AwdAsOfDate,
        CAST(awd.AwdQty AS DECIMAL(18,4)) AS AvgWeeklyDemand,
        ROW_NUMBER() OVER (
            PARTITION BY sp.Item, sp.WH, sp.SnapshotDate, sp.WeekEnding
            ORDER BY awd.AsOfDate DESC
        ) AS rn
    FROM sp_base sp
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
        ON awd.ItemSku = sp.Item
       AND awd.WarehouseCode = sp.WH
       AND awd.AsOfDate <= sp.SnapshotDate
),
awd_latest AS (
    SELECT
        Item,
        WH,
        SnapshotDate,
        WeekEnding,
        AwdAsOfDate,
        AvgWeeklyDemand
    FROM awd_ranked
    WHERE rn = 1
),
afi_ranked AS (
    SELECT
        sp.Item,
        sp.WH,
        sp.SnapshotDate,
        sp.WeekEnding,
        CAST(afi.WeekEndingDate AS DATE) AS AfiStatusAsOfDate,
        CAST(afi.AFIStatus AS VARCHAR(20)) AS AFIStatus,
        ROW_NUMBER() OVER (
            PARTITION BY sp.Item, sp.WH, sp.SnapshotDate, sp.WeekEnding
            ORDER BY afi.WeekEndingDate DESC
        ) AS rn
    FROM sp_base sp
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AFIStatusSnapshotWeekly] afi
        ON afi.ItemSku = sp.Item
       AND afi.WarehouseCode = sp.WH
       AND afi.WeekEndingDate <= sp.SnapshotDate
),
afi_latest AS (
    SELECT
        Item,
        WH,
        SnapshotDate,
        WeekEnding,
        AfiStatusAsOfDate,
        AFIStatus
    FROM afi_ranked
    WHERE rn = 1
),
joined AS (
    SELECT
        sp.Item,
        sp.WH,
        sp.WeekEnding,
        sp.SnapshotDate,
        sp.TotalInvCommitmentInFuture,
        COALESCE(atp.AtpQty, 0) AS AtpQty,
        inv.MakeBuyCode,
        inv.PrimaryVendorName,
        inv.SecondaryVendorName,
        inv.ReplenishmentLeadTime,
        awd.AvgWeeklyDemand,
        sp.SSTarget,
        afi.AFIStatus,
        dp.Cubes,
        dp.FOBArcPrice AS FobArcPrice,
        inv.InventorySnapshotDate,
        sp.SupplyPlanSnapshotDate,
        atp.AtpSnapshotDate,
        cls.ProjectedInventoryClassificationFinalStatus AS ProjectedInventoryClassification,
        sp.FirmDemandQty,
        sp.NetFcstQty,
        sp.FirmDemandQtyAtRisk,
        sp.NetFcstQtyAtRisk,
        sp.IsActiveItemWhIn7DNext,
        sp.IsActiveItemWhIn14DNext,
        sp.LatestSupplyPlanSnapshotDate,
        awd.AwdAsOfDate,
        afi.AfiStatusAsOfDate
    FROM sp_base sp
    LEFT JOIN inventory_latest inv
        ON inv.ItemSku = sp.Item
       AND inv.WarehouseCode = sp.WH
    LEFT JOIN atp_latest atp
        ON atp.Item = sp.Item
       AND atp.WH = sp.WH
       AND atp.WeekEnding = sp.WeekEnding
    LEFT JOIN awd_latest awd
        ON awd.Item = sp.Item
       AND awd.WH = sp.WH
       AND awd.SnapshotDate = sp.SnapshotDate
       AND awd.WeekEnding = sp.WeekEnding
    LEFT JOIN afi_latest afi
        ON afi.Item = sp.Item
       AND afi.WH = sp.WH
       AND afi.SnapshotDate = sp.SnapshotDate
       AND afi.WeekEnding = sp.WeekEnding
    LEFT JOIN [SupplyChain_Gold_Warehouse].[InventoryHealth_DW].[ProjectedInventoryHealthSubStatus] cls
        ON cls.ItemSku = sp.Item
       AND cls.WarehouseCode = sp.WH
       AND cls.FactAsOfDate = sp.SnapshotDate
       AND cls.FutureWeekEndingDate = sp.WeekEnding
    LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimProduct] dp
        ON dp.ItemSKU = sp.Item
),
__bob_source AS (
SELECT
    CAST(Item AS VARCHAR(50)) AS ItemSku,
    CAST(WH AS VARCHAR(50)) AS WarehouseCode,
    CAST(WeekEnding AS DATE) AS [FutureWeekEnding],
    CAST(SnapshotDate AS DATE) AS SnapshotDate,
    CAST(TotalInvCommitmentInFuture AS DECIMAL(18,4)) AS [TotalInvCommitmentInFuture],
    CAST(AtpQty AS DECIMAL(18,4)) AS [ATPQty],
    CAST(CASE
            WHEN COALESCE(TotalInvCommitmentInFuture, 0) < 0 THEN 'SHORTAGE'
            WHEN ProjectedInventoryClassification IN (
                    'TB_INVENTORY',
                    'AGGRESSIVE_EXCESS',
                    'EXCESS',
                    'OVER_TARGET',
                    'SLOB',
                    'INACTIVE'
                 ) THEN 'SURPLUS'
            WHEN ProjectedInventoryClassification IN (
                    'SWEET_SPOT',
                    'BELOW_TARGET'
                 ) THEN 'IN_STOCK'
            ELSE 'UNCLASSIFIED'
         END AS VARCHAR(30)) AS [IsShortage/Surplus/InStock],
    CAST(CASE
            WHEN COALESCE(TotalInvCommitmentInFuture, 0) < 0
                THEN ABS(COALESCE(TotalInvCommitmentInFuture, 0))
            WHEN ProjectedInventoryClassification IN (
                    'TB_INVENTORY',
                    'AGGRESSIVE_EXCESS',
                    'EXCESS',
                    'OVER_TARGET',
                    'SLOB',
                    'INACTIVE'
                 ) THEN COALESCE(TotalInvCommitmentInFuture, 0)
            ELSE 0
         END AS DECIMAL(18,4)) AS [Shortage/SurplusQty],
    CAST(MakeBuyCode AS VARCHAR(10)) AS MakeBuyCode,
    CAST(PrimaryVendorName AS VARCHAR(200)) AS PrimaryVendorName,
    CAST(SecondaryVendorName AS VARCHAR(200)) AS [SecondaryVendorName],
    CAST(ReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime,
    CAST(COALESCE(TotalInvCommitmentInFuture, 0) * COALESCE(Cubes, 0) AS DECIMAL(18,4)) AS UsedStoreCube,
    CAST(CASE
            WHEN COALESCE(TotalInvCommitmentInFuture, 0) < 0
                THEN COALESCE(TotalInvCommitmentInFuture, 0) * COALESCE(FobArcPrice, 0)
            ELSE 0
         END AS DECIMAL(18,4)) AS ProjectedRevenueAtRisk,
    CAST(CASE
            WHEN COALESCE(AvgWeeklyDemand, 0) > 0
                THEN COALESCE(TotalInvCommitmentInFuture, 0) / AvgWeeklyDemand
            ELSE NULL
         END AS DECIMAL(18,4)) AS ProjectedWOS,
    CAST(ProjectedInventoryClassification AS VARCHAR(30)) AS ProjectedInventoryClassification,
    CAST(AvgWeeklyDemand AS DECIMAL(18,4)) AS [AwdQty],
    CAST(SSTarget AS DECIMAL(18,4)) AS [SafetyStockTarget],
    CAST(AFIStatus AS VARCHAR(20)) AS [AFIStatus],
    CAST(Cubes AS DECIMAL(18,4)) AS Cubes,
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
FROM joined
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [FutureWeekEnding] = src.[FutureWeekEnding],
    [SnapshotDate] = src.[SnapshotDate],
    [TotalInvCommitmentInFuture] = src.[TotalInvCommitmentInFuture],
    [ATPQty] = src.[ATPQty],
    [IsShortage/Surplus/InStock] = src.[IsShortage/Surplus/InStock],
    [Shortage/SurplusQty] = src.[Shortage/SurplusQty],
    [MakeBuyCode] = src.[MakeBuyCode],
    [PrimaryVendorName] = src.[PrimaryVendorName],
    [SecondaryVendorName] = src.[SecondaryVendorName],
    [ReplenishmentLeadTime] = src.[ReplenishmentLeadTime],
    [UsedStoreCube] = src.[UsedStoreCube],
    [ProjectedRevenueAtRisk] = src.[ProjectedRevenueAtRisk],
    [ProjectedWOS] = src.[ProjectedWOS],
    [ProjectedInventoryClassification] = src.[ProjectedInventoryClassification],
    [AwdQty] = src.[AwdQty],
    [SafetyStockTarget] = src.[SafetyStockTarget],
    [AFIStatus] = src.[AFIStatus],
    [Cubes] = src.[Cubes],
    [InventorySnapshotDate] = src.[InventorySnapshotDate],
    [SupplyPlanSnapshotDate] = src.[SupplyPlanSnapshotDate],
    [ATPSnapshotDate] = src.[ATPSnapshotDate],
    [FirmDemandQty] = src.[FirmDemandQty],
    [NetFcstQty] = src.[NetFcstQty],
    [FirmDemandQtyAtRisk] = src.[FirmDemandQtyAtRisk],
    [NetFcstQtyAtRisk] = src.[NetFcstQtyAtRisk],
    [IsActiveItemWhIn7DNext] = src.[IsActiveItemWhIn7DNext],
    [IsActiveItemWhIn14DNext] = src.[IsActiveItemWhIn14DNext],
    [LatestSupplyPlanSnapshotDate] = src.[LatestSupplyPlanSnapshotDate],
    [AwdAsOfDate] = src.[AwdAsOfDate],
    [AfiStatusAsOfDate] = src.[AfiStatusAsOfDate]
FROM __bob_source AS src;
