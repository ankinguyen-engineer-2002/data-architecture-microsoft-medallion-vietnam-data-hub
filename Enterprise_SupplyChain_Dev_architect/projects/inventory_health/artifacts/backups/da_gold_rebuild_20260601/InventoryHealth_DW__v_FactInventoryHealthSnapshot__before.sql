
CREATE   VIEW InventoryHealth_DW.v_FactInventoryHealthSnapshot AS
WITH _InventoryCurrent AS (
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS),1) = 'Z' AND RIGHT(TRIM(b.ITCLS),1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
_CostCurrent AS (
    SELECT ItemSku, CostId, StandardCost, ItemRevision
    FROM (
        SELECT
            TRIM(ITNBR) AS ItemSku, TRIM(STID) AS CostId,
            CAST(UCDEF AS DECIMAL(18,4)) AS StandardCost,
            CAST(ITRV AS VARCHAR(20)) AS ItemRevision,
            ROW_NUMBER() OVER (PARTITION BY TRIM(STID), TRIM(ITNBR) ORDER BY ITRV DESC) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
          AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
weekly_base AS (
    SELECT
        iw.SnapshotWeekEndingDate AS SnapshotDate,
        iw.ItemSku,
        iw.WarehouseCode,
        MAX(iw.OnHandQty) AS OnHandQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeekly] iw
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
         ON d.[Date] = iw.SnapshotWeekEndingDate
    WHERE iw.FiscalMonth = d.FSCMonthYearNum
    GROUP BY iw.SnapshotWeekEndingDate, iw.ItemSku, iw.WarehouseCode
),
base AS (
    SELECT
        CAST('Current' AS VARCHAR(10)) AS SnapshotType,
        ic.SnapshotDate,
        ic.ItemSku, ic.WarehouseCode,
        ic.OnHandQty,
        CAST('ItemMaster_AFI' AS VARCHAR(64)) AS SourceSystem,
        CAST('ITEMBL' AS VARCHAR(128)) AS SourceTable
    FROM _InventoryCurrent ic
    WHERE ic.SnapshotDate = CAST(SYSUTCDATETIME() AS DATE)
    UNION ALL
    SELECT
        CAST('Weekly' AS VARCHAR(10)),
        wb.SnapshotDate,
        wb.ItemSku, wb.WarehouseCode,
        wb.OnHandQty,
        CAST('SupplyChain_Enh_1' AS VARCHAR(64)),
        CAST('DemandInventorySnapshotWeekly' AS VARCHAR(128))
    FROM weekly_base wb
),
po_curr AS (
    SELECT ItemSku, WarehouseCode, SUM(POOnOrderQty) AS POOnOrderQty, SUM(POInTransitQty) AS POInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
    WHERE SnapshotDate = (SELECT MAX(SnapshotDate) FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily])
    GROUP BY ItemSku, WarehouseCode
),
po_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode, SUM(POOnOrderQty) AS POOnOrderQty, SUM(POInTransitQty) AS POInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
mo_curr AS (
    SELECT ItemSku, WarehouseCode, SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    WHERE SnapshotDate = (SELECT MAX(SnapshotDate) FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily])
    GROUP BY ItemSku, WarehouseCode
),
mo_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode, SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode, SUM(TransferQty) AS OnHoldQty, SUM(TransferCube) AS OnHoldCube
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[HoldingTransferSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_curr AS (
    SELECT ItemSku, WarehouseCode, SUM(TransferQty) AS OnHoldQty, SUM(TransferCube) AS OnHoldCube
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[HoldingTransferSnapshotDaily]
    WHERE SnapshotDate = (SELECT MAX(SnapshotDate) FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[HoldingTransferSnapshotDaily])
    GROUP BY ItemSku, WarehouseCode
),
ti_curr AS (
    SELECT
        TRIM(b.ITNBR) AS ItemSku,
        TRIM(w.WarehouseCode) AS WarehouseCode,
        SUM(CAST(b.MOHTQ AS DECIMAL(18,4))) AS TransferInInTransitQty
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimWarehouse] w
         ON TRIM(w.IntransitWarehouseCode) = TRIM(b.HOUSE)
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND TRIM(b.HOUSE) IN ('A','B','L','N','T','F','E','W','M','V','S')
      AND TRIM(w.WarehouseCode) IN ('1','5','15','17','28','335','42','ECR','3','12','16','19')
    GROUP BY TRIM(b.ITNBR), TRIM(w.WarehouseCode)
),
ivc_monthly AS (
    SELECT DISTINCT
        b.ItemSku, b.WarehouseCode, d.FSCMonthYearNum AS FiscalMonthYear,
        ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS InventoryValueAtCost
    FROM base b
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
         ON d.[Date] = b.SnapshotDate
    LEFT JOIN _CostCurrent cc ON cc.ItemSku = b.ItemSku
    WHERE d.[Date] = (
        SELECT MAX(d2.[Date])
        FROM [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d2
        WHERE d2.FSCMonthYearNum = d.FSCMonthYearNum
    )
),
avg_ivc12 AS (
    SELECT ItemSku, WarehouseCode, FiscalMonthYear,
        AVG(InventoryValueAtCost) OVER (PARTITION BY ItemSku, WarehouseCode ORDER BY FiscalMonthYear ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS AvgInvValue12M
    FROM ivc_monthly
)
SELECT
    CAST(b.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(b.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(b.SnapshotDate AS DATE) AS SnapshotDate,
    CAST(b.SnapshotType AS VARCHAR(10)) AS SnapshotType,
    CAST(d.FSCWeekLast AS DATE) AS WeekEndingDate,
    CAST(d.DateSK AS INT) AS DateKey,
    CAST(d.FSCMonthNum AS INT) AS FiscalMonth,
    CAST(d.FSCMonthYearNum AS INT) AS FiscalMonthYear,
    CAST(CASE WHEN b.SnapshotType = 'Current' THEN 1 ELSE 0 END AS BIT) AS IsLatestSnapshot,
    CAST(b.SourceSystem AS VARCHAR(64)) AS SourceSystem,
    CAST(b.SourceTable AS VARCHAR(128)) AS SourceTable,
    CAST(1 AS BIGINT) AS RuleVersionKey,
    CAST(ISNULL(b.OnHandQty, 0) AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ISNULL(ti.TransferInInTransitQty, 0) AS DECIMAL(18,4)) AS TransferInInTransitQty,
    CAST(ISNULL(b.OnHandQty, 0) + ISNULL(ti.TransferInInTransitQty, 0) AS DECIMAL(18,4)) AS TotalAvailableQty,
    CAST(CASE WHEN b.SnapshotType = 'Current' THEN ISNULL(pc.POInTransitQty, 0) ELSE ISNULL(ps.POInTransitQty, 0) END AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(CASE WHEN b.SnapshotType = 'Current' THEN ISNULL(pc.POOnOrderQty, 0) ELSE ISNULL(ps.POOnOrderQty, 0) END AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN b.SnapshotType = 'Current' THEN ISNULL(mc.MOOnOrderQty, 0) ELSE ISNULL(ms.MOOnOrderQty, 0) END AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(ISNULL(ti.TransferInInTransitQty,0) + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POInTransitQty,0) ELSE ISNULL(ps.POInTransitQty,0) END AS DECIMAL(18,4)) AS InTransitQty,
    CAST(CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) + ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) + ISNULL(ms.MOOnOrderQty,0) END AS DECIMAL(18,4)) AS OnOrderQty,
    CAST(awd.ThreeMoForecastQty AS DECIMAL(18,4)) AS ThreeMoForecastQty,
    CAST(awd.ThreeMoDependentDemandQty AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty,
    CAST(awd.DailyFcstQty AS DECIMAL(18,4)) AS DailyFcstQty,
    CAST(awd.DependentDemandDailyQty AS DECIMAL(18,4)) AS DependentDemandDailyQty,
    CAST(awd.TotalDemandDailyQty AS DECIMAL(18,4)) AS TotalDemandDailyQty,
    CAST(awd.AwdDailyQty AS DECIMAL(18,4)) AS AwdDailyQty,
    CAST(awd.AwdQty AS DECIMAL(18,4)) AS AwdQty,
    CAST(awd.AwdSource AS VARCHAR(20)) AS AwdSource,
    CAST(CASE WHEN awd.AwdQty > 0 THEN b.OnHandQty / awd.AwdQty END AS DECIMAL(18,4)) AS WeeksOfSupply,
    CAST(CASE WHEN awd.AwdDailyQty > 0 THEN b.OnHandQty / awd.AwdDailyQty END AS DECIMAL(18,4)) AS DaysOfSupply,
    CAST(ss.SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTargetQty,
    CAST(ss.SafetyStockSource AS VARCHAR(30)) AS SafetyStockSource,
    CAST(CASE WHEN ss.SafetyStockTarget > 0 THEN b.OnHandQty / ss.SafetyStockTarget END AS DECIMAL(18,4)) AS SafetyStockMultiple,
    CAST(CASE
        WHEN dim.AfiItemStatus IN ('D','R')
         AND (ISNULL(b.OnHandQty,0) + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0 THEN 'Inactive'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 0.5 * ss.SafetyStockTarget THEN 'Below Target'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 1.5 * ss.SafetyStockTarget THEN 'Sweet Spot'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 17  * awd.AwdQty THEN 'Over Target'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 52  * awd.AwdQty THEN 'Excess'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 104 * awd.AwdQty THEN 'Aggressive Excess'
        ELSE 'TB Inventory'
    END AS VARCHAR(30)) AS InventoryClassification,
    CAST(cc.StandardCost AS DECIMAL(18,4)) AS StandardCost,
    CAST(dim.FOBArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
    CAST(dim.Cubes AS DECIMAL(18,4)) AS Cubes,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS DECIMAL(18,4)) AS InventoryValueAtCost,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.FOBArcPrice,0) AS DECIMAL(18,4)) AS InventoryValueAtRevenue,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.Cubes,0) AS DECIMAL(18,4)) AS UsedStorageCube,
    CAST(coh.PeriodCogs AS DECIMAL(18,4)) AS PeriodCogs,
    CAST(coh.Cogs52M AS DECIMAL(18,4)) AS Cogs52M,
    CAST(coh.Cogs12M AS DECIMAL(18,4)) AS Cogs12M,
    CAST(aiv.AvgInvValue12M AS DECIMAL(18,4)) AS AverageInventoryValueAtCost,
    CAST(lh.LastInvoiceDate AS DATE) AS LastInvoiceDate,
    CAST(dim.LifecycleStatus AS VARCHAR(20)) AS LifecycleStatus,
    CAST(CASE WHEN dim.AfiItemStatus IN ('D','R') AND (ISNULL(b.OnHandQty,0) + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0 THEN 1 ELSE 0 END AS BIT) AS InactiveFlag,
    CAST(CASE WHEN dim.AfiItemStatus <> 'N' AND lh.LastInvoiceDate IS NOT NULL AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate) THEN 1 ELSE 0 END AS BIT) AS SlobFlag,
    CAST(CASE WHEN ISNULL(mf.HasMovementLast17W, 0) = 0 THEN 1 ELSE 0 END AS BIT) AS NoMovementFlag,
    CAST(dim.UnavailableFlag AS BIT) AS UnavailableFlag,
    CAST(CASE WHEN b.SnapshotType='Current' THEN ISNULL(hc.OnHoldQty, 0) ELSE ISNULL(hs.OnHoldQty, 0) END AS DECIMAL(18,4)) AS OnHoldQty,
    CAST(CASE WHEN (CASE WHEN b.SnapshotType='Current' THEN ISNULL(hc.OnHoldQty,0) ELSE ISNULL(hs.OnHoldQty,0) END) > 0 THEN 1 ELSE 0 END AS BIT) AS OnHoldFlag,
    CAST(CASE WHEN dim.AfiItemStatus <> 'N' AND lh.LastInvoiceDate IS NOT NULL AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate) THEN ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) ELSE 0 END AS DECIMAL(18,4)) AS ObsoleteValue
FROM base b
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d ON d.[Date] = b.SnapshotDate
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimProduct] dim ON dim.ItemSKU = b.ItemSku
LEFT JOIN _CostCurrent cc ON cc.ItemSku = b.ItemSku
LEFT JOIN ti_curr ti ON ti.ItemSku=b.ItemSku AND ti.WarehouseCode=b.WarehouseCode
LEFT JOIN po_curr pc ON pc.ItemSku=b.ItemSku AND pc.WarehouseCode=b.WarehouseCode
LEFT JOIN po_snap ps ON ps.ItemSku=b.ItemSku AND ps.WarehouseCode=b.WarehouseCode AND ps.SnapshotDate=b.SnapshotDate
LEFT JOIN mo_curr mc ON mc.ItemSku=b.ItemSku AND mc.WarehouseCode=b.WarehouseCode
LEFT JOIN mo_snap ms ON ms.ItemSku=b.ItemSku AND ms.WarehouseCode=b.WarehouseCode AND ms.SnapshotDate=b.SnapshotDate
LEFT JOIN hold_curr hc ON hc.ItemSku=b.ItemSku AND hc.WarehouseCode=b.WarehouseCode
LEFT JOIN hold_snap hs ON hs.ItemSku=b.ItemSku AND hs.WarehouseCode=b.WarehouseCode AND hs.SnapshotDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd ON awd.ItemSku=b.ItemSku AND awd.WarehouseCode=b.WarehouseCode AND awd.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceHelper] lh ON lh.ItemSku=b.ItemSku AND lh.WarehouseCode=b.WarehouseCode AND lh.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[MovementFlagHelper] mf ON mf.ItemSku=b.ItemSku AND mf.WarehouseCode=b.WarehouseCode AND mf.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss ON ss.ItemSku=b.ItemSku AND ss.WarehouseCode=b.WarehouseCode AND ss.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Gold_Warehouse].[InventoryHealth_DW].[CogsRollingHelper] coh ON coh.ItemSku=b.ItemSku AND coh.WarehouseCode=b.WarehouseCode AND coh.FiscalMonthYear=d.FSCMonthYearNum
LEFT JOIN avg_ivc12 aiv ON aiv.ItemSku=b.ItemSku AND aiv.WarehouseCode=b.WarehouseCode AND aiv.FiscalMonthYear=d.FSCMonthYearNum
