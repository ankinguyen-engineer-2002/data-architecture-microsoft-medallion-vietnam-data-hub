-- ---- InventoryHealth_DW.v_FactInventoryHealthSnapshot ----
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, SnapshotType)
-- SnapshotType ∈ ('Current', 'Weekly').
-- v10 conversion: deliverable's 2-pass procedure (CTAS Pass 1 + UPDATE Pass 2) collapsed
-- into a SINGLE view with CTEs handling rolling COGS + AvgInv12M inline (Meta.usp_GenericLoad
-- does CTAS only — no UPDATE). Logic identical to deliverable's gold.usp_Build_FactInventoryHealthSnapshot.
-- M4 FIX (2026-05-17): SLOB + ObsoleteValue require LastInvoiceDate IS NOT NULL guard.
CREATE VIEW InventoryHealth_DW.v_FactInventoryHealthSnapshot AS
WITH _WarehouseExt AS (
    SELECT
        CAST(TRIM(w.wmaWarehouse)                  AS VARCHAR(50))   AS WarehouseCode,
        CAST(TRIM(w.wmaWarehouse)                  AS VARCHAR(50))   AS WarehouseName,
        CAST(w.wmaWarehouseType                    AS VARCHAR(100))  AS WarehouseType,
        CAST(w.wmaWarehouseOrderGroup              AS VARCHAR(50))   AS WarehouseOrderGroup,
        CAST(w.wmaWarehouseSourceId                AS VARCHAR(50))   AS WarehouseSourceId,
        CAST(w.wmaSellableWarehouse                AS BIT)           AS SellableWarehouseFlag,
        CAST(w.wmaControlled                       AS BIT)           AS ControlledFlag,
        CAST(w.wmaWhereMade                        AS VARCHAR(50))   AS WhereMadeCode,
        CAST(w.wmaManufacturingSite                AS VARCHAR(50))   AS ManufacturingSite,
        CAST(TRIM(w.wmaIntransitWarehouse)         AS VARCHAR(50))   AS IntransitWarehouseCode,
        CAST(CASE WHEN TRIM(w.wmaWarehouse) IN ('1','5','15','17','28','335','ECR')
                  THEN 1 ELSE 0 END AS BIT)                          AS IsFinishedGoodsWarehouse,
        CAST(CASE WHEN TRIM(w.wmaWarehouse) NOT IN ('1','5','15','17','28','335','ECR')
                  THEN 1 ELSE 0 END AS BIT)                          AS IsManufacturingWarehouse,
        CAST(NULL                                  AS DECIMAL(18,4)) AS TotalAvailableWarehouseCube
    FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster] w
    WHERE w.wmaWarehouse IS NOT NULL AND TRIM(w.wmaWarehouse) <> ''
),
_HoldingTransfer AS (
    SELECT TransferNumber, ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube, HeaderStatus, CancelFlag, ShipDateKey, DueDateKey
    FROM (
        SELECT
            TRIM(d.DTFRNO) AS TransferNumber, TRIM(d.DITNBR) AS ItemSku, TRIM(h.HFHOUS) AS WarehouseCode,
            CAST(d.DTFRQT AS DECIMAL(18,4)) AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4)) AS ShippedQty,
            CAST(d.DCUBES AS DECIMAL(18,4)) AS TransferCube,
            TRIM(h.HSTATS) AS HeaderStatus, TRIM(h.HCANCL) AS CancelFlag,
            CAST(h.HSHDTE AS INT) AS ShipDateKey, CAST(h.HDLDTE AS INT) AS DueDateKey,
            ROW_NUMBER() OVER (PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR) ORDER BY h.HDLDTE DESC) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
_InventoryCurrent AS (
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
_ManufacturingOrder AS (
    SELECT
        CAST(TRIM(ORDNO)  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END AS DECIMAL(18,4))  AS MOOnOrderQty,
        CAST(ODUDT        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
),
_ItemMasterExt AS (
    -- 2026-05-29: Shared product contract; single source for item lifecycle, price, cube, vendor, and unavailable flags.
    SELECT
        CAST(ItemSKU AS VARCHAR(50)) AS ItemSku,
        CAST(ItemDescription AS VARCHAR(200)) AS ItemDescription,
        CAST(ItemClassCode AS VARCHAR(50)) AS ItemClassCode,
        CAST(ItemClassName AS VARCHAR(100)) AS ItemClassName,
        CAST(CategoryName AS VARCHAR(100)) AS CategoryName,
        CAST(CategoryCode AS VARCHAR(50)) AS CategoryCode,
        CAST(CollectiveClass AS VARCHAR(50)) AS CollectiveClass,
        CAST(SeriesNumber AS VARCHAR(50)) AS SeriesNumber,
        CAST(SeriesName AS VARCHAR(100)) AS SeriesName,
        CAST(SeriesDescription AS VARCHAR(200)) AS SeriesDescription,
        CAST(AfiItemStatus AS VARCHAR(10)) AS AfiItemStatus,
        CAST(PrimaryVendorNumber AS VARCHAR(50)) AS PrimaryVendorNumber,
        CAST(PrimaryVendorDisplayName AS VARCHAR(200)) AS PrimaryVendorName,
        CAST(Cubes AS DECIMAL(18,4)) AS Cubes,
        CAST(FOBArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(IsFinishedGoodsItem AS BIT) AS IsFinishedGoodsItem,
        CAST(DiscontinuedFlag AS BIT) AS DiscontinuedFlag,
        CAST(NewItemFlag AS BIT) AS NewItemFlag,
        CAST(StatusCodeChangeDate AS DATE) AS StatusCodeChangeDate,
        CAST(UnavailableFlag AS BIT) AS UnavailableFlag
    FROM Shared_DW.DimProduct
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
_PurchaseOrder AS (
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes
    FROM (
        SELECT
            TRIM(podordernum) AS PoNumber,
            CAST(poditemsequence AS INT) AS PoLine,
            TRIM(podvendornum) AS VendorNumber,
            TRIM(poditemnum) AS ItemSku,
            TRIM(podwarehouse) AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))   AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4)) AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4)) AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4)) AS InTransitQtySource,
            CAST(podduedate AS DATE) AS DueDate,
            ROW_NUMBER() OVER (PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence ORDER BY podduedate DESC) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL

    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    
    WHERE r.rn = 1
),
base AS (
    -- Current daily rows (rolling 7d)
    SELECT
        CAST('Current'                          AS VARCHAR(10))  AS SnapshotType,
        ic.SnapshotDate                                          AS SnapshotDate,
        ic.ItemSku, ic.WarehouseCode,
        ic.OnHandQty,
        CAST('ItemMaster_AFI' AS VARCHAR(64))                    AS SourceSystem,
        CAST('ITEMBL'         AS VARCHAR(128))                   AS SourceTable
    FROM _InventoryCurrent ic
    WHERE ic.SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))

    UNION ALL

    -- Weekly history rows
    SELECT
        CAST('Weekly'                                AS VARCHAR(10)),
        iw.SnapshotDate,
        iw.ItemSku, iw.WarehouseCode,
        iw.OnHandQty,
        CAST(iw.SourceSystem AS VARCHAR(64)),
        CAST(iw.SourceTable AS VARCHAR(128))
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeeklyFactBase] iw
),
latest_current_date AS (
    SELECT MAX(SnapshotDate) AS MaxDate
    FROM _InventoryCurrent
),
-- Snapshot-aware PO/MO/Hold aggregates
po_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(POOnOrderQty) AS POOnOrderQty,
        SUM(POInTransitQty) AS POInTransitQty
    FROM _PurchaseOrder
    GROUP BY ItemSku, WarehouseCode
),
po_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(POOnOrderQty) AS POOnOrderQty,
        SUM(POInTransitQty) AS POInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
mo_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM _ManufacturingOrder
    GROUP BY ItemSku, WarehouseCode
),
mo_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(TransferQty) AS OnHoldQty,
        SUM(TransferCube) AS OnHoldCube
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[HoldingTransferSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(TransferQty) AS OnHoldQty,
        SUM(TransferCube) AS OnHoldCube
    FROM _HoldingTransfer
    GROUP BY ItemSku, WarehouseCode
),
-- Transfer-in InTransit (paired warehouse from ITEMBL)
ti_curr AS (
    SELECT
        TRIM(b.ITNBR)         AS ItemSku,
        TRIM(w.WarehouseCode) AS WarehouseCode,
        SUM(CAST(b.MOHTQ AS DECIMAL(18,4)))   AS TransferInInTransitQty
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    JOIN _WarehouseExt w
         ON TRIM(w.IntransitWarehouseCode) = TRIM(b.HOUSE)
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
    GROUP BY TRIM(b.ITNBR), TRIM(w.WarehouseCode)
),
-- Pre-derive InventoryValueAtCost for AvgInv12M computation
ivc_monthly AS (
    SELECT DISTINCT
        b.ItemSku, b.WarehouseCode, d.FSCMonthYearNum AS FiscalMonthYear,
        ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS InventoryValueAtCost
    FROM base b
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
         ON d.[Date] = b.SnapshotDate
    LEFT JOIN _CostCurrent cc
         ON cc.ItemSku = b.ItemSku
    WHERE d.[Date] = (
        SELECT MAX(d2.[Date])
        FROM [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d2
        WHERE d2.FSCMonthYearNum = d.FSCMonthYearNum
    )  -- month-end approximation
),
avg_ivc12 AS (
    SELECT
        ItemSku, WarehouseCode, FiscalMonthYear,
        AVG(InventoryValueAtCost) OVER (
            PARTITION BY ItemSku, WarehouseCode
            ORDER BY FiscalMonthYear
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) AS AvgInvValue12M
    FROM ivc_monthly
)
SELECT
    -- Grain
    CAST(b.ItemSku           AS VARCHAR(50))  AS ItemSku,
    CAST(b.WarehouseCode     AS VARCHAR(50))  AS WarehouseCode,
    CAST(b.SnapshotDate      AS DATE)         AS SnapshotDate,
    CAST(b.SnapshotType      AS VARCHAR(10))  AS SnapshotType,
    CAST(d.FSCWeekLast       AS DATE)         AS WeekEndingDate,
    CAST(d.DateSK            AS INT)          AS DateKey,    -- FIX 2026-05-19: DimCalendar (Gold) uses DateSK; Calendar (Silver) uses SKDate
    CAST(d.FSCMonthNum       AS INT)          AS FiscalMonth,
    CAST(d.FSCMonthYearNum   AS INT)          AS FiscalMonthYear,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              AND b.SnapshotDate = (SELECT MaxDate FROM latest_current_date)
              THEN 1 ELSE 0 END AS BIT)        AS IsLatestSnapshot,
    CAST(b.SourceSystem      AS VARCHAR(64))   AS SourceSystem,
    CAST(b.SourceTable       AS VARCHAR(128))  AS SourceTable,
    CAST(1                   AS BIGINT)        AS RuleVersionKey,

    -- Base supply qty
    CAST(ISNULL(b.OnHandQty, 0)                          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ISNULL(ti.TransferInInTransitQty, 0)            AS DECIMAL(18,4)) AS TransferInInTransitQty,

    -- Snapshot-aware PO / MO / Hold pull
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(pc.POInTransitQty, 0)
              ELSE ISNULL(ps.POInTransitQty, 0) END     AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(pc.POOnOrderQty, 0)
              ELSE ISNULL(ps.POOnOrderQty, 0) END       AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(mc.MOOnOrderQty, 0)
              ELSE ISNULL(ms.MOOnOrderQty, 0) END       AS DECIMAL(18,4)) AS MOOnOrderQty,

    -- Derived totals
    CAST(ISNULL(ti.TransferInInTransitQty,0) +
         CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POInTransitQty,0)
              ELSE ISNULL(ps.POInTransitQty,0) END
         AS DECIMAL(18,4))                              AS InTransitQty,
    CAST(CASE WHEN b.SnapshotType='Current'
              THEN ISNULL(pc.POOnOrderQty,0) + ISNULL(mc.MOOnOrderQty,0)
              ELSE ISNULL(ps.POOnOrderQty,0) + ISNULL(ms.MOOnOrderQty,0) END
         AS DECIMAL(18,4))                              AS OnOrderQty,

    -- Demand & coverage
    CAST(awd.AwdQty         AS DECIMAL(18,4))           AS AwdQty,
    CAST(awd.AwdSource      AS VARCHAR(20))             AS AwdSource,
    CAST(CASE WHEN awd.AwdQty > 0
              THEN b.OnHandQty / awd.AwdQty END
         AS DECIMAL(18,4))                              AS WeeksOfSupply,
    CAST(ss.SafetyStockTarget AS DECIMAL(18,4))         AS SafetyStockTargetQty,
    CAST(CASE WHEN ss.SafetyStockTarget > 0
              THEN b.OnHandQty / ss.SafetyStockTarget END
         AS DECIMAL(18,4))                              AS SafetyStockMultiple,

    -- Inventory classification (BRD v1)
    CAST(CASE
        WHEN dim.AfiItemStatus IN ('D','R')
         AND (ISNULL(b.OnHandQty,0)
            + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
            + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
            THEN 'Inactive'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 0.5 * ss.SafetyStockTarget THEN 'Below Target'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 1.5 * ss.SafetyStockTarget THEN 'Sweet Spot'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 17  * awd.AwdQty THEN 'Over Target'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 52  * awd.AwdQty THEN 'Excess'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 104 * awd.AwdQty THEN 'Aggressive Excess'
        ELSE 'TB Inventory'
    END AS VARCHAR(30))                                 AS InventoryClassification,

    -- Financial
    CAST(cc.StandardCost  AS DECIMAL(18,4))             AS StandardCost,
    CAST(dim.FobArcPrice  AS DECIMAL(18,4))             AS FobArcPrice,
    CAST(dim.Cubes        AS DECIMAL(18,4))             AS Cubes,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS DECIMAL(18,4)) AS InventoryValueAtCost,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.FobArcPrice,0) AS DECIMAL(18,4)) AS InventoryValueAtRevenue,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.Cubes,0)       AS DECIMAL(18,4)) AS UsedStorageCube,

    -- Rolling COGS (Pass 2 inlined via JOIN to v_CogsRollingHelper)
    CAST(coh.PeriodCogs AS DECIMAL(18,4))               AS PeriodCogs,
    CAST(coh.Cogs52M    AS DECIMAL(18,4))               AS Cogs52M,
    CAST(coh.Cogs12M    AS DECIMAL(18,4))               AS Cogs12M,
    CAST(aiv.AvgInvValue12M AS DECIMAL(18,4))           AS AverageInventoryValueAtCost,

    -- Status flags
    CAST(lh.LastInvoiceDate AS DATE)                    AS LastInvoiceDate,
    CAST(dim.LifecycleStatus AS VARCHAR(20))            AS LifecycleStatus,
    CAST(CASE WHEN dim.AfiItemStatus IN ('D','R')
              AND (ISNULL(b.OnHandQty,0)
                + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
                + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS InactiveFlag,
    -- M4 FIX (2026-05-17): require LastInvoiceDate IS NOT NULL to avoid false-positive SLOB on new items.
    CAST(CASE WHEN dim.AfiItemStatus <> 'N'
              AND lh.LastInvoiceDate IS NOT NULL
              AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
              THEN 1 ELSE 0 END
         AS BIT)                                        AS SlobFlag,
    CAST(CASE WHEN ISNULL(mf.HasMovementLast17W, 0) = 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS NoMovementFlag,
    CAST(dim.UnavailableFlag AS BIT)                    AS UnavailableFlag,

    -- Hold (snapshot-aware)
    CAST(CASE WHEN b.SnapshotType='Current'
              THEN ISNULL(hc.OnHoldQty, 0)
              ELSE ISNULL(hs.OnHoldQty, 0) END
         AS DECIMAL(18,4))                              AS OnHoldQty,
    CAST(CASE WHEN (CASE WHEN b.SnapshotType='Current' THEN ISNULL(hc.OnHoldQty,0) ELSE ISNULL(hs.OnHoldQty,0) END) > 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS OnHoldFlag,

    -- Obsolete (SLOB-flagged inventory value at cost)
    -- M4 FIX: same NULL handling as SlobFlag
    CAST(CASE WHEN dim.AfiItemStatus <> 'N'
              AND lh.LastInvoiceDate IS NOT NULL
              AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
              THEN ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0)
              ELSE 0 END
         AS DECIMAL(18,4))                              AS ObsoleteValue
FROM base b
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
       ON d.[Date] = b.SnapshotDate
-- DimItem reused from forecast's DimProduct + augmented inline with InventoryHistory ItemMasterExt fields
LEFT JOIN _ItemMasterExt dim_ext
       ON dim_ext.ItemSku = b.ItemSku
LEFT JOIN (
    -- Mirror deliverable's DimItem layout: select needed cols from ItemMasterExt + lifecycle case
    SELECT
        ItemSku, AfiItemStatus, FobArcPrice, Cubes, UnavailableFlag,
        CASE
            WHEN DiscontinuedFlag = 1     THEN 'Discontinued'
            WHEN AfiItemStatus = 'N'      THEN 'New'
            WHEN AfiItemStatus = 'A'      THEN 'Active'
            WHEN AfiItemStatus IN ('D','R') THEN 'Inactive'
            ELSE 'Other'
        END AS LifecycleStatus
    FROM _ItemMasterExt
) dim ON dim.ItemSku = b.ItemSku
LEFT JOIN _CostCurrent cc
       ON cc.ItemSku = b.ItemSku
LEFT JOIN ti_curr ti                  ON ti.ItemSku=b.ItemSku AND ti.WarehouseCode=b.WarehouseCode
LEFT JOIN po_curr pc                  ON pc.ItemSku=b.ItemSku AND pc.WarehouseCode=b.WarehouseCode
LEFT JOIN po_snap ps                  ON ps.ItemSku=b.ItemSku AND ps.WarehouseCode=b.WarehouseCode AND ps.SnapshotDate=b.SnapshotDate
LEFT JOIN mo_curr mc                  ON mc.ItemSku=b.ItemSku AND mc.WarehouseCode=b.WarehouseCode
LEFT JOIN mo_snap ms                  ON ms.ItemSku=b.ItemSku AND ms.WarehouseCode=b.WarehouseCode AND ms.SnapshotDate=b.SnapshotDate
LEFT JOIN hold_curr hc                ON hc.ItemSku=b.ItemSku AND hc.WarehouseCode=b.WarehouseCode
LEFT JOIN hold_snap hs                ON hs.ItemSku=b.ItemSku AND hs.WarehouseCode=b.WarehouseCode AND hs.SnapshotDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
       ON awd.ItemSku=b.ItemSku AND awd.WarehouseCode=b.WarehouseCode AND awd.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceHelper] lh
       ON lh.ItemSku=b.ItemSku AND lh.WarehouseCode=b.WarehouseCode AND lh.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[MovementFlagHelper] mf
       ON mf.ItemSku=b.ItemSku AND mf.WarehouseCode=b.WarehouseCode AND mf.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss
       ON ss.ItemSku=b.ItemSku AND ss.WarehouseCode=b.WarehouseCode AND ss.AsOfDate=b.SnapshotDate
-- Rolling COGS (Pass 2 inlined): join CogsRollingHelper on FiscalMonthYear of SnapshotDate
LEFT JOIN [SupplyChain_Gold_Warehouse].[InventoryHealth_DW].[CogsRollingHelper] coh
       ON coh.ItemSku=b.ItemSku AND coh.WarehouseCode=b.WarehouseCode
      AND coh.FiscalMonthYear=d.FSCMonthYearNum
LEFT JOIN avg_ivc12 aiv
       ON aiv.ItemSku=b.ItemSku AND aiv.WarehouseCode=b.WarehouseCode
      AND aiv.FiscalMonthYear=d.FSCMonthYearNum