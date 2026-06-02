
CREATE   VIEW InventoryHealth_DW.v_FactInventoryRiskForward AS
WITH _SupplyPlan AS (
    SELECT
        CAST(TRIM(spdItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(spdWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dtea AS DATE) AS SnapshotDate,
        CAST(spdWeekEnding AS DATE) AS WeekEndingDate,
        CAST(spdBeginingBalance AS DECIMAL(18,4)) AS BeginningBalanceQty,
        CAST(spdFirmDemands AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(spdNetForecast AS DECIMAL(18,4)) AS NetForecastQty,
        CAST(spdFirmPurchaseOrders AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
        CAST(spdPlannedPurchaseOrders AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
        CAST(spdOnOrderTransferIn AS DECIMAL(18,4)) AS OnOrderTransferInQty,
        CAST(spdShippableInventory AS DECIMAL(18,4)) AS ShippableInventoryQty,
        CAST(spdSafetyStock AS DECIMAL(18,4)) AS SafetyStockTargetQty,
        CAST(spdMonthsOfSupply AS DECIMAL(18,4)) AS MonthsOfSupply,
        CAST(CASE WHEN spdShippableInventory < 0 THEN ABS(CAST(spdShippableInventory AS DECIMAL(18,4))) ELSE 0 END AS DECIMAL(18,4)) AS SINegQty
    FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
    WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
      AND TRIM(spdItem) <> '' AND TRIM(spdWarehouse) <> ''
),
_AllocatedDemandCandidate AS (
    SELECT
        CAST(TRIM(d.ItemSKU) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(d.Warehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(c.FSCWeekLast AS DATE) AS PromiseWeekEndingDate,
        CAST(d.QuantityBackOrdered AS DECIMAL(18,4)) AS AllocatedDemandQty
    FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] c ON c.[Date] = d.PromiseDate
    WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
      AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
      AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
      AND d.PromiseDate IS NOT NULL
      AND TRIM(d.ItemSKU) <> '' AND TRIM(d.Warehouse) <> ''
),
alloc AS (
    SELECT ItemSku, WarehouseCode, PromiseWeekEndingDate, SUM(AllocatedDemandQty) AS AllocatedDemandQty
    FROM _AllocatedDemandCandidate
    GROUP BY ItemSku, WarehouseCode, PromiseWeekEndingDate
)
SELECT
    CAST(lp.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(lp.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(lp.WeekEndingDate AS DATE) AS WeekEndingDate,
    CAST(d.DateSK AS INT) AS DateKey,
    CAST(lp.BeginningBalanceQty AS DECIMAL(18,4)) AS BeginningBalanceQty,
    CAST(lp.FirmDemandQty AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(lp.NetForecastQty AS DECIMAL(18,4)) AS NetForecastQty,
    CAST(lp.FirmPurchaseOrderQty AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
    CAST(lp.PlannedPurchaseOrderQty AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
    CAST(lp.OnOrderTransferInQty AS DECIMAL(18,4)) AS OnOrderTransferInQty,
    CAST(lp.ShippableInventoryQty AS DECIMAL(18,4)) AS ShippableInventoryQty,
    CAST(lp.SafetyStockTargetQty AS DECIMAL(18,4)) AS SafetyStockTargetQty,
    CAST(lp.MonthsOfSupply AS DECIMAL(18,4)) AS MonthsOfSupply,
    CAST(lp.FirmDemandQty * (14.0/7.0) AS DECIMAL(18,4)) AS ExpectedDemand14DQty,
    CAST((lp.FirmPurchaseOrderQty + lp.OnOrderTransferInQty) * (14.0/7.0) AS DECIMAL(18,4)) AS Inbound14DQty,
    CAST(ISNULL(al.AllocatedDemandQty, 0) AS DECIMAL(18,4)) AS AllocatedDemandQty,
    CAST(0 AS DECIMAL(18,4)) AS ATPQty,
    CAST(0 AS BIT) AS ATPInStockFlag,
    CAST(CASE WHEN lp.ShippableInventoryQty > 0 THEN 1 ELSE 0 END AS BIT) AS ShippableInStockFlag,
    CAST(lp.SINegQty AS DECIMAL(18,4)) AS SINegQty,
    CAST(lp.SINegQty * ISNULL(dim.FOBArcPrice, 0) AS DECIMAL(18,4)) AS RevenueAtRiskValue,
    CAST(CASE WHEN lp.WeekEndingDate = (DATEADD(day, ((7 - DATEPART(weekday, SYSUTCDATETIME()) + 7) % 7) + 28, CAST(SYSUTCDATETIME() AS DATE))) THEN 1 ELSE 0 END AS BIT) AS WeekFourFlag,
    CAST(dim.FOBArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
    CAST(1 AS BIGINT) AS RuleVersionKey
FROM _SupplyPlan lp
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d ON d.[Date] = lp.WeekEndingDate
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimProduct] dim ON dim.ItemSKU = lp.ItemSku
LEFT JOIN alloc al ON al.ItemSku=lp.ItemSku AND al.WarehouseCode=lp.WarehouseCode AND al.PromiseWeekEndingDate=lp.WeekEndingDate
