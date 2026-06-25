-- ============================================================
-- Gold Views — InventoryHealth_DW Serving Layer (project='inventory_health')
-- ============================================================
-- Target: SupplyChain_Gold_Warehouse (98e2a911-...) schema InventoryHealth_DW
-- Pattern: cross-DB 3-part name from Processing WH + Direct Lake-compatible CAST.
-- Cross-DB CTAS executed by pl_sc_gold pipeline (registry-driven) — Fabric WH
-- restriction: cross-DB CREATE TABLE cannot run from SP, so the pipeline bridges
-- via separate WH connections.
-- ============================================================
-- Track A fixes preserved:
--   H4 ORDER BY FiscalMonthYear (CogsRollingHelper)
--   H5 WeekFourFlag exact week (FactInventoryRiskForward, Robert sign-off pending)
--   M3 Cogs52W → Cogs52M rename (Robert sign-off pending re: keep 52M or rewrite weekly)
--   M4 SLOB NULL guard on LastInvoiceDate
-- ============================================================
-- 6 NEW views (Gold artifacts for inventory_health mart):
--   1. DimProduct                                    — shared via Shared_DW.DimProduct
--   2. DimWarehouse                                  — shared via Shared_DW.DimWarehouse
--   3. InventoryHealth_DW.v_DimVendor                — derived from ReferenceMaster_Enh.Vendor
--   4. InventoryHealth_DW.v_CogsRollingHelper        — 52M + 12M rolling COGS (H4 + M3)
--   5. InventoryHealth_DW.v_FactInventoryHealthSnapshot
--   6. InventoryHealth_DW.v_FactInventoryRiskForward (H5)
-- DROPPED 2026-05-22 (round 1): DimRuleVersion (over-engineering — Aric decision).
-- DROPPED 2026-05-22 (round 2): DimDate (duplication with shared DimCalendar).
--   Inventory_health TMDL now rebinds to Shared_DW.DimCalendar (single shared
--   date dim across both marts). Fact views already JOIN to that table for fiscal cols.
-- Shared date dim: see Shared_DW.v_DimCalendar (75 cols, conformed Gold schema).
-- DESIGN NOTE 2026-05-29: Product is now a conformed shared dimension. Inventory
-- semantic table is named DimProduct and binds to Shared_DW.DimProduct. Inventory
-- facts still expose ItemSku because their fact grain/source names are unchanged;
-- semantic relationships map Fact*.ItemSku -> DimProduct.ItemSKU.
-- ============================================================


-- ---- InventoryHealth_DW.v_DimDate ----  [DROPPED 2026-05-22]
-- Reason: duplicate of Shared_DW.DimCalendar (same source ReferenceMaster_Enh.Calendar).
-- Inv_health TMDL now binds directly to Shared_DW.DimCalendar via column-name
-- aliases (DateKey→DateSK, FiscalMonth→FSCMonthNum, etc.). Single shared date dim.
-- IsCurrentDate/IsCurrentWeek/IsMonthEnd flag cols deferred — compute report-level DAX if needed.
-- See git history pre-2026-05-22 for restoration if Phase 2 needs them as physical cols.

-- (Full v_DimDate CREATE VIEW body removed — recoverable from git pre-2026-05-22)


-- ---- InventoryHealth_DW.v_DimItem ----  [DEACTIVATED 2026-05-29]
-- Consolidated to Shared_DW.DimProduct. The shared superset preserves inventory
-- attributes (LifecycleStatus, PrimaryVendorNumber, vendor display name, Cubes,
-- FOBArcPrice, finished-goods and unavailable flags) while keeping Forecast-compatible
-- columns in one physical table.
-- Kept below as historical reference only; live registry marks InventoryHealth_DW.DimItem inactive.
CREATE VIEW InventoryHealth_DW.v_DimItem AS
SELECT
    CAST(p.ItemSKU                   AS VARCHAR(50))    AS ItemSku,
    CAST(p.ItemDescription           AS VARCHAR(200))   AS ItemDescription,
    CAST(p.ItemClassCode             AS VARCHAR(50))    AS ItemClassCode,
    CAST(p.ItemClassName             AS VARCHAR(100))   AS ItemClassName,
    CAST(p.CategoryName              AS VARCHAR(100))   AS CategoryName,
    CAST(p.CategoryCode              AS VARCHAR(50))    AS CategoryCode,
    CAST(p.CollectiveClass           AS VARCHAR(50))    AS CollectiveClass,
    CAST(p.SeriesNumber              AS VARCHAR(50))    AS SeriesNumber,
    CAST(p.SeriesName                AS VARCHAR(100))   AS SeriesName,
    CAST(p.AfiItemStatus             AS VARCHAR(10))    AS AfiItemStatus,
    CAST(p.LifecycleStatus           AS VARCHAR(20))    AS LifecycleStatus,
    CAST(p.PrimaryVendorNumber       AS VARCHAR(50))    AS PrimaryVendorNumber,
    CAST(p.PrimaryVendorDisplayName  AS VARCHAR(200))   AS PrimaryVendorName,
    CAST(p.Cubes                     AS DECIMAL(18,4))  AS Cubes,
    CAST(p.FOBArcPrice               AS DECIMAL(18,4))  AS FobArcPrice,
    CAST(p.IsFinishedGoodsItem       AS BIT)            AS IsFinishedGoodsItem,
    CAST(p.DiscontinuedFlag          AS BIT)            AS DiscontinuedFlag,
    CAST(p.NewItemFlag               AS BIT)            AS NewItemFlag,
    CAST(p.StatusCodeChangeDate      AS DATE)           AS StatusCodeChangeDate,
    CAST(p.UnavailableFlag           AS BIT)            AS UnavailableFlag
FROM [SupplyChain_Gold_Warehouse].[Shared_DW].[DimProduct] p

GO


-- ---- InventoryHealth_DW.v_DimWarehouse ----  [DROPPED 2026-05-29]
-- Consolidated to Shared_DW.DimWarehouse. The shared superset keeps all
-- inventory-specific warehouse flags plus forecast warehouse fields.


-- ---- InventoryHealth_DW.v_DimVendor ----
CREATE VIEW InventoryHealth_DW.v_DimVendor AS
SELECT
    CAST(v.VendorNumber  AS VARCHAR(50))   AS VendorNumber,
    CAST(v.VendorName    AS VARCHAR(200))  AS VendorName
FROM [SupplyChain_Processing_Warehouse].[ReferenceMaster_Enh].[Vendor] v
WHERE v.VendorNumber IS NOT NULL

GO



CREATE   VIEW InventoryHealth_DW.v_CogsRollingHelper AS
WITH _CostCurrent AS (
    SELECT ItemSku, CostId, StandardCost, ItemRevision
    FROM (
        SELECT
            TRIM(ITNBR)                          AS ItemSku,
            TRIM(STID)                           AS CostId,
            CAST(UCDEF AS DECIMAL(18,4))         AS StandardCost,
            CAST(ITRV  AS VARCHAR(20))           AS ItemRevision,
            ROW_NUMBER() OVER (PARTITION BY TRIM(STID), TRIM(ITNBR) ORDER BY ITRV DESC) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
          AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
monthly AS (
    SELECT
        CAST(TRIM(s.ItemSKU) AS VARCHAR(50)) AS ItemSku,
        s.WarehouseCode,
        d.FSCMonthYearNum AS FiscalMonthYear,
        SUM(s.QtyShipped * ISNULL(c.StandardCost, 0)) AS PeriodCogs,
        SUM(s.QtyShipped) AS PeriodShippedQty
    FROM [SupplyChain_Processing_Warehouse].[SalesHistory_Enh].[v_InvoiceDetailLineLevel] s
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
         ON d.[Date] = s.InvoiceDate
    LEFT JOIN _CostCurrent c
         ON c.ItemSku = s.ItemSKU
    GROUP BY s.ItemSKU, s.WarehouseCode, d.FSCMonthYearNum
)
SELECT
    CAST(ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(FiscalMonthYear   AS INT)           AS FiscalMonthYear,
    CAST(PeriodCogs        AS DECIMAL(18,4)) AS PeriodCogs,
    CAST(PeriodShippedQty  AS DECIMAL(18,4)) AS PeriodShippedQty,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4)) AS Cogs12M,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear
        ROWS BETWEEN 51 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4)) AS Cogs52M
FROM monthly

GO



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

GO



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

GO


-- ============================================================
-- END gold_views.sql
-- Total: 5 views in InventoryHealth_DW
-- ============================================================
