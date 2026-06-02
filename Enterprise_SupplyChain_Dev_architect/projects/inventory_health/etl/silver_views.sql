-- ============================================================
-- Silver Views — InventoryHealth Project (project='inventory_health')
-- ============================================================
-- Layer: Silver. Pattern: 1 generic SP (Meta.usp_GenericLoad) + N views.
--   Each view encapsulates business logic from the deliverable v1 procs.
--   Meta.usp_GenericLoad reads Meta.AssetRegistry to know:
--     - load_type (overwrite | incremental | datekey | upsert | ...)
--     - watermark_column / primary_key / date_key (incremental/datekey/upsert)
--     - last_watermark_value (for incremental)
--   At CTAS time: SELECT * FROM <view> + auto-inject LoadDT column.
-- Source (target WH): SupplyChain_Processing_Warehouse (c0262cef-...)
-- Target schemas: InventoryHistory_Enh (NEW) + ReferenceMaster_Enh (extend with Vendor only)
-- Reuse (do NOT recreate): ReferenceMaster_Enh.ItemMaster, ReferenceMaster_Enh.Warehouse, ReferenceMaster_Enh.Calendar
-- ============================================================
-- Track A fixes preserved (deliverable v1, 2026-05-17):
--   H1 ItemAllocationFlag=2 (Robert sign-off pending)
--   H2 ATPSUM UNPIVOT APAT01-43 only (data-shape fix)
--   H3 FG-only + WH exclusion (matches sếp's PurchaseOrderSnapshot)
--   H4 ORDER BY FiscalMonthYear (math fix, applied in gold_views)
--   H5 WeekFourFlag exact week (applied in gold_views, Robert sign-off pending)
--   M1 Saturday detection via DATENAME — N/A (handled by Meta.usp_GenericLoad cron)
--   M3 Cogs52W → Cogs52M rename (applied in gold_views, Robert sign-off pending)
--   M4 SLOB NULL guard (applied in gold_views)
--   M5 AWD COUNTROWS SUMMARIZE (applied in DAX)
--   B1 PoDetail source switched Enterprise.PoDetail (preserved below)
--   B2 ForecastCurrent reads DemandForecast (preserved below)
--   B3 Warehouse exclusion flag columns (preserved in v_WarehouseExt + v_InventoryCurrent)
-- ============================================================


-- ============================================================
-- §A. ReferenceMaster_Enh — NEW Vendor view (1 NEW)
--     ItemMaster + Warehouse already exist; only Vendor is NEW.
-- ============================================================

-- ---- ReferenceMaster_Enh.v_Vendor (NEW for inventory_health) ----
-- Source: Enterprise_Lakehouse.Purchasing_AFI.VendorMaster (51 cols, 86,598 rows)
CREATE VIEW ReferenceMaster_Enh.v_Vendor AS
SELECT
    CAST(TRIM(v.VendorNumber) AS VARCHAR(50))           AS VendorNumber,
    CAST(v.VendorName         AS VARCHAR(200))          AS VendorName,
    CAST('Purchasing_AFI'     AS VARCHAR(64))           AS SourceSystem,
    CAST('VendorMaster'       AS VARCHAR(128))          AS SourceTable
FROM [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
WHERE v.VendorNumber IS NOT NULL AND TRIM(v.VendorNumber) <> ''

GO


-- ============================================================
-- §B. InventoryHistory_Enh — Master extension views (2 views)
--     Wrap existing ReferenceMaster_Enh.ItemMaster + Warehouse with
--     inventory-specific columns NOT present in the base masters.
--     These views are persisted into InventoryHistory_Enh via GenericLoad
--     (overwrite, monthly) so downstream Silver/Gold can JOIN them.
-- ============================================================

-- ---- InventoryHistory_Enh.v_ItemMasterExt ----
-- Base columns sourced from DimItemMaster (matches ReferenceMaster_Enh.ItemMaster lineage).
-- Extension JOINs:
--   - VendorMaster (Purchasing_AFI) → PrimaryVendorName
--   - ITBEXT (ItemMaster_AFI) → UnavailableFlag (MAX MFPUS='U' per ItemSku)
CREATE VIEW InventoryHistory_Enh.v_ItemMasterExt AS
WITH unavailable AS (
    SELECT
        TRIM(ITNBR) AS ItemSku,
        MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
    WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
    GROUP BY TRIM(ITNBR)
)
SELECT
    CAST(TRIM(d.ItemSKU)                AS VARCHAR(50))   AS ItemSku,
    CAST(d.ItemDescription              AS VARCHAR(200))  AS ItemDescription,
    CAST(TRIM(d.ItemClassCode)          AS VARCHAR(50))   AS ItemClassCode,
    CAST(d.ItemClassName                AS VARCHAR(100))  AS ItemClassName,
    CAST(d.RetailCategoryName           AS VARCHAR(100))  AS CategoryName,
    CAST(d.RetailCategoryCode           AS VARCHAR(50))   AS CategoryCode,
    CAST(d.CollectiveClass              AS VARCHAR(50))   AS CollectiveClass,
    CAST(d.SeriesNumber                 AS VARCHAR(50))   AS SeriesNumber,
    CAST(d.SeriesName                   AS VARCHAR(100))  AS SeriesName,
    CAST(d.SeriesDescription            AS VARCHAR(200))  AS SeriesDescription,
    CAST(TRIM(d.AFIItemStatus)          AS VARCHAR(10))   AS AfiItemStatus,
    CAST(TRIM(d.PrimaryVendor)          AS VARCHAR(50))   AS PrimaryVendorNumber,
    CAST(v.VendorName                   AS VARCHAR(200))  AS PrimaryVendorName,
    CAST(d.Cubes                        AS DECIMAL(18,4)) AS Cubes,
    CAST(d.FOBArcPrice                  AS DECIMAL(18,4)) AS FobArcPrice,
    CAST(CASE
        WHEN LEFT(TRIM(d.ItemClassCode), 1) = 'Z'
         AND RIGHT(TRIM(d.ItemClassCode), 1) = 'K'
        THEN 1 ELSE 0
    END AS BIT)                                            AS IsFinishedGoodsItem,
    CAST(d.DiscontinuedFlag             AS BIT)            AS DiscontinuedFlag,
    CAST(d.NewItemFlag                  AS BIT)            AS NewItemFlag,
    CAST(d.StatusCodeChangeDate         AS DATE)           AS StatusCodeChangeDate,
    CAST(ISNULL(u.UnavailableFlag, 0)   AS BIT)            AS UnavailableFlag,
    CAST('MasterData_DW+ITBEXT'         AS VARCHAR(64))    AS SourceSystem,
    CAST('DimItemMaster+ITBEXT(MFPUS)'  AS VARCHAR(128))   AS SourceTable
FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
       ON TRIM(v.VendorNumber) = TRIM(d.PrimaryVendor)
LEFT JOIN unavailable u
       ON u.ItemSku = TRIM(d.ItemSKU)
WHERE d.ItemSKU IS NOT NULL AND TRIM(d.ItemSKU) <> ''

GO


-- ---- InventoryHistory_Enh.v_WarehouseExt ----
-- Base: AshleyWarehouseMaster (Wholesale_Codis_AFI). Extension adds:
--   - IsFinishedGoodsWarehouse + IsManufacturingWarehouse flags
--   - B3 FIX: IsExcludedDirectCustomerRP flag (direct-to-customer / RP exclusion)
--   - IsNetworkInventoryWarehouse flag (matrix v3 extended network)
CREATE VIEW InventoryHistory_Enh.v_WarehouseExt AS
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
    -- B3 FIX (2026-05-17): WH exclusion list (direct-to-customer / RP) — from sếp's PurchaseOrderSnapshot query
    CAST(CASE WHEN TRIM(w.wmaWarehouse) IN ('C','CNW','AF','IOR','C35','55','MAX')
              THEN 1 ELSE 0 END AS BIT)                          AS IsExcludedDirectCustomerRP,
    -- Extended network list (matrix v3 alt)
    CAST(CASE WHEN TRIM(w.wmaWarehouse) IN ('1','5','15','17','28','42','ECR','3','12','16','19')
              THEN 1 ELSE 0 END AS BIT)                          AS IsNetworkInventoryWarehouse,
    CAST(NULL                                  AS DECIMAL(18,4)) AS TotalAvailableWarehouseCube,
    CAST('Wholesale_Codis_AFI'                 AS VARCHAR(64))   AS SourceSystem,
    CAST('AshleyWarehouseMaster'               AS VARCHAR(128))  AS SourceTable
FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster] w
WHERE w.wmaWarehouse IS NOT NULL AND TRIM(w.wmaWarehouse) <> ''

GO


-- ============================================================
-- §C. InventoryHistory_Enh — Tier 1 base tables (12 views)
-- ============================================================

-- ---- InventoryHistory_Enh.v_CostCurrent ----
-- ITMRVA dedupe (STID+ITNBR, STID='000'). Pick latest by ITRV DESC.
CREATE VIEW InventoryHistory_Enh.v_CostCurrent AS
WITH ranked AS (
    SELECT
        TRIM(ITNBR)                          AS ItemSku,
        TRIM(STID)                           AS CostId,
        CAST(UCDEF AS DECIMAL(18,4))         AS StandardCost,
        CAST(ITRV  AS VARCHAR(20))           AS ItemRevision,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(STID), TRIM(ITNBR)
            ORDER BY ITRV DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
    WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
      AND TRIM(STID)  = '000'
      AND TRIM(ITNBR) <> ''
)
SELECT
    CAST(ItemSku       AS VARCHAR(50))    AS ItemSku,
    CAST(CostId        AS VARCHAR(10))    AS CostId,
    CAST(StandardCost  AS DECIMAL(18,4))  AS StandardCost,
    CAST(ItemRevision  AS VARCHAR(20))    AS ItemRevision,
    CAST('ItemMaster_AFI'     AS VARCHAR(64))   AS SourceSystem,
    CAST('ITMRVA(STID=000)'   AS VARCHAR(128))  AS SourceTable
FROM ranked
WHERE rn = 1

GO


-- ---- InventoryHistory_Enh.v_InventoryCurrent ----
-- ITEMBL on-hand snapshot. Daily reload via datekey load_type (registry).
-- H3 FIX (2026-05-17): FG-only filter (ItemClassCode like Z%K) — 99.98% match vs 32% w/o
-- B3 FIX (2026-05-17): exclude direct-to-customer/RP warehouses
-- BLOCKED: Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL needs full DE US load — flag in registry is_active=0 initially.
CREATE VIEW InventoryHistory_Enh.v_InventoryCurrent AS
SELECT
    CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
    CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
    CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
    CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate,
    CAST('ItemMaster_AFI'           AS VARCHAR(64))   AS SourceSystem,
    CAST('ITEMBL'                   AS VARCHAR(128))  AS SourceTable
FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
  AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
  -- H3 FIX: FG-only per BRD §6.5 / sheet R21
  AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
  AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
  -- B3 FIX: WH exclusion list (direct-to-customer / RP)
  AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')

GO


-- ---- InventoryHistory_Enh.v_SupplyPlan ----
CREATE VIEW InventoryHistory_Enh.v_SupplyPlan AS
SELECT
    CAST(TRIM(spdItem)                              AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(spdWarehouse)                         AS VARCHAR(50))   AS WarehouseCode,
    CAST(dtea                                       AS DATE)          AS SnapshotDate,
    CAST(spdWeekEnding                              AS DATE)          AS WeekEndingDate,
    CAST(spdBeginingBalance                         AS DECIMAL(18,4)) AS BeginningBalanceQty,
    CAST(spdFirmDemands                             AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(spdNetForecast                             AS DECIMAL(18,4)) AS NetForecastQty,
    CAST(spdFirmPurchaseOrders                      AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
    CAST(spdPlannedPurchaseOrders                   AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
    CAST(spdOnOrderTransferIn                       AS DECIMAL(18,4)) AS OnOrderTransferInQty,
    CAST(spdShippableInventory                      AS DECIMAL(18,4)) AS ShippableInventoryQty,
    CAST(spdSafetyStock                             AS DECIMAL(18,4)) AS SafetyStockTargetQty,
    CAST(spdMonthsOfSupply                          AS DECIMAL(18,4)) AS MonthsOfSupply,
    CAST(CASE WHEN spdShippableInventory < 0
              THEN ABS(CAST(spdShippableInventory AS DECIMAL(18,4)))
              ELSE 0 END                            AS DECIMAL(18,4)) AS SINegQty,
    CAST('Wholesale_DemandPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyPlanDetail'              AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
  AND TRIM(spdItem) <> '' AND TRIM(spdWarehouse) <> ''

GO


-- ---- InventoryHistory_Enh.v_SalesShipment ----
-- REMOVED 2026-05-28: DA-first flow reads SalesHistory_Enh.v_InvoiceDetailLineLevel directly.
-- Do not recreate Mart B SalesShipment materialization or alias view.



-- ---- InventoryHistory_Enh.v_PurchaseOrder ----
-- B1 FIX (2026-05-17): switched source SupplyChain.dbo.podetail_v2 → Enterprise.PoDetail (21.95M rows).
-- B1.2 FIX (2026-05-19): Dhivya loaded Enterprise.PoMaster (5.69M rows, 75 cols) — switched LEFT JOIN from SC_LH.dbo.pomaster → Enterprise.PoMaster. SC_LH.dbo.pomaster legacy path can be deprecated.
-- DA Silver_Check 2026-05-28: keep direct-to-customer/RP warehouses in PO source.
-- DEDUPE: PoDetail has 1 verified true-dup pair (Key 'P0SM242'|'612908'|1 — all 53 cols identical); ROW_NUMBER drops safely.
CREATE VIEW InventoryHistory_Enh.v_PurchaseOrder AS
WITH ranked AS (
    SELECT
        TRIM(podordernum)                          AS PoNumber,
        CAST(poditemsequence AS INT)               AS PoLine,
        TRIM(podvendornum)                         AS VendorNumber,
        TRIM(poditemnum)                           AS ItemSku,
        TRIM(podwarehouse)                         AS WarehouseCode,
        CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
        CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
        CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
        CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
        CAST(podduedate     AS DATE)               AS DueDate,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
            ORDER BY podduedate DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]  -- B1 FIX: Enterprise (was SC.podetail_v2)
    WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
      AND TRIM(poditemnum) <> '' AND TRIM(podwarehouse) <> ''
)
SELECT
    CAST(r.PoNumber             AS VARCHAR(50))   AS PoNumber,
    CAST(r.PoLine               AS INT)           AS PoLine,
    CAST(r.VendorNumber         AS VARCHAR(50))   AS VendorNumber,
    CAST(r.ItemSku              AS VARCHAR(50))   AS ItemSku,
    CAST(r.WarehouseCode        AS VARCHAR(50))   AS WarehouseCode,
    CAST(r.StatusCode           AS VARCHAR(10))   AS StatusCode,
    CAST(r.StockQty             AS DECIMAL(18,4)) AS StockQty,
    CAST(r.OrderedQty           AS DECIMAL(18,4)) AS OrderedQty,
    CAST(r.InTransitQtySource   AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(r.DueDate              AS DATE)          AS DueDate,
    CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
    CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
    CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
    CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
    CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
    CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('PoDetail+PoMaster (both Enterprise)'   AS VARCHAR(128)) AS SourceTable
FROM ranked r
-- B1.2 FIX 2026-05-19: switched from SC_LH.dbo.pomaster → Enterprise.PoMaster after Dhivya load
LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
       ON TRIM(h.pomordernum)  = r.PoNumber
WHERE r.rn = 1

GO


-- ---- InventoryHistory_Enh.v_ManufacturingOrder ----
-- L3 (deferred): OSTAT firm list ('10','40','45') needs Robert sign-off.
CREATE VIEW InventoryHistory_Enh.v_ManufacturingOrder AS
SELECT
    CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
    CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
    CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
    CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
    CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
    CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
    -- L3 PENDING: firm OSTAT list ('10','40','45') awaiting Robert sign-off
    CAST(CASE WHEN TRIM(OSTAT) IN ('10', '40', '45')
              THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
              ELSE 0
         END                          AS DECIMAL(18,4))  AS MOOnOrderQty,
    CAST(ODUDT                        AS INT)            AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
  AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''

GO


-- ---- InventoryHistory_Enh.v_LogilityItemStatus ----  [PHASE 2 DEACTIVATED 2026-05-22]
-- Reason: KPI #17 Inactive / #18 SLOB / #20a Lifecycle past-tracking are Phase 2
-- conditional KPIs (Excel: "P2 conditional, chờ Robert"). Current status served via
-- DimItemMaster.AFIItemStatus (Phase 1 path). View kept for Phase 2 reactivation;
-- the downstream materialization LogilityItemStatusSnapshotWeekly is_active=0.
-- A3 RESOLVED 2026-05-19: Dhivya promoted to Enterprise.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility (38.36M rows, 53 cols, types match SC_LH).
-- D1 FIX 2026-05-19: source has 9,128 GRAIN-CONFLICT groups (NOT true dups) at (Item,Whse,WeekEnding) — 47/53 cols identical, 6 metrics differ.
--   Pattern: 1 row has actual data, 1 row has zero-placeholder metrics. StatusChngDate IDENTICAL across dup group → old ORDER BY was non-deterministic.
--   New ORDER BY: prefer row where ShippableInvQty/FirmDemand/OnHandQty are non-zero (data-bearing); fallback to StatusChngDate then OnHandAmt.
--   Root cause unfixable upstream (DE confirmed Slack 2026-05-09); v10 deterministic at-query-time dedupe.
CREATE VIEW InventoryHistory_Enh.v_LogilityItemStatus AS
WITH ranked AS (
    SELECT
        TRIM(Item)                            AS ItemSku,
        TRIM(Whse)                            AS WarehouseCode,
        CAST(WeekEnding AS DATE)              AS WeekEndingDate,
        TRIM(ItemStatus)                      AS ItemStatus,
        TRIM(FutureStatus)                    AS FutureStatus,
        CAST(StatusChngDate AS DATE)          AS StatusChangeDate,
        CAST(OnHandQty AS DECIMAL(18,4))      AS OnHandQty,
        CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
        CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
        CAST(MosofSupply AS DECIMAL(18,4))    AS MonthsOfSupply,
        CAST(Price AS DECIMAL(18,4))          AS Price,
        TRIM(ItemClass)                       AS ItemClass,
        TRIM(Vendor)                          AS Vendor,
        TRIM(HoldBuy)                         AS HoldBuyCode,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
            ORDER BY
                -- D1 FIX 2026-05-19 (v2): identify placeholder rows by demand-side metrics ONLY.
                -- OnHandQty đã EXCLUDED khỏi CASE vì là identity-attribute (luôn ≠ 0 trên cả 2 row dup, không phân biệt được).
                -- Verified pattern: 74.3% (6,786/9,128) groups có 1 data-row + 1 placeholder zero-row;
                --                   19.6% (1,791) both zero (drop any); 6.0% (551) both have data (tiebreaker = OnHandAmt).
                CASE WHEN COALESCE(ShippableInvQty,0) = 0
                      AND COALESCE(FirmDemand,0) = 0 THEN 1 ELSE 0 END ASC,
                StatusChngDate DESC,                       -- legacy tiebreaker (usually identical within group)
                COALESCE(OnHandAmt,0) DESC,                -- for "both have data" 6% case — pick higher inventory value
                CAST(FileDate AS DATETIME2) DESC           -- absolute last resort
        ) AS rn
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandFulfillmentCommonContainer_Logility]  -- A3 FIX 2026-05-19: was SC_LH.dbo.logility_demandfulfillment
    WHERE Item IS NOT NULL AND Whse IS NOT NULL
      AND TRIM(Item) <> '' AND TRIM(Whse) <> ''
)
SELECT
    CAST(ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(WeekEndingDate    AS DATE)          AS WeekEndingDate,
    CAST(ItemStatus        AS VARCHAR(20))   AS ItemStatus,
    CAST(FutureStatus      AS VARCHAR(20))   AS FutureStatus,
    CAST(StatusChangeDate  AS DATE)          AS StatusChangeDate,
    CAST(OnHandQty         AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockQty    AS DECIMAL(18,4)) AS SafetyStockQty,
    CAST(ShippableInvQty   AS DECIMAL(18,4)) AS ShippableInvQty,
    CAST(MonthsOfSupply    AS DECIMAL(18,4)) AS MonthsOfSupply,
    CAST(Price             AS DECIMAL(18,4)) AS Price,
    CAST(ItemClass         AS VARCHAR(50))   AS ItemClass,
    CAST(Vendor            AS VARCHAR(50))   AS Vendor,
    CAST(HoldBuyCode       AS VARCHAR(10))   AS HoldBuyCode,
    CAST(1                 AS BIT)           AS IsCertified,
    CAST('Enterprise_Lakehouse'        AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility'   AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO


-- ---- InventoryHistory_Enh.v_HoldingTransfer ----
-- TFRDTL + TFRHDR. Same-warehouse holding transfers.
-- DA Silver_Check 2026-05-28: keep cancelled rows; expose CancelFlag for downstream logic.
CREATE VIEW InventoryHistory_Enh.v_HoldingTransfer AS
WITH ranked AS (
    SELECT
        TRIM(d.DTFRNO)                       AS TransferNumber,
        TRIM(d.DITNBR)                       AS ItemSku,
        TRIM(h.HFHOUS)                       AS WarehouseCode,
        CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
        CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
        CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
        TRIM(h.HSTATS)                       AS HeaderStatus,
        TRIM(h.HCANCL)                       AS CancelFlag,
        CAST(h.HSHDTE AS INT)                AS ShipDateKey,
        CAST(h.HDLDTE AS INT)                AS DueDateKey,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
            ORDER BY h.HDLDTE DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
    JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
         ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
    WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
      AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
      AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
)
SELECT
    CAST(TransferNumber  AS VARCHAR(50))   AS TransferNumber,
    CAST(ItemSku         AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode   AS VARCHAR(50))   AS WarehouseCode,
    CAST(TransferQty     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TransferCube    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus    AS VARCHAR(10))   AS HeaderStatus,
    CAST(CancelFlag      AS VARCHAR(5))    AS CancelFlag,
    CAST(ShipDateKey     AS INT)           AS ShipDateKey,
    CAST(DueDateKey      AS INT)           AS DueDateKey,
    CAST('Manufacturing_Inventory_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO


-- ---- InventoryHistory_Enh.v_AtpWeekEnding ----
-- H2 FIX (2026-05-17): UNPIVOT only APAT01-43 (APWK columns don't exist as series).
-- Derive WeekEndingDate = BaseWeekEnding (APWK01) + (WeekNumber - 1) weeks.
CREATE VIEW InventoryHistory_Enh.v_AtpWeekEnding AS
WITH base AS (
    SELECT
        TRIM(APITNB)                                                  AS ItemSku,
        TRIM(APHOUS)                                                  AS WarehouseCode,
        TRY_CAST(CAST(CAST(APWK01 AS BIGINT) AS VARCHAR(8)) AS DATE)  AS BaseWeekEndingDate
    FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
    WHERE APITNB IS NOT NULL AND APHOUS IS NOT NULL
      AND TRIM(APITNB) <> '' AND TRIM(APHOUS) <> ''
),
unpiv AS (
    SELECT
        TRIM(APITNB)                          AS ItemSku,
        TRIM(APHOUS)                          AS WarehouseCode,
        CAST(REPLACE(WeekCol, 'APAT', '') AS INT) AS WeekNumber,
        CAST(AtpQty AS DECIMAL(18,4))         AS AtpQty
    FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
    UNPIVOT (AtpQty FOR WeekCol IN (
        APAT01,APAT02,APAT03,APAT04,APAT05,APAT06,APAT07,APAT08,APAT09,APAT10,
        APAT11,APAT12,APAT13,APAT14,APAT15,APAT16,APAT17,APAT18,APAT19,APAT20,
        APAT21,APAT22,APAT23,APAT24,APAT25,APAT26,APAT27,APAT28,APAT29,APAT30,
        APAT31,APAT32,APAT33,APAT34,APAT35,APAT36,APAT37,APAT38,APAT39,APAT40,
        APAT41,APAT42,APAT43
    )) u
)
SELECT
    CAST(u.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(u.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(u.WeekNumber     AS INT)           AS WeekNumber,
    CAST(DATEADD(week, u.WeekNumber - 1, b.BaseWeekEndingDate) AS DATE) AS WeekEndingDate,
    CAST(u.AtpQty         AS DECIMAL(18,4)) AS AtpQty,
    CAST('Wholesale_Purchasing_AFI'    AS VARCHAR(64))  AS SourceSystem,
    CAST('ATPSUM(UNPIVOT APAT01-43)'   AS VARCHAR(128)) AS SourceTable
FROM unpiv u
JOIN base b ON b.ItemSku = u.ItemSku AND b.WarehouseCode = u.WarehouseCode
WHERE b.BaseWeekEndingDate IS NOT NULL

GO


-- ---- InventoryHistory_Enh.v_MovementHistory ---- [DROPPED 2026-05-22]
-- Reason: Tagged orphan in Option B inline refactor 2026-05-21 + watermark bug
-- (future-date 2026-11-10 → 0 rows loaded). KPI #26 Obsolete Ratio served via
-- LastInvoiceHelper (no-movement check); KPI #30 Total Commitment not wired in Phase 1.
-- To restore for Phase 2: see git history pre-2026-05-22 for full CREATE VIEW definition
-- sourcing Enterprise_Lakehouse.Manufacturing_Inventory_AFI.IMHIST via CYYMMDD date conv.


-- ---- InventoryHistory_Enh.v_AllocatedDemandCandidate ----
-- H1 FIX (2026-05-17): ItemAllocationFlag = 2 (not 1). Probe: {0:16,802; 2:901,411 rows}.
-- Robert sign-off pending — see _open_questions_for_bob.md.
CREATE VIEW InventoryHistory_Enh.v_AllocatedDemandCandidate AS
SELECT
    CAST(TRIM(d.OrderNumber)         AS VARCHAR(50))   AS OrderNumber,
    CAST(ROW_NUMBER() OVER (
        PARTITION BY TRIM(d.OrderNumber)
        ORDER BY d.LoadDate DESC, d.PromiseDate DESC
    )                                AS INT)           AS OrderLine,
    CAST(TRIM(d.ItemSKU)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(d.Warehouse)           AS VARCHAR(50))   AS WarehouseCode,
    CAST(d.PromiseDate               AS DATE)          AS PromiseDate,
    CAST(d.LoadDate                  AS DATE)          AS LoadDate,
    CAST(d.MaterialRequestDate       AS DATE)          AS MaterialRequestDate,
    CAST(d.QuantityBackOrdered       AS DECIMAL(18,4)) AS AllocatedDemandQty,
    CAST(d.QuantityShipped           AS DECIMAL(18,4)) AS QuantityShipped,
    CAST(d.ItemAllocationFlag        AS DECIMAL(18,4)) AS ItemAllocationFlag,
    CAST(TRIM(h.CustomerNumber)      AS VARCHAR(50))   AS CustomerNumber,
    CAST(h.OrderDate                 AS DATE)          AS OrderDate,
    CAST('CustomerOrders_AFI'        AS VARCHAR(64))   AS SourceSystem,
    CAST('OpenOrderDetail+Header'    AS VARCHAR(128))  AS SourceTable
FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
LEFT JOIN [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderHeader] h
       ON TRIM(h.OrderNumber) = TRIM(d.OrderNumber)
-- H1 FIX: ItemAllocationFlag = 2 means "Allocated". Robert sign-off pending.
WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
  AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
  AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
  AND TRIM(d.ItemSKU) <> '' AND TRIM(d.Warehouse) <> ''

GO


-- ---- InventoryHistory_Enh.v_ForecastCurrent ---- [DROPPED 2026-05-22]
-- Reason: Tagged orphan in Option B inline refactor 2026-05-21. KPI #7 Forecast
-- Demand Qty served via ForecastSnapshotWeekly (history) + DAX aggregations; the
-- "current overlay" path via SupplyForecast/DemandForecast was scaffolded but never
-- wired into FactInventoryHealthSnapshot or DAX measures.
-- To restore for Phase 2 current overlay: see git history pre-2026-05-22 for full
-- CREATE VIEW sourcing Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.DemandForecast.

GO


-- ============================================================
-- §D. InventoryHistory_Enh — Tier 2 snapshot history (2 views, incremental)
-- ============================================================

CREATE OR ALTER VIEW InventoryHistory_Enh.v_InventorySnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-27:
--   DemandInventorySnapshotWeekly captures Monday snapshots, while Inventory Health needs Saturday snapshots.
--   Use DemandInventorySnapshotDaily and filter to Saturday captures.
--   SnapshotWeekEndingDate is now the actual Saturday capture date.
--   FiscalMonth/FiscalMonthDate describe the inventory forecast period.
--   Grain: (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth).
--   Do not use InventoryHistory_Enh.ItemBalanceHistorical as backup/backfill information.
WITH source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(dinSnapshot AS DATE) AS SnapshotWeekEndingDate,
        CAST(dinFiscalMonth AS INT) AS FiscalMonth,
        CAST(DATEFROMPARTS(CAST(dinFiscalMonth / 100 AS INT), CAST(dinFiscalMonth % 100 AS INT), 1) AS DATE) AS FiscalMonthDate,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(dinIOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
        CAST(dinOrderQuantity AS DECIMAL(18,4)) AS OrderQty,
        CAST(dinBuildQuantity AS DECIMAL(18,4)) AS BuildQty,
        CAST(TRIM(dinMakeBuyCode) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(TRIM(dinSource1) AS VARCHAR(50))  AS SourceWarehouseCode,
        CAST('DemandInventorySnapshotDaily' AS VARCHAR(50)) AS SourceLabel,
        CAST('SupplyChain_Enh_1' AS VARCHAR(64)) AS SourceSystem,
        CAST('DemandInventorySnapshotDaily (Sat dedupe)' AS VARCHAR(128)) AS SourceTable,
        dtec,
        dtea
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotDaily]
    WHERE dinItem IS NOT NULL AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> '' AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND CAST(dinFiscalMonth AS INT) BETWEEN 190001 AND 209912
      AND CAST(dinFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
      AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
), ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM source_rows
)
SELECT
    ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth, FiscalMonthDate, MakeBuyCode, SourceWarehouseCode,
    OnHandQty, SafetyStockTarget, IOSafetyStock, OrderQty, BuildQty,
    SourceLabel, SourceSystem, SourceTable
FROM ranked WHERE rn = 1

GO


CREATE OR ALTER VIEW InventoryHistory_Enh.v_ForecastSnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   SnapshotDate is the capture date; FiscalMonthDate is the forecast period.
--   Weekly reporting uses Saturday captures from the daily staging source.
--   Forecast demand is consumed downstream as next 3 fiscal months, not a single week.
--   Reference: Inventory Health Dataset.sql uses ResultantForecast + PromotionalLift for demand.
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotWeekEndingDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(ISNULL(CAST(dfcResultantForecast AS DECIMAL(18,4)), 0)
           + ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS PromoLiftQty,
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty, --Giang: hiện ko sử dụng
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS DependentForecastQty, --Giang: sai
    CAST('Staging_Wrk'                    AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily'    AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.DemandForecastSnapshotDaily
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND CAST(dfcFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
  AND dfcSnapshot IS NOT NULL
  -- Weekly reporting grain: keep Saturday captures only.
  AND DATEDIFF(day, CAST('19000106' AS DATE), CAST(dfcSnapshot AS DATE)) % 7 = 0
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth

GO


-- ============================================================
-- §E. InventoryHistory_Enh — Tier 3 helpers (4 views, overwrite daily)
--     Grain: (ItemSku, WarehouseCode, AsOfDate)
--     AsOfDate set = InventoryCurrent.SnapshotDate (last 7d) ∪ InventorySnapshotWeekly.SnapshotDate (last 104w)
-- ============================================================

-- ---------------------------------------------------------------------
-- AWD candidate:
--   - Preserves the 2026-05-26 FactBase path.
--   - Uses DA 3 fiscal month forecast horizon and dependent demand roll-up.
--   - Uses SalesHistory_Enh.v_InvoiceDetailLineLevel directly for historical fallback per DA Silver_Check.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_AwdHelper AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   Forecast demand = next 3 fiscal months, not one forecast week.
--   DailyFcstQty = ThreeMoForecastQty / HorizonDays.
--   Dependent demand rolls buy/source-dependent demand to source warehouse via InventorySnapshotWeekly.SourceWarehouseCode.
--   TotalDemandDailyQty = DailyFcstQty + DependentDemandDailyQty.
--   AwdQty is weekly-equivalent demand for existing Gold WeeksOfSupply.
--   AwdDailyQty is daily demand for DaysOfSupply = OnHandQty / AwdDailyQty.
--   If forecast demand is zero or missing, fallback to 13-week shipped demand.
-- 2026-05-20 FIX (Giang #4): three-month forecast uses FiscalMonthDate (forecast period)
-- 2026-05-21 PERF OPTIMIZATION: limit latest_snap lookback to 13 weeks of forecast snapshots.
-- Pre-fix: 153M ForecastSnapshotWeekly × 100+ AsOfDates → huge intermediate JOIN.
-- Post-fix: only join snapshots within 13W of each AsOfDate → ~13× weekly snapshots scanned per AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.InventoryCurrent (dropped entity)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K' -- FG
),
asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE)) -- Giang Historical weekly 3 years
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate,
        DATEDIFF(day,
            DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1),
            DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1))
        ) AS HorizonDays
    FROM asof_dates
),
item_wh AS (
    SELECT DISTINCT ItemSku, WarehouseCode FROM _InventoryCurrent
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
-- Pre-limit ForecastSnapshotWeekly to last 13 weeks of snapshots (weekly cadence → ~13 rows per Item×WH)
fcst_recent AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonthDate,
        ForecastQty
    FROM InventoryHistory_Enh.ForecastSnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
      AND FiscalMonthDate IS NOT NULL
),
latest_snap AS (
    SELECT
        f.ItemSku, f.WarehouseCode, a.AsOfDate,
        MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a
         ON f.SnapshotDate <= a.AsOfDate
        AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)   -- only look back 13W of weekly snapshots
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
inventory_source AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotWeekEndingDate) AS LatestInventorySnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate >= DATEADD(week, -13, a.AsOfDate)
    WHERE isw.MakeBuyCode IS NOT NULL
       OR isw.SourceWarehouseCode IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
source_map AS (
    -- Reference: Inventory Health Dataset.sql #DPD.
    -- Buy/source-dependent demand is identified by MBX='X' and rolled to dinSource1.
    -- Collapse fiscal-month inventory rows to one mapping row per ItemSku + WarehouseCode + AsOfDate.
    -- Assumption: MakeBuyCode and SourceWarehouseCode are stable across the 3 fiscal months in scope.
    SELECT
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate,
        CAST(MAX(NULLIF(TRIM(isw.MakeBuyCode), '')) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(MAX(NULLIF(TRIM(isw.SourceWarehouseCode), '')) AS VARCHAR(50)) AS SourceWarehouseCode
    FROM inventory_source src
    JOIN InventoryHistory_Enh.InventorySnapshotWeekly isw
         ON isw.ItemSku = src.ItemSku
        AND isw.WarehouseCode = src.WarehouseCode
        AND isw.SnapshotWeekEndingDate = src.LatestInventorySnapshotDate
    GROUP BY
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate
),
forecast_components AS (
    -- Direct forecast demand stays at the forecast warehouse.
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        SUM(f.ForecastQty) AS ThreeMoForecastQty,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
         ON f.ItemSku = ls.ItemSku
        AND f.WarehouseCode = ls.WarehouseCode
        AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
         ON a.AsOfDate = ls.AsOfDate
        AND f.FiscalMonthDate >= a.HorizonStartDate
        AND f.FiscalMonthDate <  a.HorizonEndDate
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate

    UNION ALL

    -- Dependent demand rolls from buy/source-dependent warehouse to source warehouse.
    SELECT
        ls.ItemSku,
        CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)) AS WarehouseCode,
        ls.AsOfDate,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoForecastQty,
        SUM(f.ForecastQty) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
         ON f.ItemSku = ls.ItemSku
        AND f.WarehouseCode = ls.WarehouseCode
        AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
         ON a.AsOfDate = ls.AsOfDate
        AND f.FiscalMonthDate >= a.HorizonStartDate
        AND f.FiscalMonthDate <  a.HorizonEndDate
    JOIN source_map sm
         ON sm.ItemSku = f.ItemSku
        AND sm.WarehouseCode = f.WarehouseCode
        AND sm.AsOfDate = ls.AsOfDate
    WHERE TRIM(sm.MakeBuyCode) = 'X'
      AND NULLIF(TRIM(sm.SourceWarehouseCode), '') IS NOT NULL
    GROUP BY ls.ItemSku, CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)), ls.AsOfDate
),
demand_3mo AS (
    SELECT
        ItemSku,
        WarehouseCode,
        AsOfDate,
        SUM(ThreeMoForecastQty) AS ThreeMoForecastQty,
        SUM(ThreeMoDependentDemandQty) AS ThreeMoDependentDemandQty,
        SUM(ThreeMoForecastQty + ThreeMoDependentDemandQty) AS ThreeMoTotalDemandQty
    FROM forecast_components
    WHERE WarehouseCode IS NOT NULL
    GROUP BY ItemSku, WarehouseCode, AsOfDate
),
hist13w AS (
    SELECT
        TRIM(s.ItemSKU)      AS ItemSku,
        TRIM(s.WarehouseCode) AS WarehouseCode,
        a.AsOfDate,
        SUM(CAST(s.QtyShipped AS DECIMAL(18,4))) AS Hist13WQty
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel s
    JOIN asof a
        ON s.InvoiceDate > DATEADD(WEEK, -13, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    WHERE s.ItemSKU IS NOT NULL
      AND s.WarehouseCode IS NOT NULL
      AND TRIM(s.ItemSKU) <> ''
      AND TRIM(s.WarehouseCode) <> ''
      AND s.InvoiceDate IS NOT NULL
    GROUP BY
        TRIM(s.ItemSKU),
        TRIM(s.WarehouseCode),
        a.AsOfDate
)
SELECT
    CAST(iw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(iw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate        AS DATE)          AS AsOfDate,
    CAST(a.HorizonStartDate AS DATE)         AS HorizonStartDate,
    CAST(a.HorizonEndDate   AS DATE)         AS HorizonEndDate,
    CAST(a.HorizonDays      AS INT)          AS HorizonDays,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) AS DECIMAL(18,4)) AS ThreeMoForecastQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoTotalDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS Fwd13WForecastQty,
    CAST(ISNULL(h.Hist13WQty, 0) AS DECIMAL(18,4)) AS Hist13WShippedQty,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DailyFcstQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DependentDemandDailyQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS TotalDemandDailyQty,
    CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4)) AS Hist13WShippedDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / 13.0 AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 13.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
             AND ISNULL(d.ThreeMoDependentDemandQty, 0) > 0 THEN 'Forecast+Dependent'
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN 'Forecast'
        ELSE 'HistoricalFallback'
    END AS VARCHAR(20))                       AS AwdSource
FROM item_wh iw
CROSS JOIN asof a
LEFT JOIN demand_3mo d
       ON d.ItemSku = iw.ItemSku
      AND d.WarehouseCode = iw.WarehouseCode
      AND d.AsOfDate = a.AsOfDate
LEFT JOIN hist13w h
       ON h.ItemSku = iw.ItemSku
      AND h.WarehouseCode = iw.WarehouseCode
      AND h.AsOfDate = a.AsOfDate
WHERE COALESCE(d.ThreeMoTotalDemandQty, h.Hist13WQty) IS NOT NULL

GO

-- ---------------------------------------------------------------------
-- Last invoice: DA as-of behavior + direct Mart A invoice source.
-- ---------------------------------------------------------------------
-- ---- InventoryHistory_Enh.v_LastInvoiceHelper ----
-- MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(s.WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate          AS DATE)          AS AsOfDate,
    CAST(MAX(s.InvoiceDate)  AS DATE)          AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM (
    SELECT
        CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InvoiceDate         AS DATE)        AS InvoiceDate
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
    WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
      AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
      AND InvoiceDate IS NOT NULL
) s
JOIN asof a ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate

GO

-- ---------------------------------------------------------------------
-- Movement flag: DA as-of behavior + direct Mart A invoice source.
-- ---------------------------------------------------------------------
-- ---- InventoryHistory_Enh.v_MovementFlagHelper ----
-- HasMovementLast17W: InvoiceDetail as movement signal per BRD §6 (only sales count for SLOB).
CREATE OR ALTER VIEW InventoryHistory_Enh.v_MovementFlagHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
moves AS (
    SELECT
        s.ItemSku, s.WarehouseCode, a.AsOfDate,
        MAX(CASE WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                  AND s.InvoiceDate <= a.AsOfDate
                 THEN 1 ELSE 0 END) AS HasMovementLast17W,
        COUNT(*)                    AS MovementCountLast17W
    FROM (
        SELECT
            CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
            CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
            CAST(InvoiceDate         AS DATE)        AS InvoiceDate
        FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
        WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
          AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
          AND InvoiceDate IS NOT NULL
    ) s
    JOIN asof a
         ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(ItemSku                AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode          AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate               AS DATE)        AS AsOfDate,
    CAST(HasMovementLast17W     AS BIT)         AS HasMovementLast17W,
    CAST(MovementCountLast17W   AS INT)         AS MovementCountLast17W
FROM moves

GO


CREATE OR ALTER VIEW InventoryHistory_Enh.v_SafetyStockHelper AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   Safety stock target is normalized across the next 3 fiscal months.
--   Fallback to prior 13-week average only when fiscal-period safety stock is unavailable.
-- 2026-05-20 FIX (Giang #6): BRD says '13-week AVERAGE safety stock target', not latest.
-- Replaced ROW_NUMBER picking latest snapshot → AVG() across 13 weekly snapshots prior to AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate
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
        AND isw.SnapshotWeekEndingDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
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
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate
),
fallback_ss AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
keys AS (
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fiscal_ss
    UNION
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fallback_ss
)
SELECT
    CAST(k.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(k.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(k.AsOfDate       AS DATE)          AS AsOfDate,
    CAST(COALESCE(f.SafetyStockTarget, fb.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COALESCE(f.SnapshotCount, fb.SnapshotCount) AS INT) AS SnapshotCount,
    CAST(CASE WHEN f.SafetyStockTarget IS NOT NULL
              THEN 'Next3FiscalMonths'
              ELSE 'Historical13W'
         END AS VARCHAR(30)) AS SafetyStockSource
FROM keys k
LEFT JOIN fiscal_ss f
       ON f.ItemSku = k.ItemSku
      AND f.WarehouseCode = k.WarehouseCode
      AND f.AsOfDate = k.AsOfDate
LEFT JOIN fallback_ss fb
       ON fb.ItemSku = k.ItemSku
      AND fb.WarehouseCode = k.WarehouseCode
      AND fb.AsOfDate = k.AsOfDate

GO


-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ---- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily ----
CREATE OR ALTER VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily AS
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
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
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    WHERE r.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(PoNumber                        AS VARCHAR(50))  AS PoNumber,
    CAST(PoLine                          AS INT)          AS PoLine,
    CAST(VendorNumber                    AS VARCHAR(50))  AS VendorNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(StockQty                        AS DECIMAL(18,4)) AS StockQty,
    CAST(OrderedQty                      AS DECIMAL(18,4)) AS OrderedQty,
    CAST(InTransitQtySource              AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(POOnOrderQty                    AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(POInTransitQty                  AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(TotalOpenPOQty                  AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(EstimatedArrivalDate            AS DATE)         AS EstimatedArrivalDate,
    CAST(EstimatedDepartureDate          AS DATE)         AS EstimatedDepartureDate,
    CAST(SourceSystem                    AS VARCHAR(64))  AS SourceSystem,
    CAST(SourceTable                     AS VARCHAR(128)) AS SourceTable
FROM _PurchaseOrder

GO


-- ---- InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily ----
CREATE OR ALTER VIEW InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily AS
WITH _ManufacturingOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ManufacturingOrder
    SELECT
        CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END              AS DECIMAL(18,4))  AS MOOnOrderQty, --Giang: Confirm logic với Robert.
        CAST(ODUDT                        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(MoNumber                        AS VARCHAR(50))  AS MoNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(OrderQty                        AS DECIMAL(18,4)) AS OrderQty,
    CAST(ReceivedQty                     AS DECIMAL(18,4)) AS ReceivedQty,
    CAST(MOOnOrderQty                    AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM _ManufacturingOrder

GO


-- ---- InventoryHistory_Enh.v_HoldingTransferSnapshotDaily ----
CREATE OR ALTER VIEW InventoryHistory_Enh.v_HoldingTransferSnapshotDaily AS
WITH _HoldingTransfer AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.HoldingTransfer
    -- Reference: etl/Holding Transfers.sql.
    -- Business signal: same-warehouse transfer (HFHOUS = HTHOUS) is an on-hold candidate.
    -- Current metric keeps active/non-cancelled transfers for OnHoldQty compatibility.
    SELECT
        TransferNumber, ItemSku, WarehouseCode, SourceWarehouseCode, ReceivingWarehouseCode,
        ShipDateKey, ShipDate, ShipWeekEndingDate, DueDateKey, DueDate, DueWeekEndingDate,
        HeaderComment, DetailComment, TransferQty, ShippedQty, TotalShippedQty,
        ExpediteCode, FirmCode, TransferCube, HeaderStatus, CancelFlag
    FROM (
        SELECT
            TRIM(d.DTFRNO)                       AS TransferNumber,
            TRIM(d.DITNBR)                       AS ItemSku,
            TRIM(h.HFHOUS)                       AS WarehouseCode,
            TRIM(h.HFHOUS)                       AS SourceWarehouseCode,
            TRIM(h.HTHOUS)                       AS ReceivingWarehouseCode,
            CAST(h.HSHDTE AS INT)                AS ShipDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112) AS ShipDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) AS DATE) AS ShipWeekEndingDate,
            CAST(h.HDLDTE AS INT)                AS DueDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112) AS DueDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) AS DATE) AS DueWeekEndingDate,
            CAST(h.HTRCMT AS VARCHAR(200))       AS HeaderComment,
            CAST(d.DCOMNT AS VARCHAR(200))       AS DetailComment,
            CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
            CAST(d.DTSHPQ AS DECIMAL(18,4))      AS TotalShippedQty,
            CAST(d.DEXPED AS VARCHAR(20))        AS ExpediteCode,
            CAST(d.DFIRMC AS VARCHAR(20))        AS FirmCode,
            CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
            TRIM(h.HSTATS)                       AS HeaderStatus,
            TRIM(h.HCANCL)                       AS CancelFlag,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
                ORDER BY h.HDLDTE DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
        --   AND TRIM(h.HCANCL) = 'N'
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)        AS SnapshotDate,
    CAST(TransferNumber                  AS VARCHAR(50)) AS TransferNumber,
    CAST(ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS INT) AS TransferLine,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(SourceWarehouseCode             AS VARCHAR(50))  AS SourceWarehouseCode,
    CAST(ReceivingWarehouseCode          AS VARCHAR(50))  AS ReceivingWarehouseCode,
    CAST(ShipDateKey                     AS INT)          AS ShipDateKey,
    CAST(ShipDate                        AS DATE)         AS ShipDate,
    CAST(ShipWeekEndingDate              AS DATE)         AS ShipWeekEndingDate,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(DueWeekEndingDate               AS DATE)         AS DueWeekEndingDate,
    CAST(HeaderComment                   AS VARCHAR(200)) AS HeaderComment,
    CAST(DetailComment                   AS VARCHAR(200)) AS DetailComment,
    CAST(TransferQty                     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty                      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TotalShippedQty                 AS DECIMAL(18,4)) AS TotalShippedQty,
    CAST(ExpediteCode                    AS VARCHAR(20)) AS ExpediteCode,
    CAST(FirmCode                        AS VARCHAR(20)) AS FirmCode,
    CAST(TransferCube                    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus                    AS VARCHAR(10))  AS HeaderStatus,
    CAST(CancelFlag                      AS VARCHAR(10))  AS CancelFlag,
    CAST('Manufacturing_Inventory_AFI'   AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                 AS VARCHAR(128)) AS SourceTable
FROM _HoldingTransfer

GO


-- ---- InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly ----
-- WEEKLY — Saturday only (cron '0 6 * * 6' in registry).
-- Captures latest WeekEndingDate snapshot per (ItemSku, WarehouseCode).
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly AS
WITH _LogilityItemStatus AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.LogilityItemStatus
    SELECT ItemSku, WarehouseCode, WeekEndingDate, ItemStatus, FutureStatus, StatusChangeDate,
           OnHandQty, SafetyStockQty, ShippableInvQty, MonthsOfSupply, Price,
           ItemClass, Vendor, HoldBuyCode, IsCertified
    FROM (
        SELECT
            TRIM(Item)                            AS ItemSku,
            TRIM(Whse)                            AS WarehouseCode,
            CAST(WeekEnding AS DATE)              AS WeekEndingDate,
            TRIM(ItemStatus)                      AS ItemStatus,
            TRIM(FutureStatus)                    AS FutureStatus,
            CAST(StatusChngDate AS DATE)          AS StatusChangeDate,
            CAST(OnHandQty AS DECIMAL(18,4))      AS OnHandQty,
            CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
            CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
            CAST(MosofSupply AS DECIMAL(18,4))    AS MonthsOfSupply,
            CAST(Price AS DECIMAL(18,4))          AS Price,
            TRIM(ItemClass)                       AS ItemClass,
            TRIM(Vendor)                          AS Vendor,
            TRIM(HoldBuy)                         AS HoldBuyCode,
            CAST(1 AS BIT)                        AS IsCertified,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
                ORDER BY
                    CASE WHEN COALESCE(ShippableInvQty,0) = 0
                          AND COALESCE(FirmDemand,0) = 0 THEN 1 ELSE 0 END ASC,
                    StatusChngDate DESC,
                    COALESCE(OnHandAmt,0) DESC,
                    CAST(FileDate AS DATETIME2) DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandFulfillmentCommonContainer_Logility]
        WHERE Item IS NOT NULL AND Whse IS NOT NULL
          AND TRIM(Item) <> '' AND TRIM(Whse) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(DATEADD(day, (7 - DATEPART(weekday, SYSUTCDATETIME())) % 7,
                 CAST(SYSUTCDATETIME() AS DATE))  AS DATE)         AS WeekEndingDate,
    CAST(ItemSku                                  AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                            AS VARCHAR(50))  AS WarehouseCode,
    CAST(ItemStatus                               AS VARCHAR(20))  AS ItemStatus,
    CAST(FutureStatus                             AS VARCHAR(20))  AS FutureStatus,
    CAST(StatusChangeDate                         AS DATE)         AS StatusChangeDate,
    CAST(IsCertified                              AS BIT)          AS IsCertified,
    CAST('Enterprise_Lakehouse'                   AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility' AS VARCHAR(128)) AS SourceTable
FROM _LogilityItemStatus
WHERE WeekEndingDate = (
    SELECT MAX(WeekEndingDate) FROM _LogilityItemStatus
)

GO


-- ============================================================
-- §G. SC_LH workaround tables (DF2 → SC_LH; pending EL DE-team promote) — NEW 2026-05-19
--     Following forecast pattern: wire DF2 source into pipeline now, swap to EL later
-- ============================================================

CREATE OR ALTER VIEW InventoryHistory_Enh.v_ItemBalanceHistorical AS
-- Source: SC_LH.dbo.itembalance loaded via df_brz_ItemBalance (DF2 workaround pending EL.Inventory_Enh_History.ItemBalance promote)
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate); 107 dups detected → ROW_NUMBER dedupe by latest OnHandQty
-- History: 2021-03-06 → 2026-05-16 (5 years); not used as backup/backfill for v_InventorySnapshotWeekly
-- Future: when Dhivya promotes Enterprise.Inventory_Enh_History.ItemBalance, swap source_objects in registry
WITH ranked AS (
    SELECT
        TRIM(ItemNumber)                  AS ItemSku,
        TRIM(Warehouse)                   AS WarehouseCode,
        CAST(DateWeekEnding AS DATE)      AS WeekEndingDate,
        CAST(OnHandQty AS DECIMAL(18,4))  AS OnHandQty,
        TRIM(ItemStatus)                  AS ItemStatus,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(ItemNumber), TRIM(Warehouse), CAST(DateWeekEnding AS DATE)
            ORDER BY OnHandQty DESC, ItemStatus
        ) AS rn
    FROM [SupplyChain_Lakehouse].[dbo].[itembalance]
    WHERE ItemNumber IS NOT NULL AND Warehouse IS NOT NULL
      AND TRIM(ItemNumber) <> '' AND TRIM(Warehouse) <> ''
)
SELECT
    CAST(ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(WeekEndingDate     AS DATE)          AS WeekEndingDate,
    CAST(OnHandQty          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ItemStatus         AS VARCHAR(10))   AS ItemStatus,
    CAST('SupplyChain_Lakehouse'    AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.itembalance (DF2)'    AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO


CREATE OR ALTER VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical AS
-- Source: SC_LH.dbo.purchaseordersnapshot loaded via df_brz_PurchaseOrderSnapshot (DF2 workaround, 2B rows ⚠️)
-- Grain: (SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode)
-- Phase 2 PO-as-of feature: capture historical PO state by SnapshotDate
-- posDueDt is AS/400 CYYMMDD decimal (e.g., 1230130 = 2023-01-30)
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
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
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    WHERE r.rn = 1
)
SELECT
    CAST(posSnapshot AS DATE)                                 AS SnapshotDate,
    CAST(TRIM(posItNbr)             AS VARCHAR(50))           AS ItemSku,
    CAST(TRIM(posWhse)              AS VARCHAR(50))           AS WarehouseCode,
    CAST(TRIM(posVndnr)             AS VARCHAR(50))           AS VendorNumber,
    CAST(posQtyOr                   AS DECIMAL(18,4))         AS OrderedQty,
    CAST(TRIM(posPstts)             AS VARCHAR(10))           AS StatusCode,
    CAST(
        TRY_CAST(
            DATEFROMPARTS(
                1900 + 100 * (TRY_CAST(posDueDt AS INT) / 1000000) + ((TRY_CAST(posDueDt AS INT) % 1000000) / 10000),
                (TRY_CAST(posDueDt AS INT) % 10000) / 100,
                TRY_CAST(posDueDt AS INT) % 100
            ) AS DATE)                                        AS DATE)              AS DueDate,
    CAST(posUUD1PM                  AS DECIMAL(18,4))         AS UnitCost,
    CAST('SupplyChain_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.purchaseordersnapshot (DF2)'        AS VARCHAR(128)) AS SourceTable
FROM [SupplyChain_Lakehouse].[dbo].[purchaseordersnapshot]
WHERE posItNbr IS NOT NULL AND posWhse IS NOT NULL
  AND TRIM(posItNbr) <> '' AND TRIM(posWhse) <> ''

GO


-- ============================================================
-- END silver_views.sql
-- Total: 27 views (after §G additions 2026-05-19)
--   §A. ReferenceMaster_Enh: 1 view (Vendor NEW)
--   §B. InventoryHistory_Enh masters: 2 ext views (ItemMasterExt, WarehouseExt)
--   §C. InventoryHistory_Enh base: 12 views
--   §D. InventoryHistory_Enh snapshots: 2 views (incremental)
--   §E. InventoryHistory_Enh helpers: 4 views
--   §F. InventoryHistory_Enh self-snapshots: 4 views (datekey)
--   §G. InventoryHistory_Enh SC_LH workaround (DF2): 2 views (ItemBalanceHistorical active, PurchaseOrderSnapshotHistorical Phase 2)
-- ============================================================
