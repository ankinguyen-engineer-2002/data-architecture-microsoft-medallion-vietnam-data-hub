-- InventoryHealth_DW_Wrk.v_ProjectedInventoryHealthSubStatus
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_ProjectedInventoryHealthSubStatus] AS
WITH sp_base AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(SnapshotDate AS DATE) AS FactAsOfDate,
        CAST(SnapshotDate AS DATE) AS SupplyPlanSnapshotDate,
        CAST(WeekEnding AS DATE) AS FutureWeekEndingDate,
        CAST(SIQty AS DECIMAL(18,4)) AS ProjectedInventoryQty,
        CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(NetFcstQty AS DECIMAL(18,4)) AS NetFcstQty,
        CAST(FirmDemandQtyAtRisk AS DECIMAL(18,4)) AS FirmDemandQtyAtRisk,
        CAST(NetFcstQtyAtRisk AS DECIMAL(18,4)) AS NetFcstQtyAtRisk,
        CAST(IsActiveItemWhIn7DNext AS INT) AS IsActiveItemWhIn7DNext,
        CAST(IsActiveItemWhIn14DNext AS INT) AS IsActiveItemWhIn14DNext,
        CAST(IsLatestSupplyPlanSnapshot AS INT) AS IsLatestSupplyPlanSnapshot,
        CAST(SnapshotType AS VARCHAR(30)) AS SupplyPlanSnapshotType,
        CAST(LatestSupplyPlanSnapshotDate AS DATE) AS LatestSupplyPlanSnapshotDate
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SupplyPlanDetail]
    WHERE IsLatestSupplyPlanSnapshot = 1
      AND ItemSku IS NOT NULL
      AND WarehouseCode IS NOT NULL
      AND SnapshotDate IS NOT NULL
      AND WeekEnding IS NOT NULL
      AND WeekEnding >= SnapshotDate
),
awd_ranked AS (
    SELECT
        sp.ItemSku,
        sp.WarehouseCode,
        sp.FactAsOfDate,
        sp.FutureWeekEndingDate,
        CAST(awd.AsOfDate AS DATE) AS AwdAsOfDate,
        CAST(awd.AwdQty AS DECIMAL(18,4)) AS AvgWeeklyDemand,
        ROW_NUMBER() OVER (
            PARTITION BY
                sp.ItemSku,
                sp.WarehouseCode,
                sp.FactAsOfDate,
                sp.FutureWeekEndingDate
            ORDER BY awd.AsOfDate DESC
        ) AS rn
    FROM sp_base sp
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
        ON awd.ItemSku = sp.ItemSku
       AND awd.WarehouseCode = sp.WarehouseCode
       AND awd.AsOfDate <= sp.FactAsOfDate
),
awd_latest AS (
    SELECT
        ItemSku,
        WarehouseCode,
        FactAsOfDate,
        FutureWeekEndingDate,
        AwdAsOfDate,
        AvgWeeklyDemand
    FROM awd_ranked
    WHERE rn = 1
),
afi_ranked AS (
    SELECT
        sp.ItemSku,
        sp.WarehouseCode,
        sp.FactAsOfDate,
        sp.FutureWeekEndingDate,
        CAST(afi.WeekEndingDate AS DATE) AS AfiStatusAsOfDate,
        CAST(afi.AFIStatus AS VARCHAR(20)) AS AFIStatus,
        ROW_NUMBER() OVER (
            PARTITION BY
                sp.ItemSku,
                sp.WarehouseCode,
                sp.FactAsOfDate,
                sp.FutureWeekEndingDate
            ORDER BY afi.WeekEndingDate DESC
        ) AS rn
    FROM sp_base sp
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AFIStatusSnapshotWeekly] afi
        ON afi.ItemSku = sp.ItemSku
       AND afi.WarehouseCode = sp.WarehouseCode
       AND afi.WeekEndingDate <= sp.FactAsOfDate
),
afi_latest AS (
    SELECT
        ItemSku,
        WarehouseCode,
        FactAsOfDate,
        FutureWeekEndingDate,
        AfiStatusAsOfDate,
        AFIStatus
    FROM afi_ranked
    WHERE rn = 1
),
last_invoice_ranked AS (
    SELECT
        sp.ItemSku,
        sp.WarehouseCode,
        sp.FactAsOfDate,
        sp.FutureWeekEndingDate,
        CAST(li.WeekEndingDate AS DATE) AS LastInvoiceAsOfDate,
        CAST(li.LastInvoiceDate AS DATE) AS LastInvoiceDate,
        ROW_NUMBER() OVER (
            PARTITION BY
                sp.ItemSku,
                sp.WarehouseCode,
                sp.FactAsOfDate,
                sp.FutureWeekEndingDate
            ORDER BY li.WeekEndingDate DESC
        ) AS rn
    FROM sp_base sp
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceWeekly] li
        ON li.ItemSku = sp.ItemSku
       AND li.WarehouseCode = sp.WarehouseCode
       AND li.WeekEndingDate <= sp.FactAsOfDate
),
last_invoice_latest AS (
    SELECT
        ItemSku,
        WarehouseCode,
        FactAsOfDate,
        FutureWeekEndingDate,
        LastInvoiceAsOfDate,
        LastInvoiceDate
    FROM last_invoice_ranked
    WHERE rn = 1
),
src AS (
    SELECT
        sp.ItemSku,
        sp.WarehouseCode,
        sp.FactAsOfDate,
        sp.SupplyPlanSnapshotDate,
        sp.FutureWeekEndingDate,
        sp.ProjectedInventoryQty,
        sp.SafetyStockTarget,
        sp.FirmDemandQty,
        sp.NetFcstQty,
        sp.FirmDemandQtyAtRisk,
        sp.NetFcstQtyAtRisk,
        sp.IsActiveItemWhIn7DNext,
        sp.IsActiveItemWhIn14DNext,
        sp.SupplyPlanSnapshotType,
        sp.LatestSupplyPlanSnapshotDate,
        awd.AwdAsOfDate,
        awd.AvgWeeklyDemand,
        afi.AfiStatusAsOfDate,
        afi.AFIStatus,
        li.LastInvoiceAsOfDate,
        li.LastInvoiceDate
    FROM sp_base sp
    LEFT JOIN awd_latest awd
        ON awd.ItemSku = sp.ItemSku
       AND awd.WarehouseCode = sp.WarehouseCode
       AND awd.FactAsOfDate = sp.FactAsOfDate
       AND awd.FutureWeekEndingDate = sp.FutureWeekEndingDate
    LEFT JOIN afi_latest afi
        ON afi.ItemSku = sp.ItemSku
       AND afi.WarehouseCode = sp.WarehouseCode
       AND afi.FactAsOfDate = sp.FactAsOfDate
       AND afi.FutureWeekEndingDate = sp.FutureWeekEndingDate
    LEFT JOIN last_invoice_latest li
        ON li.ItemSku = sp.ItemSku
       AND li.WarehouseCode = sp.WarehouseCode
       AND li.FactAsOfDate = sp.FactAsOfDate
       AND li.FutureWeekEndingDate = sp.FutureWeekEndingDate
),
classified AS (
    SELECT
        s.*,
        CASE
            WHEN UPPER(LTRIM(RTRIM(COALESCE(AFIStatus, '')))) IN ('D', 'R')
                 AND COALESCE(ProjectedInventoryQty, 0) = 0 THEN 'INACTIVE'
            WHEN LastInvoiceDate IS NOT NULL
                 AND LastInvoiceDate <= DATEADD(WEEK, -17, FactAsOfDate)
                 AND UPPER(LTRIM(RTRIM(COALESCE(AFIStatus, '')))) NOT IN ('N') THEN 'SLOB'
            WHEN COALESCE(ProjectedInventoryQty, 0) < 0.5 * COALESCE(SafetyStockTarget, 0)
                 AND COALESCE(SafetyStockTarget, 0) > 0 THEN 'BELOW_TARGET'
            WHEN AvgWeeklyDemand > 0
                 AND ProjectedInventoryQty > 104 * AvgWeeklyDemand THEN 'TB_INVENTORY'
            WHEN AvgWeeklyDemand > 0
                 AND ProjectedInventoryQty > 52 * AvgWeeklyDemand THEN 'AGGRESSIVE_EXCESS'
            WHEN AvgWeeklyDemand > 0
                 AND ProjectedInventoryQty > 17 * AvgWeeklyDemand THEN 'EXCESS'
            WHEN ProjectedInventoryQty > 1.5 * COALESCE(SafetyStockTarget, 0) THEN 'OVER_TARGET'
            WHEN ProjectedInventoryQty >= 0.5 * COALESCE(SafetyStockTarget, 0) THEN 'SWEET_SPOT'
            ELSE 'UNCLASSIFIED'
        END AS ProjectedSubStatus
    FROM src s
),
ranked AS (
    SELECT
        c.*,
        CASE ProjectedSubStatus
            WHEN 'INACTIVE' THEN 0
            WHEN 'SLOB' THEN 1
            WHEN 'BELOW_TARGET' THEN 2
            WHEN 'SWEET_SPOT' THEN 3
            WHEN 'OVER_TARGET' THEN 4
            WHEN 'EXCESS' THEN 5
            WHEN 'AGGRESSIVE_EXCESS' THEN 6
            WHEN 'TB_INVENTORY' THEN 7
            ELSE 99
        END AS ProjectedRanking
    FROM classified c
),
__bob_source AS (
SELECT
    ItemSku,
    WarehouseCode,
    FactAsOfDate,
    FutureWeekEndingDate,
    SupplyPlanSnapshotDate,
    AwdAsOfDate,
    AfiStatusAsOfDate,
    LastInvoiceAsOfDate,
    ProjectedSubStatus,
    ProjectedRanking,
    CASE MIN(ProjectedRanking) OVER (
        PARTITION BY ItemSku, WarehouseCode, FactAsOfDate, FutureWeekEndingDate
    )
        WHEN 0 THEN 'INACTIVE'
        WHEN 1 THEN 'SLOB'
        WHEN 2 THEN 'BELOW_TARGET'
        WHEN 3 THEN 'SWEET_SPOT'
        WHEN 4 THEN 'OVER_TARGET'
        WHEN 5 THEN 'EXCESS'
        WHEN 6 THEN 'AGGRESSIVE_EXCESS'
        WHEN 7 THEN 'TB_INVENTORY'
        ELSE 'UNCLASSIFIED'
    END AS ProjectedInventoryClassificationFinalStatus,
    AvgWeeklyDemand,
    SafetyStockTarget,
    ProjectedInventoryQty,
    FirmDemandQty,
    NetFcstQty,
    FirmDemandQtyAtRisk,
    NetFcstQtyAtRisk,
    IsActiveItemWhIn7DNext,
    IsActiveItemWhIn14DNext,
    AFIStatus,
    LastInvoiceDate,
    SupplyPlanSnapshotType,
    LatestSupplyPlanSnapshotDate,
    CAST(DATEDIFF(day, SupplyPlanSnapshotDate, FactAsOfDate) AS INT) AS SupplyPlanSnapshotLagDays,
    CAST(DATEDIFF(day, AwdAsOfDate, FactAsOfDate) AS INT) AS AwdLagDays,
    CAST(DATEDIFF(day, AfiStatusAsOfDate, FactAsOfDate) AS INT) AS AfiStatusLagDays,
    CAST(DATEDIFF(day, LastInvoiceAsOfDate, FactAsOfDate) AS INT) AS LastInvoiceLagDays
FROM ranked
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [FactAsOfDate] = src.[FactAsOfDate],
    [FutureWeekEndingDate] = src.[FutureWeekEndingDate],
    [SupplyPlanSnapshotDate] = src.[SupplyPlanSnapshotDate],
    [AwdAsOfDate] = src.[AwdAsOfDate],
    [AfiStatusAsOfDate] = src.[AfiStatusAsOfDate],
    [LastInvoiceAsOfDate] = src.[LastInvoiceAsOfDate],
    [ProjectedSubStatus] = src.[ProjectedSubStatus],
    [ProjectedRanking] = src.[ProjectedRanking],
    [ProjectedInventoryClassificationFinalStatus] = src.[ProjectedInventoryClassificationFinalStatus],
    [AvgWeeklyDemand] = src.[AvgWeeklyDemand],
    [SafetyStockTarget] = src.[SafetyStockTarget],
    [ProjectedInventoryQty] = src.[ProjectedInventoryQty],
    [FirmDemandQty] = src.[FirmDemandQty],
    [NetFcstQty] = src.[NetFcstQty],
    [FirmDemandQtyAtRisk] = src.[FirmDemandQtyAtRisk],
    [NetFcstQtyAtRisk] = src.[NetFcstQtyAtRisk],
    [IsActiveItemWhIn7DNext] = src.[IsActiveItemWhIn7DNext],
    [IsActiveItemWhIn14DNext] = src.[IsActiveItemWhIn14DNext],
    [AFIStatus] = src.[AFIStatus],
    [LastInvoiceDate] = src.[LastInvoiceDate],
    [SupplyPlanSnapshotType] = src.[SupplyPlanSnapshotType],
    [LatestSupplyPlanSnapshotDate] = src.[LatestSupplyPlanSnapshotDate],
    [SupplyPlanSnapshotLagDays] = src.[SupplyPlanSnapshotLagDays],
    [AwdLagDays] = src.[AwdLagDays],
    [AfiStatusLagDays] = src.[AfiStatusLagDays],
    [LastInvoiceLagDays] = src.[LastInvoiceLagDays]
FROM __bob_source AS src;
