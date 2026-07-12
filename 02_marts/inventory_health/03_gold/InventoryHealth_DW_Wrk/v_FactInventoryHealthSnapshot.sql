-- InventoryHealth_DW_Wrk.v_FactInventoryHealthSnapshot
-- InventoryHealth_DW_Wrk.v_FactInventoryHealthSnapshot
CREATE           VIEW [InventoryHealth_DW_Wrk].[v_FactInventoryHealthSnapshot] AS
WITH inv_base AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotWeekEndingDate,
        OnHandQty,
        MakeBuyCode,
        PrimaryVendorName,
        SecondaryVendorName,
        ReplenishmentLeadTime,
        SnapshotType
    FROM (
        SELECT
            ItemSku,
            WarehouseCode,
            SnapshotWeekEndingDate,
            OnHandQty,
            MakeBuyCode,
            PrimaryVendorName,
            SecondaryVendorName,
            ReplenishmentLeadTime, 
            SnapshotType, 
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                ORDER BY FiscalMonthDate ASC
            ) AS rn
        FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeekly]
        WHERE ItemSku IS NOT NULL
          AND WarehouseCode IS NOT NULL
          AND SnapshotWeekEndingDate IS NOT NULL
    ) ranked_inv
    WHERE rn = 1 
),
base AS (
    SELECT
        CAST(inv.ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(inv.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(inv.SnapshotWeekEndingDate AS DATE) AS SnapshotWeekEndingDate,
        CAST(inv.OnHandQty AS DECIMAL(18,4)) AS OnHandsQty,
        CAST(inv.MakeBuyCode AS VARCHAR(10)) AS MakeBuyCode,
        CAST(inv.PrimaryVendorName AS VARCHAR(200)) AS PrimaryVendorName,
        CAST(inv.SecondaryVendorName AS VARCHAR(200)) AS SecondaryVendorName,
        CAST(inv.ReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime
    FROM inv_base inv
    Where SnapshotType = 'WEEKLY' or SnapshotType = 'WEEKLY_AND_LATEST'
),
po AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(SnapshotDate AS DATE) AS SnapshotWeekEndingDate,
        SUM(COALESCE(POOnOrderQty, 0)) AS POOnOrderQty,
        SUM(COALESCE(POInTransitQty, 0)) AS POInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotHistorical]
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotDate
),
mo AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(SnapshotDate AS DATE) AS SnapshotWeekEndingDate,
        SUM(COALESCE(RemainingMOQty, 0)) AS RemainingMOQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotDate
),
transfer_in AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(WeekEndingDate AS DATE) AS WeekEndingDate,
        SUM(COALESCE(InTransitQty, 0)) AS TransferInInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ItemBalanceHistorical_WithInTransit]
    GROUP BY
        ItemSku,
        WarehouseCode,
        WeekEndingDate
),
supply_plan AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(WeekEnding AS DATE) AS WeekEnding,
        MAX(CAST(IsActiveItemWhIn7DNext AS INT)) AS IsActiveItemWhIn7DNext,
        MAX(CAST(IsActiveItemWhIn14DNext AS INT)) AS IsActiveItemWhIn14DNext,
        SUM(COALESCE(SIQty, 0)) AS SIQty,
        SUM(COALESCE(SINegQty, 0)) AS SINegQty,
        SUM(COALESCE(FirmDemandQtyAtRisk, 0)) AS FirmDemandQtyAtRisk,
        SUM(COALESCE(NetFcstQtyAtRisk, 0)) AS NetFcstQtyAtRisk,
        SUM(COALESCE(FirmDemandQty, 0)) AS FirmDemandQty,
        SUM(COALESCE(NetFcstQty, 0)) AS NetFcstQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SupplyPlanDetail]
    Where SnapshotType = 'WEEKLY' or SnapshotType = 'WEEKLY_AND_LATEST'
    GROUP BY
        ItemSku,
        WarehouseCode,
        WeekEnding
),
atp AS (
    SELECT
        CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
        CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
        CAST(SnapshotWeekEndingDate AS DATE) AS SnapshotWeekEndingDate,
        SUM(COALESCE(AtpQty, 0)) AS AtpQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AtpWeekEnding]
    Where SnapshotType = 'WEEKLY' or SnapshotType = 'WEEKLY_AND_LATEST'
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotWeekEndingDate
),
joined AS (
    SELECT
        b.ItemSku,
        b.WarehouseCode,
        b.SnapshotWeekEndingDate,
        b.OnHandsQty,
        b.MakeBuyCode,
        b.PrimaryVendorName,
        b.SecondaryVendorName,
        b.ReplenishmentLeadTime,
        COALESCE(po.POOnOrderQty, 0) AS POOnOrderQty,
        COALESCE(mo.RemainingMOQty, 0) AS MOOnOrderQty,
        COALESCE(ti.TransferInInTransitQty, 0) AS TransferInInTransitQty,
        COALESCE(po.POInTransitQty, 0) AS POInTransitQty,
        awd.AwdQty AS AwdQty,
        sp.IsActiveItemWhIn7DNext,
        sp.IsActiveItemWhIn14DNext,
        sp.SIQty,
        sp.SINegQty,
        sp.FirmDemandQtyAtRisk,
        sp.NetFcstQtyAtRisk,
        sp.FirmDemandQty,
        sp.NetFcstQty,
        atp.AtpQty,
        cls.[InventoryClassification Final Status],
        qty.[Qty by InventoryClassification (Inactive)] AS QtyInactive,
        qty.[Qty by InventoryClassification (SLOB)] AS QtySLOB,
        qty.[Qty by InventoryClassification (Below Target)] AS QtyBelowTarget,
        qty.[Qty by InventoryClassification (SweetSpot)] AS QtySweetSpot,
        qty.[Qty by InventoryClassification (OverTarget)] AS QtyOverTarget,
        qty.[Qty by InventoryClassification (Excess)] AS QtyExcess,
        qty.[Qty by InventoryClassification (AE)] AS QtyAE,
        qty.[Qty by InventoryClassification (TB Inventory)] AS QtyTBInventory,
        ss.SafetyStockTarget,
        cogs.COGS52W,
        cogs.StandardCost,
        dp.FOBArcPrice AS FobArcPrice,
        dp.Cubes,
        li.LastInvoiceDate,
        li.WeeksSinceLastInvoice,
        afi.AFIStatus,
        outage.WeightedSINegScore,
        outage.OutageClass
    FROM base b
    LEFT JOIN po
        ON po.ItemSku = b.ItemSku
       AND po.WarehouseCode = b.WarehouseCode
       AND po.SnapshotWeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN mo
        ON mo.ItemSku = b.ItemSku
       AND mo.WarehouseCode = b.WarehouseCode
       AND mo.SnapshotWeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN transfer_in ti
        ON ti.ItemSku = b.ItemSku
       AND ti.WarehouseCode = b.WarehouseCode
       AND ti.WeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
        ON awd.ItemSku = b.ItemSku
       AND awd.WarehouseCode = b.WarehouseCode
       AND awd.AsOfDate = b.SnapshotWeekEndingDate
    LEFT JOIN supply_plan sp
        ON sp.ItemSku = b.ItemSku
       AND sp.WarehouseCode = b.WarehouseCode
       AND sp.WeekEnding = b.SnapshotWeekEndingDate
    LEFT JOIN atp
        ON atp.ItemSku = b.ItemSku
       AND atp.WarehouseCode = b.WarehouseCode
       AND atp.SnapshotWeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN [InventoryHealth_DW].[InventoryHealthSubStatusWeekly] cls
        ON cls.ItemSku = b.ItemSku
       AND cls.WarehouseCode = b.WarehouseCode
       AND cls.SnapshotWeekEnding = b.SnapshotWeekEndingDate
    LEFT JOIN [InventoryHealth_DW].[InventoryClassificationQtyWeekly] qty
        ON qty.Item = b.ItemSku
       AND qty.WH = b.WarehouseCode
       AND qty.SnapshotWeekEnding = b.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss
        ON ss.ItemSku = b.ItemSku
       AND ss.WarehouseCode = b.WarehouseCode
       AND ss.AsOfDate = b.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[Cogs52WWeekly] cogs
        ON cogs.ItemSku = b.ItemSku
       AND cogs.WarehouseCode = b.WarehouseCode
       AND cogs.WeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN [Shared_DW].[DimProduct] dp
        ON dp.ItemSKU = b.ItemSku
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceWeekly] li
        ON li.ItemSku = b.ItemSku
       AND li.WarehouseCode = b.WarehouseCode
       AND li.WeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AFIStatusSnapshotWeekly] afi
        ON afi.ItemSku = b.ItemSku
       AND afi.WarehouseCode = b.WarehouseCode
       AND afi.WeekEndingDate = b.SnapshotWeekEndingDate
    LEFT JOIN [InventoryHealth_DW_Wrk].[v_SupplyPlanOutageClassHelper] outage
        ON outage.ItemSku = b.ItemSku
       AND outage.WarehouseCode = b.WarehouseCode
       AND outage.WeekEnding = b.SnapshotWeekEndingDate
)
SELECT
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(SnapshotWeekEndingDate AS DATE) AS SnapshotWeekEndingDate,
    CAST(OnHandsQty AS DECIMAL(18,4)) AS OnHandQty,
    CAST(COALESCE(OnHandsQty, 0) * COALESCE(StandardCost, 0) AS DECIMAL(18,4)) AS [OnHandValue],
    CAST(COALESCE(POOnOrderQty, 0) + COALESCE(MOOnOrderQty, 0) AS DECIMAL(18,4)) AS [OnOrderQty],
    CAST(POOnOrderQty AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(MOOnOrderQty AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(COALESCE(TransferInInTransitQty, 0) + COALESCE(POInTransitQty, 0) AS DECIMAL(18,4)) AS [InTransitQty],
    CAST(TransferInInTransitQty AS DECIMAL(18,4)) AS TransferInInTransitQty,
    CAST(POInTransitQty AS DECIMAL(18,4)) AS POInTransitQty,
    CAST((COALESCE(POOnOrderQty, 0) + COALESCE(MOOnOrderQty, 0)) * COALESCE(StandardCost, 0) AS DECIMAL(18,4)) AS [OnOrderValue],
    CAST((COALESCE(TransferInInTransitQty, 0) + COALESCE(POInTransitQty, 0)) * COALESCE(StandardCost, 0) AS DECIMAL(18,4)) AS [InTransitValue],
    CAST(AwdQty AS DECIMAL(18,4)) AS AwdQty,
    CAST(NULL AS DECIMAL(18,4)) AS [OnHoldRatio],
    CAST(IsActiveItemWhIn7DNext AS INT) AS IsActiveItemWhIn7DNext,
    CAST(IsActiveItemWhIn14DNext AS INT) AS IsActiveItemWhIn14DNext,
    CAST(AtpQty AS DECIMAL(18,4)) AS [ATPQty],
    CAST(SIQty AS DECIMAL(18,4)) AS SIQty,
    CAST(CASE
            WHEN COALESCE(SIQty, 0) < 0 THEN COALESCE(SINegQty, ABS(SIQty)) * COALESCE(FobArcPrice, 0)
            ELSE 0
         END AS DECIMAL(18,4)) AS [ShortageValue],
    CAST([InventoryClassification Final Status] AS VARCHAR(30)) AS [InventoryClassificationFinalStatus],
    CAST(QtyInactive AS DECIMAL(18,4)) AS [QtyByInventoryClassification(InActive)],
    CAST(QtySLOB AS DECIMAL(18,4)) AS [QtyByInventoryClassification(SLOB)],
    CAST(QtyBelowTarget AS DECIMAL(18,4)) AS [QtyByInventoryClassification(BelowTarget)],
    CAST(QtySweetSpot AS DECIMAL(18,4)) AS [QtyByInventoryClassification(SweetSpot)],
    CAST(QtyOverTarget AS DECIMAL(18,4)) AS [QtyByInventoryClassification(OverTarget)],
    CAST(QtyExcess AS DECIMAL(18,4)) AS [QtyByInventoryClassification(Excess)],
    CAST(QtyAE AS DECIMAL(18,4)) AS [QtyByInventoryClassification(AE)],
    CAST(QtyTBInventory AS DECIMAL(18,4)) AS [QtyByInventoryClassification(TBInventory)],
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(FirmDemandQtyAtRisk AS DECIMAL(18,4)) AS FirmDemandQtyAtRisk,
    CAST(NetFcstQtyAtRisk AS DECIMAL(18,4)) AS NetFcstQtyAtRisk,
    CAST(FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(NetFcstQty AS DECIMAL(18,4)) AS NetFcstQty,
    CAST(COGS52W AS DECIMAL(18,4)) AS COGS52W,
    CAST(CASE
            WHEN COALESCE(SIQty, 0) < 0 THEN 'SHORTAGE'
            WHEN [InventoryClassification Final Status] IN (
                    'TB_INVENTORY',
                    'AGGRESSIVE_EXCESS',
                    'EXCESS',
                    'OVER_TARGET',
                    'SLOB',
                    'INACTIVE'
                 ) THEN 'SURPLUS'
            WHEN [InventoryClassification Final Status] IN (
                    'SWEET_SPOT',
                    'BELOW_TARGET'
                 ) THEN 'IN_STOCK'
            ELSE 'UNCLASSIFIED'
         END AS VARCHAR(30)) AS [IsShortage/Surplus/InStock],
    CAST(CASE
            WHEN COALESCE(SIQty, 0) < 0 THEN ABS(COALESCE(SIQty, 0))
            WHEN [InventoryClassification Final Status] IN (
                    'TB_INVENTORY',
                    'AGGRESSIVE_EXCESS',
                    'EXCESS',
                    'OVER_TARGET',
                    'SLOB',
                    'INACTIVE',
                    'SWEET_SPOT',
                    'BELOW_TARGET'
                 ) THEN COALESCE(OnHandsQty, 0) 
            ELSE 0
         END AS DECIMAL(18,4)) AS [Shortage/SurplusQty],
    CAST(MakeBuyCode AS VARCHAR(10)) AS MakeBuyCode,
    CAST(PrimaryVendorName AS VARCHAR(200)) AS PrimaryVendorName,
    CAST(SecondaryVendorName AS VARCHAR(200)) AS SecondaryVendorName,
    CAST(ReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime,
    CAST(COALESCE(OnHandsQty, 0) * COALESCE(Cubes, 0) AS DECIMAL(18,4)) AS UsedStorageCube,
    CAST(StandardCost AS DECIMAL(18,4)) AS StandardCost,
    CAST(FobArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
    CAST(Cubes AS DECIMAL(18,4)) AS Cubes,
    CAST(LastInvoiceDate AS DATE) AS LastInvoiceDate,
    CAST(WeeksSinceLastInvoice AS INT) AS InventoryAgeWeeks,
    CAST(NULL AS DECIMAL(18,4)) AS [AgingBucket<3MQty],
    CAST(NULL AS DECIMAL(18,4)) AS [AgingBucket<6MQty],
    CAST(NULL AS DECIMAL(18,4)) AS [AgingBucket<12MQty],
    CAST(NULL AS DECIMAL(18,4)) AS [AgingBucket>12MQty],
    CAST(AFIStatus AS VARCHAR(20)) AS AFIStatus, 
    CAST(WeightedSINegScore AS DECIMAL(18,4)) AS WeightedSINegScore,
    CAST(OutageClass AS VARCHAR(30)) AS OutageClass
FROM joined;
