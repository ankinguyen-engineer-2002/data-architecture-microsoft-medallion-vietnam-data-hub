/*============================================================
  10_verify.sql — Smoke tests + KPI sample queries
  Run after silver + gold refresh — verifies row counts, key joins, KPI samples.
============================================================*/

-- ── A. Silver smoke ─────────────────────────────────────
SELECT 'silver.ItemMaster'                AS TableName, COUNT(*) AS RowCount, COUNT(DISTINCT ItemSku) AS DistinctItem FROM silver.ItemMaster
UNION ALL
SELECT 'silver.Warehouse',                COUNT(*), COUNT(DISTINCT WarehouseCode)        FROM silver.Warehouse
UNION ALL
SELECT 'silver.Vendor',                   COUNT(*), COUNT(DISTINCT VendorNumber)         FROM silver.Vendor
UNION ALL
SELECT 'silver.CostCurrent',              COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.CostCurrent
UNION ALL
SELECT 'silver.InventoryCurrent',         COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.InventoryCurrent
UNION ALL
SELECT 'silver.InventorySnapshotWeekly',  COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.InventorySnapshotWeekly
UNION ALL
SELECT 'silver.ForecastSnapshotWeekly',   COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.ForecastSnapshotWeekly
UNION ALL
SELECT 'silver.ForecastCurrent',          COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.ForecastCurrent
UNION ALL
SELECT 'silver.SupplyPlan',               COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.SupplyPlan
UNION ALL
SELECT 'silver.SalesShipment',            COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.SalesShipment
UNION ALL
SELECT 'silver.PurchaseOrder',            COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.PurchaseOrder
UNION ALL
SELECT 'silver.ManufacturingOrder',       COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.ManufacturingOrder
UNION ALL
SELECT 'silver.LogilityItemStatus',       COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.LogilityItemStatus
UNION ALL
SELECT 'silver.HoldingTransfer',          COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.HoldingTransfer
UNION ALL
SELECT 'silver.AtpWeekEnding',            COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.AtpWeekEnding
UNION ALL
SELECT 'silver.MovementHistory',          COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.MovementHistory
UNION ALL
SELECT 'silver.AllocatedDemandCandidate', COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.AllocatedDemandCandidate
UNION ALL
SELECT 'silver.AwdHelper',                COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.AwdHelper
UNION ALL
SELECT 'silver.LastInvoiceHelper',        COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.LastInvoiceHelper
UNION ALL
SELECT 'silver.MovementFlagHelper',       COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.MovementFlagHelper
UNION ALL
SELECT 'silver.SafetyStockHelper',        COUNT(*), COUNT(DISTINCT ItemSku)              FROM silver.SafetyStockHelper
UNION ALL
SELECT 'silver.PurchaseOrderSnapshotDaily',         COUNT(*), COUNT(DISTINCT ItemSku)   FROM silver.PurchaseOrderSnapshotDaily
UNION ALL
SELECT 'silver.ManufacturingOrderSnapshotDaily',    COUNT(*), COUNT(DISTINCT ItemSku)   FROM silver.ManufacturingOrderSnapshotDaily
UNION ALL
SELECT 'silver.HoldingTransferSnapshotDaily',       COUNT(*), COUNT(DISTINCT ItemSku)   FROM silver.HoldingTransferSnapshotDaily
UNION ALL
SELECT 'silver.LogilityItemStatusSnapshotWeekly',   COUNT(*), COUNT(DISTINCT ItemSku)   FROM silver.LogilityItemStatusSnapshotWeekly;


-- ── B. Gold smoke ───────────────────────────────────────
SELECT 'gold.DimDate'                          AS TableName, COUNT(*) AS RowCount FROM gold.DimDate
UNION ALL SELECT 'gold.DimItem',               COUNT(*) FROM gold.DimItem
UNION ALL SELECT 'gold.DimWarehouse',          COUNT(*) FROM gold.DimWarehouse
UNION ALL SELECT 'gold.DimVendor',             COUNT(*) FROM gold.DimVendor
UNION ALL SELECT 'gold.DimRuleVersion',        COUNT(*) FROM gold.DimRuleVersion
UNION ALL SELECT 'gold.CogsRollingHelper',     COUNT(*) FROM gold.CogsRollingHelper
UNION ALL SELECT 'gold.FactInventoryHealthSnapshot', COUNT(*) FROM gold.FactInventoryHealthSnapshot
UNION ALL SELECT 'gold.FactInventoryRiskForward',    COUNT(*) FROM gold.FactInventoryRiskForward;


-- ── C. Fact composition by SnapshotType ─────────────────
SELECT SnapshotType,
       COUNT(*)                                  AS Rows,
       COUNT(DISTINCT ItemSku)                   AS DistinctItem,
       COUNT(DISTINCT WarehouseCode)             AS DistinctWh,
       SUM(CASE WHEN IsLatestSnapshot=1 THEN 1 ELSE 0 END) AS LatestRows,
       SUM(OnHandQty)                            AS TotalOnHand,
       SUM(InventoryValueAtCost)                 AS TotalInvCost
FROM gold.FactInventoryHealthSnapshot
GROUP BY SnapshotType;


-- ── D. KPI sample — current dashboard view ──────────────
SELECT TOP 20
    f.ItemSku, f.WarehouseCode, f.SnapshotDate,
    f.OnHandQty,
    f.TransferInInTransitQty,
    f.POOnOrderQty, f.POInTransitQty, f.MOOnOrderQty,
    f.OnOrderQty, f.InTransitQty, f.TotalInventoryCommitmentQty,  -- M2 FIX (2026-05-17): removed Python-style ':=' walrus syntax (not T-SQL)
    f.AwdQty, f.AwdSource, f.WeeksOfSupply,
    f.SafetyStockTargetQty, f.SafetyStockMultiple,
    f.InventoryClassification,
    f.StandardCost, f.FobArcPrice, f.Cubes,
    f.InventoryValueAtCost, f.InventoryValueAtRevenue, f.UsedStorageCube,
    f.LastInvoiceDate, f.LifecycleStatus,
    f.InactiveFlag, f.SlobFlag, f.NoMovementFlag, f.UnavailableFlag, f.OnHoldFlag,
    f.OnHoldQty, f.ObsoleteValue
FROM gold.FactInventoryHealthSnapshot f
WHERE f.IsLatestSnapshot = 1
ORDER BY f.InventoryValueAtCost DESC;


-- ── E. KPI sample — risk forward ────────────────────────
SELECT TOP 20
    r.ItemSku, r.WarehouseCode, r.WeekEndingDate,
    r.BeginningBalanceQty, r.FirmDemandQty, r.NetForecastQty,
    r.FirmPurchaseOrderQty, r.PlannedPurchaseOrderQty,
    r.ShippableInventoryQty, r.SafetyStockTargetQty, r.MonthsOfSupply,
    r.ExpectedDemand14DQty, r.Inbound14DQty,
    r.AllocatedDemandQty,
    r.ATPQty, r.ATPInStockFlag,
    r.ShippableInStockFlag,
    r.SINegQty, r.RevenueAtRiskValue,
    r.WeekFourFlag, r.FobArcPrice
FROM gold.FactInventoryRiskForward r
WHERE r.WeekFourFlag = 1
ORDER BY r.RevenueAtRiskValue DESC;


-- ── F. KPI aggregate examples ───────────────────────────
-- F.1 Total OnHand (current)
SELECT SUM(OnHandQty) AS Total_OnHandQty_Latest
FROM gold.FactInventoryHealthSnapshot
WHERE IsLatestSnapshot = 1;

-- F.2 Inventory Classification distribution (latest current)
SELECT InventoryClassification, COUNT(*) AS Rows, SUM(InventoryValueAtCost) AS TotalIVC
FROM gold.FactInventoryHealthSnapshot
WHERE IsLatestSnapshot = 1
GROUP BY InventoryClassification
ORDER BY TotalIVC DESC;

-- F.3 ATP In-Stock Rate (latest week)
SELECT
    1.0 * SUM(CASE WHEN ATPInStockFlag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS ATPInStockRate
FROM gold.FactInventoryRiskForward
WHERE WeekFourFlag = 1;

-- F.4 Shippable Inventory In-Stock Rate (latest week)
SELECT
    1.0 * SUM(CASE WHEN ShippableInStockFlag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS ShippableInStockRate
FROM gold.FactInventoryRiskForward
WHERE WeekFourFlag = 1;

-- F.5 Revenue at Risk (week-4)
SELECT SUM(RevenueAtRiskValue) AS Total_RevenueAtRisk_Week4
FROM gold.FactInventoryRiskForward
WHERE WeekFourFlag = 1;

-- F.6 Turns (latest month-end)
SELECT
    SUM(Cogs52M) / NULLIF(SUM(AverageInventoryValueAtCost), 0) AS InventoryTurns  -- M3: renamed Cogs52W → Cogs52M
FROM gold.FactInventoryHealthSnapshot f
JOIN gold.DimDate d ON d.CalendarDate = f.SnapshotDate
WHERE d.IsMonthEnd = 1
  AND f.SnapshotDate = (
    SELECT MAX(CalendarDate) FROM gold.DimDate WHERE IsMonthEnd = 1 AND CalendarDate <= CAST(SYSUTCDATETIME() AS DATE)
  );

-- F.7 SLOB ratio (% of inventory value flagged)
SELECT
    SUM(CASE WHEN SlobFlag=1 THEN InventoryValueAtCost ELSE 0 END)
        / NULLIF(SUM(InventoryValueAtCost), 0)  AS SlobRatio,
    SUM(ObsoleteValue) AS TotalObsoleteValue,
    SUM(InventoryValueAtCost) AS TotalIVC
FROM gold.FactInventoryHealthSnapshot
WHERE IsLatestSnapshot = 1;
