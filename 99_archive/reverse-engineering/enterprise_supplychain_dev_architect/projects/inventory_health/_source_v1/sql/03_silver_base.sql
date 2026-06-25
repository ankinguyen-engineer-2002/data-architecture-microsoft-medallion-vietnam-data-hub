/*============================================================
  03_silver_base.sql — Silver base tables (Tier 1 + Tier 2)
  Run on: SupplyChain Processing Warehouse
  All columns verified vs INFORMATION_SCHEMA on 2026-05-14.

  Note on PoDetail: Enterprise.Wholesale_ProductSourcing_AFI.PoDetail still 0 rows.
  Phase 1 uses SupplyChain_Lakehouse.dbo.podetail_v2 + dbo.pomaster via cross-DB.
  When Enterprise is reloaded, swap source path in usp_Build_PurchaseOrder.

  Note on ItemBalanceHistory: schema does NOT exist on lake. Use
  silver.InventorySnapshotWeekly (from DemandInventorySnapshotWeekly) as historical
  primary source. Switch to ItemBalanceHistory when DE loads it.
============================================================*/


-- ════════════════════════════════════════════════════════
-- 4. silver.usp_Build_CostCurrent (ITMRVA dedupe STID+ITNBR, STID='000')
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_CostCurrent AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.CostCurrent_stg') IS NOT NULL DROP TABLE silver.CostCurrent_stg;

        CREATE TABLE silver.CostCurrent_stg AS
        WITH ranked AS (
            SELECT
                LTRIM(RTRIM(ITNBR))                AS ItemSku,
                LTRIM(RTRIM(STID))                 AS CostId,
                CAST(UCDEF AS DECIMAL(18,4))       AS StandardCost,
                CAST(ITRV AS VARCHAR(20))          AS ItemRevision,
                ROW_NUMBER() OVER (
                    PARTITION BY LTRIM(RTRIM(STID)), LTRIM(RTRIM(ITNBR))
                    ORDER BY ITRV DESC
                ) AS rn
            FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
            WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
              AND LTRIM(RTRIM(STID))  = '000'
              AND LTRIM(RTRIM(ITNBR)) <> ''
        )
        SELECT
            ItemSku, CostId, StandardCost, ItemRevision,
            CAST('ItemMaster_AFI' AS VARCHAR(64))      AS SourceSystem,
            CAST('ITMRVA(STID=000)' AS VARCHAR(128))   AS SourceTable,
            SYSUTCDATETIME()                           AS EtlLoadDate
        FROM ranked WHERE rn = 1;

        IF OBJECT_ID('silver.CostCurrent') IS NOT NULL DROP TABLE silver.CostCurrent;
        EXEC sp_rename 'silver.CostCurrent_stg', 'CostCurrent';

        ALTER TABLE silver.CostCurrent
            ADD CONSTRAINT PK_silver_CostCurrent
            PRIMARY KEY NONCLUSTERED (ItemSku) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 5. silver.usp_Build_InventoryCurrent (ITEMBL daily append, MOHTQ)
-- ════════════════════════════════════════════════════════
IF OBJECT_ID('silver.InventoryCurrent') IS NULL
BEGIN
    CREATE TABLE silver.InventoryCurrent (
        ItemSku        VARCHAR(50)  NOT NULL,
        WarehouseCode  VARCHAR(50)  NOT NULL,
        OnHandQty      DECIMAL(18,4) NULL,
        ItemClassCode  VARCHAR(50)  NULL,
        SnapshotDate   DATE         NOT NULL,
        SourceSystem   VARCHAR(64)  NULL,
        SourceTable    VARCHAR(128) NULL,
        EtlLoadDate    DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
    );

    ALTER TABLE silver.InventoryCurrent
        ADD CONSTRAINT PK_silver_InventoryCurrent
        PRIMARY KEY NONCLUSTERED (SnapshotDate, ItemSku, WarehouseCode) NOT ENFORCED;
END;
GO

CREATE OR ALTER PROCEDURE silver.usp_Build_InventoryCurrent AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @SnapshotDate DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.InventoryCurrent WHERE SnapshotDate = @SnapshotDate;

        INSERT INTO silver.InventoryCurrent (
            ItemSku, WarehouseCode, OnHandQty, ItemClassCode,
            SnapshotDate, SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            LTRIM(RTRIM(b.ITNBR))                AS ItemSku,
            LTRIM(RTRIM(b.HOUSE))                AS WarehouseCode,
            CAST(b.MOHTQ AS DECIMAL(18,4))       AS OnHandQty,    -- NOT PHYOH (dead)
            LTRIM(RTRIM(b.ITCLS))                AS ItemClassCode,
            @SnapshotDate                        AS SnapshotDate,
            CAST('ItemMaster_AFI' AS VARCHAR(64))   AS SourceSystem,
            CAST('ITEMBL' AS VARCHAR(128))          AS SourceTable,
            SYSUTCDATETIME()                     AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
        WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
          AND LTRIM(RTRIM(b.ITNBR)) <> ''
          AND LTRIM(RTRIM(b.HOUSE)) <> ''
          -- H3 FIX (2026-05-17): FG-only scope per BRD §6.5 / sheet R21
          -- ITEMBL has 558K items but DimItemMaster only 32% match. FG filter → 99.98% match.
          AND LEFT(LTRIM(RTRIM(b.ITCLS)), 1) = 'Z'
          AND RIGHT(LTRIM(RTRIM(b.ITCLS)), 1) = 'K'
          -- B3 FIX (2026-05-17): exclude direct-to-customer/RP warehouses (from sếp's PurchaseOrderSnapshot code)
          AND LTRIM(RTRIM(b.HOUSE)) NOT IN ('C','CNW','AF','IOR','C35','55','MAX');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 6. silver.usp_Build_SupplyPlan (SupplyPlanDetail — all 13 cols verified)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_SupplyPlan AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.SupplyPlan_stg') IS NOT NULL DROP TABLE silver.SupplyPlan_stg;

        CREATE TABLE silver.SupplyPlan_stg AS
        SELECT
            LTRIM(RTRIM(spdItem))                              AS ItemSku,
            LTRIM(RTRIM(spdWarehouse))                         AS WarehouseCode,
            CAST(dtea AS DATE)                                 AS SnapshotDate,
            CAST(spdWeekEnding AS DATE)                        AS WeekEndingDate,
            CAST(spdBeginingBalance AS DECIMAL(18,4))          AS BeginningBalanceQty,
            CAST(spdFirmDemands AS DECIMAL(18,4))              AS FirmDemandQty,
            CAST(spdNetForecast AS DECIMAL(18,4))              AS NetForecastQty,
            CAST(spdFirmPurchaseOrders AS DECIMAL(18,4))       AS FirmPurchaseOrderQty,
            CAST(spdPlannedPurchaseOrders AS DECIMAL(18,4))    AS PlannedPurchaseOrderQty,
            CAST(spdOnOrderTransferIn AS DECIMAL(18,4))        AS OnOrderTransferInQty,
            CAST(spdShippableInventory AS DECIMAL(18,4))       AS ShippableInventoryQty,
            CAST(spdSafetyStock AS DECIMAL(18,4))              AS SafetyStockTargetQty,
            CAST(spdMonthsOfSupply AS DECIMAL(18,4))           AS MonthsOfSupply,
            CASE WHEN spdShippableInventory < 0
                 THEN ABS(CAST(spdShippableInventory AS DECIMAL(18,4)))
                 ELSE 0 END                                    AS SINegQty,
            CAST('Wholesale_DemandPlanning_AFI' AS VARCHAR(64))   AS SourceSystem,
            CAST('SupplyPlanDetail' AS VARCHAR(128))              AS SourceTable,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
        WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
          AND LTRIM(RTRIM(spdItem)) <> '' AND LTRIM(RTRIM(spdWarehouse)) <> '';

        IF OBJECT_ID('silver.SupplyPlan') IS NOT NULL DROP TABLE silver.SupplyPlan;
        EXEC sp_rename 'silver.SupplyPlan_stg', 'SupplyPlan';

        ALTER TABLE silver.SupplyPlan
            ADD CONSTRAINT PK_silver_SupplyPlan
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, SnapshotDate, WeekEndingDate) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 7. silver.usp_Build_SalesShipment (InvoiceDetail incremental by InvoiceDate)
--    Real cols: InvoiceNumber(2) + ItemSequence(4) = PK; Warehouse(12) not WarehouseCode
-- ════════════════════════════════════════════════════════
IF OBJECT_ID('silver.SalesShipment') IS NULL
BEGIN
    CREATE TABLE silver.SalesShipment (
        InvoiceNumber    DECIMAL(18,0) NOT NULL,
        ItemSequence     DECIMAL(18,0) NOT NULL,
        ItemSku          VARCHAR(50)  NULL,
        WarehouseCode    VARCHAR(50)  NULL,
        InvoiceDate      DATE         NULL,
        OrderDate        DATE         NULL,
        QuantityShipped  DECIMAL(18,4) NULL,
        QuantityOrdered  DECIMAL(18,4) NULL,
        Price            DECIMAL(18,4) NULL,
        SourceSystem     VARCHAR(64)  NULL,
        SourceTable      VARCHAR(128) NULL,
        EtlLoadDate      DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
    );
    ALTER TABLE silver.SalesShipment
        ADD CONSTRAINT PK_silver_SalesShipment
        PRIMARY KEY NONCLUSTERED (InvoiceNumber, ItemSequence) NOT ENFORCED;
END;
GO

CREATE OR ALTER PROCEDURE silver.usp_Build_SalesShipment AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @LastInv DATE = (
        SELECT ISNULL(LastInvoiceDate, '1900-01-01')
        FROM silver.EtlWatermark WHERE TableName = 'SalesShipment'
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.SalesShipment WHERE InvoiceDate > @LastInv;

        INSERT INTO silver.SalesShipment (
            InvoiceNumber, ItemSequence, ItemSku, WarehouseCode,
            InvoiceDate, OrderDate, QuantityShipped, QuantityOrdered, Price,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            CAST(InvoiceNumber AS DECIMAL(18,0))   AS InvoiceNumber,
            CAST(ItemSequence  AS DECIMAL(18,0))   AS ItemSequence,
            LTRIM(RTRIM(ItemSKU))                  AS ItemSku,
            LTRIM(RTRIM(Warehouse))                AS WarehouseCode,
            CAST(InvoiceDate AS DATE)              AS InvoiceDate,
            CAST(OrderDate AS DATE)                AS OrderDate,
            CAST(QuantityShipped AS DECIMAL(18,4)) AS QuantityShipped,
            CAST(QuantityOrdered AS DECIMAL(18,4)) AS QuantityOrdered,
            CAST(Price AS DECIMAL(18,4))           AS Price,
            CAST('SalesHistory_AFI' AS VARCHAR(64))     AS SourceSystem,
            CAST('InvoiceDetail' AS VARCHAR(128))       AS SourceTable,
            SYSUTCDATETIME()                       AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail]
        WHERE CAST(InvoiceDate AS DATE) > @LastInv
          AND ItemSKU IS NOT NULL AND Warehouse IS NOT NULL
          AND LTRIM(RTRIM(ItemSKU)) <> '' AND LTRIM(RTRIM(Warehouse)) <> '';

        UPDATE silver.EtlWatermark
        SET LastInvoiceDate = (SELECT MAX(InvoiceDate) FROM silver.SalesShipment),
            LastLoadDate    = SYSUTCDATETIME(),
            UpdatedAt       = SYSUTCDATETIME()
        WHERE TableName = 'SalesShipment';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 8. silver.usp_Build_PurchaseOrder
--    B1 FIX (2026-05-17): Switched source SupplyChain.dbo.podetail_v2 → Enterprise.PoDetail
--    DE loaded Enterprise.Wholesale_ProductSourcing_AFI.PoDetail (21.95M rows).
--    PoMaster still on SC (Enterprise.PoMaster not yet loaded — chase DE).
--    Real cols: poditemnum (NOT poditem); podstatuscode is VARCHAR.
--    B3: WH exclusion list applied (direct-to-customer/RP).
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_PurchaseOrder AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.PurchaseOrder_stg') IS NOT NULL DROP TABLE silver.PurchaseOrder_stg;

        CREATE TABLE silver.PurchaseOrder_stg AS
        WITH ranked AS (
            SELECT
                LTRIM(RTRIM(podordernum))               AS PoNumber,
                CAST(poditemsequence AS INT)            AS PoLine,
                LTRIM(RTRIM(podvendornum))              AS VendorNumber,
                LTRIM(RTRIM(poditemnum))                AS ItemSku,
                LTRIM(RTRIM(podwarehouse))              AS WarehouseCode,
                CAST(podstatuscode AS VARCHAR(10))      AS StatusCode,
                CAST(podstockqty AS DECIMAL(18,4))      AS StockQty,
                CAST(podqtyordered AS DECIMAL(18,4))    AS OrderedQty,
                CAST(podIntransitQty AS DECIMAL(18,4))  AS InTransitQtySource,
                CAST(podduedate AS DATE)                AS DueDate,
                ROW_NUMBER() OVER (
                    PARTITION BY LTRIM(RTRIM(podordernum)),
                                 LTRIM(RTRIM(podvendornum)),
                                 poditemsequence
                    ORDER BY podduedate DESC
                ) AS rn
            FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]   -- B1 FIX: switched to Enterprise
            WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
              AND LTRIM(RTRIM(poditemnum)) <> '' AND LTRIM(RTRIM(podwarehouse)) <> ''
              -- B3: WH exclusion list (direct-to-customer/RP)
              AND LTRIM(RTRIM(podwarehouse)) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
        )
        SELECT
            r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
            r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
            CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS POOnOrderQty,
            CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS POInTransitQty,
            CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS TotalOpenPOQty,
            CAST(h.pometa AS DATE)                AS EstimatedArrivalDate,
            CAST(h.pometd AS DATE)                AS EstimatedDepartureDate,
            CAST(h.pomdue AS DATE)                AS PromisedReceiptDate,
            CAST(h.pomcontainer AS VARCHAR(50))   AS ContainerNumber,
            CAST(h.pomtotalcubes AS DECIMAL(18,4)) AS TotalCubes,
            CAST('Enterprise+SupplyChain' AS VARCHAR(64))                       AS SourceSystem,
            CAST('PoDetail(Ent) + pomaster(SC)' AS VARCHAR(128))                AS SourceTable,
            SYSUTCDATETIME()                                        AS EtlLoadDate
        FROM ranked r
        LEFT JOIN [SupplyChain_Lakehouse].[dbo].[pomaster] h    -- TODO: switch to Enterprise.PoMaster when DE loads
               ON LTRIM(RTRIM(h.pomordernum))  = r.PoNumber
              AND LTRIM(RTRIM(h.pomvendornum)) = r.VendorNumber
        WHERE r.rn = 1;

        IF OBJECT_ID('silver.PurchaseOrder') IS NOT NULL DROP TABLE silver.PurchaseOrder;
        EXEC sp_rename 'silver.PurchaseOrder_stg', 'PurchaseOrder';

        ALTER TABLE silver.PurchaseOrder
            ADD CONSTRAINT PK_silver_PurchaseOrder
            PRIMARY KEY NONCLUSTERED (PoNumber, PoLine) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 9. silver.usp_Build_ManufacturingOrder (MOMAST — OSTAT is varchar)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_ManufacturingOrder AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.ManufacturingOrder_stg') IS NOT NULL DROP TABLE silver.ManufacturingOrder_stg;

        CREATE TABLE silver.ManufacturingOrder_stg AS
        SELECT
            LTRIM(RTRIM(ORDNO))                  AS MoNumber,
            LTRIM(RTRIM(FITEM))                  AS ItemSku,
            LTRIM(RTRIM(FITWH))                  AS WarehouseCode,
            LTRIM(RTRIM(OSTAT))                  AS StatusCode,
            CAST(ORQTY AS DECIMAL(18,4))         AS OrderQty,
            CAST(QTYRC AS DECIMAL(18,4))         AS ReceivedQty,
            CASE WHEN LTRIM(RTRIM(OSTAT)) IN ('10', '40', '45')
                 THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                 ELSE 0
            END                                  AS MOOnOrderQty,
            CAST(ODUDT AS INT)                   AS DueDateKey,
            CAST('Manufacturing_ProductionPlanning_AFI' AS VARCHAR(64))  AS SourceSystem,
            CAST('MOMAST' AS VARCHAR(128))                              AS SourceTable,
            SYSUTCDATETIME()                     AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
        WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
          AND LTRIM(RTRIM(FITEM)) <> ''
          AND LTRIM(RTRIM(FITWH)) <> '';

        IF OBJECT_ID('silver.ManufacturingOrder') IS NOT NULL DROP TABLE silver.ManufacturingOrder;
        EXEC sp_rename 'silver.ManufacturingOrder_stg', 'ManufacturingOrder';

        ALTER TABLE silver.ManufacturingOrder
            ADD CONSTRAINT PK_silver_ManufacturingOrder
            PRIMARY KEY NONCLUSTERED (MoNumber, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 10. silver.usp_Build_LogilityItemStatus (SC dbo.logility_demandfulfillment)
--     53 cols rich source — extract status + OnHand/Safety/Shippable
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_LogilityItemStatus AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.LogilityItemStatus_stg') IS NOT NULL DROP TABLE silver.LogilityItemStatus_stg;

        CREATE TABLE silver.LogilityItemStatus_stg AS
        WITH ranked AS (
            SELECT
                LTRIM(RTRIM(Item))                  AS ItemSku,
                LTRIM(RTRIM(Whse))                  AS WarehouseCode,
                CAST(WeekEnding AS DATE)            AS WeekEndingDate,
                LTRIM(RTRIM(ItemStatus))            AS ItemStatus,
                LTRIM(RTRIM(FutureStatus))          AS FutureStatus,
                CAST(StatusChngDate AS DATE)        AS StatusChangeDate,
                CAST(OnHandQty AS DECIMAL(18,4))    AS OnHandQty,
                CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
                CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
                CAST(MosofSupply AS DECIMAL(18,4))  AS MonthsOfSupply,
                CAST(Price AS DECIMAL(18,4))        AS Price,
                LTRIM(RTRIM(ItemClass))             AS ItemClass,
                LTRIM(RTRIM(Vendor))                AS Vendor,
                LTRIM(RTRIM(HoldBuy))               AS HoldBuyCode,
                ROW_NUMBER() OVER (
                    PARTITION BY LTRIM(RTRIM(Item)),
                                 LTRIM(RTRIM(Whse)),
                                 CAST(WeekEnding AS DATE)
                    ORDER BY StatusChngDate DESC
                ) AS rn
            FROM [SupplyChain_Lakehouse].[dbo].[logility_demandfulfillment]
            WHERE Item IS NOT NULL AND Whse IS NOT NULL
              AND LTRIM(RTRIM(Item)) <> '' AND LTRIM(RTRIM(Whse)) <> ''
        )
        SELECT
            ItemSku, WarehouseCode, WeekEndingDate,
            ItemStatus, FutureStatus, StatusChangeDate,
            OnHandQty, SafetyStockQty, ShippableInvQty, MonthsOfSupply,
            Price, ItemClass, Vendor, HoldBuyCode,
            CAST(1 AS BIT)                          AS IsCertified,
            CAST('SupplyChain_Lakehouse' AS VARCHAR(64))                AS SourceSystem,
            CAST('logility_demandfulfillment' AS VARCHAR(128))          AS SourceTable,
            SYSUTCDATETIME()                        AS EtlLoadDate
        FROM ranked WHERE rn = 1;

        IF OBJECT_ID('silver.LogilityItemStatus') IS NOT NULL DROP TABLE silver.LogilityItemStatus;
        EXEC sp_rename 'silver.LogilityItemStatus_stg', 'LogilityItemStatus';

        ALTER TABLE silver.LogilityItemStatus
            ADD CONSTRAINT PK_silver_LogilityItemStatus
            PRIMARY KEY NONCLUSTERED (WeekEndingDate, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 11. silver.usp_Build_HoldingTransfer (TFRDTL + TFRHDR)
--     TFRDTL has 19 cols; assume DTFRNO+DITNBR composite or synthetic PK.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_HoldingTransfer AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.HoldingTransfer_stg') IS NOT NULL DROP TABLE silver.HoldingTransfer_stg;

        CREATE TABLE silver.HoldingTransfer_stg AS
        WITH ranked AS (
            SELECT
                LTRIM(RTRIM(d.DTFRNO))                AS TransferNumber,
                LTRIM(RTRIM(d.DITNBR))                AS ItemSku,
                LTRIM(RTRIM(h.HFHOUS))                AS WarehouseCode,
                CAST(d.DTFRQT AS DECIMAL(18,4))       AS TransferQty,
                CAST(d.DSHPQT AS DECIMAL(18,4))       AS ShippedQty,
                CAST(d.DCUBES AS DECIMAL(18,4))       AS TransferCube,
                LTRIM(RTRIM(h.HSTATS))                AS HeaderStatus,
                LTRIM(RTRIM(h.HCANCL))                AS CancelFlag,
                CAST(h.HSHDTE AS INT)                 AS ShipDateKey,
                CAST(h.HDLDTE AS INT)                 AS DueDateKey,
                ROW_NUMBER() OVER (
                    PARTITION BY LTRIM(RTRIM(d.DTFRNO)), LTRIM(RTRIM(d.DITNBR))
                    ORDER BY h.HDLDTE DESC
                ) AS rn
            FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
            JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
                 ON LTRIM(RTRIM(d.DTFRNO)) = LTRIM(RTRIM(h.HTFRNO))
            WHERE LTRIM(RTRIM(h.HFHOUS)) = LTRIM(RTRIM(h.HTHOUS))
              AND LTRIM(RTRIM(h.HCANCL)) = 'N'
              AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
              AND LTRIM(RTRIM(d.DITNBR)) <> '' AND LTRIM(RTRIM(h.HFHOUS)) <> ''
        )
        SELECT
            TransferNumber, ItemSku, WarehouseCode,
            TransferQty, ShippedQty, TransferCube,
            HeaderStatus, CancelFlag, ShipDateKey, DueDateKey,
            CAST('Manufacturing_Inventory_AFI' AS VARCHAR(64))   AS SourceSystem,
            CAST('TFRDTL+TFRHDR' AS VARCHAR(128))                AS SourceTable,
            SYSUTCDATETIME()                                     AS EtlLoadDate
        FROM ranked WHERE rn = 1;

        IF OBJECT_ID('silver.HoldingTransfer') IS NOT NULL DROP TABLE silver.HoldingTransfer;
        EXEC sp_rename 'silver.HoldingTransfer_stg', 'HoldingTransfer';

        ALTER TABLE silver.HoldingTransfer
            ADD CONSTRAINT PK_silver_HoldingTransfer
            PRIMARY KEY NONCLUSTERED (TransferNumber, ItemSku) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 12. silver.usp_Build_AtpWeekEnding
--     H2 FIX (2026-05-17): ATPSUM real schema = 43 APAT cols (APAT01-43) but only 1 APWK col
--     (APWK01 = base week-ending date in YYYYMMDD decimal format, e.g. 20260517 = Saturday 2026-05-17).
--     Plan v3 wrong: tried UNPIVOT APWK01-27 (don't exist).
--     New logic: UNPIVOT APAT01-43 only; derive WeekEndingDate = APWK01 (parsed) + (n-1)*7 days.
--     For ATP In-Stock Rate KPI #23: filter WeekNumber=2 per Aric/Robert chốt "Week2".
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_AtpWeekEnding AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.AtpWeekEnding_stg') IS NOT NULL DROP TABLE silver.AtpWeekEnding_stg;

        CREATE TABLE silver.AtpWeekEnding_stg AS
        WITH base AS (
            SELECT
                LTRIM(RTRIM(APITNB)) AS ItemSku,
                LTRIM(RTRIM(APHOUS)) AS WarehouseCode,
                -- APWK01 stored as decimal YYYYMMDD; parse → DATE
                TRY_CAST(CAST(CAST(APWK01 AS BIGINT) AS VARCHAR(8)) AS DATE) AS BaseWeekEndingDate
            FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
            WHERE APITNB IS NOT NULL AND APHOUS IS NOT NULL
              AND LTRIM(RTRIM(APITNB)) <> '' AND LTRIM(RTRIM(APHOUS)) <> ''
        ),
        unpiv AS (
            SELECT LTRIM(RTRIM(APITNB)) AS ItemSku,
                   LTRIM(RTRIM(APHOUS)) AS WarehouseCode,
                   CAST(REPLACE(WeekCol, 'APAT', '') AS INT) AS WeekNumber,
                   CAST(AtpQty AS DECIMAL(18,4)) AS AtpQty
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
            u.ItemSku, u.WarehouseCode, u.WeekNumber,
            -- WeekEnding = BaseWeekEndingDate + (n-1)*7 days
            DATEADD(week, u.WeekNumber - 1, b.BaseWeekEndingDate) AS WeekEndingDate,
            u.AtpQty,
            CAST('Wholesale_Purchasing_AFI' AS VARCHAR(64))  AS SourceSystem,
            CAST('ATPSUM(UNPIVOT APAT01-43)' AS VARCHAR(128)) AS SourceTable,
            SYSUTCDATETIME()                                 AS EtlLoadDate
        FROM unpiv u
        JOIN base b ON b.ItemSku = u.ItemSku AND b.WarehouseCode = u.WarehouseCode
        WHERE b.BaseWeekEndingDate IS NOT NULL;

        IF OBJECT_ID('silver.AtpWeekEnding') IS NOT NULL DROP TABLE silver.AtpWeekEnding;
        EXEC sp_rename 'silver.AtpWeekEnding_stg', 'AtpWeekEnding';

        ALTER TABLE silver.AtpWeekEnding
            ADD CONSTRAINT PK_silver_AtpWeekEnding
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, WeekNumber) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 13. silver.usp_Build_MovementHistory (IMHIST incremental by TRNDT)
--     TRNDT is decimal (date key encoded YYYYMMDD); join DimDate via DateID
-- ════════════════════════════════════════════════════════
IF OBJECT_ID('silver.MovementHistory') IS NULL
BEGIN
    CREATE TABLE silver.MovementHistory (
        ItemSku           VARCHAR(50)  NOT NULL,
        WarehouseCode     VARCHAR(50)  NOT NULL,
        TransactionDateKey DECIMAL(18,0) NOT NULL,
        TransactionDate   DATE         NULL,
        TCode             VARCHAR(10)  NOT NULL,
        TransactionQty    DECIMAL(18,4) NULL,
        PriorOnHandQty    DECIMAL(18,4) NULL,
        NewOnHandQty      DECIMAL(18,4) NULL,
        VendorNumber      VARCHAR(50)  NULL,
        SourceSystem      VARCHAR(64)  NULL,
        SourceTable       VARCHAR(128) NULL,
        EtlLoadDate       DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
    );
    ALTER TABLE silver.MovementHistory
        ADD CONSTRAINT PK_silver_MovementHistory
        PRIMARY KEY NONCLUSTERED (TransactionDateKey, ItemSku, WarehouseCode, TCode) NOT ENFORCED;
END;
GO

CREATE OR ALTER PROCEDURE silver.usp_Build_MovementHistory AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @LastTrn DATE = (
        SELECT ISNULL(LastTransactionDate, '1900-01-01')
        FROM silver.EtlWatermark WHERE TableName = 'MovementHistory'
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.MovementHistory WHERE TransactionDate > @LastTrn;

        INSERT INTO silver.MovementHistory (
            ItemSku, WarehouseCode, TransactionDateKey, TransactionDate, TCode,
            TransactionQty, PriorOnHandQty, NewOnHandQty, VendorNumber,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            LTRIM(RTRIM(im.ITNBR))                AS ItemSku,
            LTRIM(RTRIM(im.HOUSE))                AS WarehouseCode,
            CAST(im.TRNDT AS DECIMAL(18,0))       AS TransactionDateKey,
            d.FiscalDate                          AS TransactionDate,
            LTRIM(RTRIM(im.TCODE))                AS TCode,
            CAST(im.TRQTY AS DECIMAL(18,4))       AS TransactionQty,
            CAST(im.PRQOH AS DECIMAL(18,4))       AS PriorOnHandQty,
            CAST(im.NUQOH AS DECIMAL(18,4))       AS NewOnHandQty,
            LTRIM(RTRIM(im.VNDNR))                AS VendorNumber,
            CAST('Manufacturing_Inventory_AFI' AS VARCHAR(64))  AS SourceSystem,
            CAST('IMHIST' AS VARCHAR(128))                      AS SourceTable,
            SYSUTCDATETIME()                      AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[IMHIST] im
        LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] d
               ON d.DateID = CAST(im.TRNDT AS DATE)
        WHERE im.ITNBR IS NOT NULL AND im.HOUSE IS NOT NULL
          AND LTRIM(RTRIM(im.ITNBR)) <> '' AND LTRIM(RTRIM(im.HOUSE)) <> ''
          AND d.FiscalDate > @LastTrn;

        UPDATE silver.EtlWatermark
        SET LastTransactionDate = (SELECT MAX(TransactionDate) FROM silver.MovementHistory),
            LastLoadDate = SYSUTCDATETIME(),
            UpdatedAt    = SYSUTCDATETIME()
        WHERE TableName = 'MovementHistory';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 14. silver.usp_Build_AllocatedDemandCandidate
--     OpenOrderDetail (66 cols) + OpenOrderHeader (15)
--     Use PromiseDate (col 10) as planned ship date (RequestedShipDate not present)
--     PK: synthetic via ROW_NUMBER (no obvious line col in detail)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_AllocatedDemandCandidate AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.AllocatedDemandCandidate_stg') IS NOT NULL DROP TABLE silver.AllocatedDemandCandidate_stg;

        CREATE TABLE silver.AllocatedDemandCandidate_stg AS
        SELECT
            LTRIM(RTRIM(d.OrderNumber))                       AS OrderNumber,
            ROW_NUMBER() OVER (
                PARTITION BY LTRIM(RTRIM(d.OrderNumber))
                ORDER BY d.LoadDate DESC, d.PromiseDate DESC
            )                                                  AS OrderLine,
            LTRIM(RTRIM(d.ItemSKU))                           AS ItemSku,
            LTRIM(RTRIM(d.Warehouse))                         AS WarehouseCode,
            CAST(d.PromiseDate AS DATE)                       AS PromiseDate,
            CAST(d.LoadDate AS DATE)                          AS LoadDate,
            CAST(d.MaterialRequestDate AS DATE)               AS MaterialRequestDate,
            CAST(d.QuantityBackOrdered AS DECIMAL(18,4))      AS AllocatedDemandQty,
            CAST(d.QuantityShipped AS DECIMAL(18,4))          AS QuantityShipped,
            CAST(d.ItemAllocationFlag AS DECIMAL(18,4))       AS ItemAllocationFlag,
            LTRIM(RTRIM(h.CustomerNumber))                    AS CustomerNumber,
            CAST(h.OrderDate AS DATE)                         AS OrderDate,
            CAST('CustomerOrders_AFI' AS VARCHAR(64))         AS SourceSystem,
            CAST('OpenOrderDetail+Header' AS VARCHAR(128))    AS SourceTable,
            SYSUTCDATETIME()                                  AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
        LEFT JOIN [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderHeader] h
               ON LTRIM(RTRIM(h.OrderNumber)) = LTRIM(RTRIM(d.OrderNumber))
        -- H1 FIX (2026-05-17): probe shows real values = {0: 16,802 rows; 2: 901,411 rows} — no value 1.
        -- "Allocated" = ItemAllocationFlag = 2 (not 1). Robert sign-off pending.
        WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
          AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
          AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
          AND LTRIM(RTRIM(d.ItemSKU)) <> '' AND LTRIM(RTRIM(d.Warehouse)) <> '';

        IF OBJECT_ID('silver.AllocatedDemandCandidate') IS NOT NULL DROP TABLE silver.AllocatedDemandCandidate;
        EXEC sp_rename 'silver.AllocatedDemandCandidate_stg', 'AllocatedDemandCandidate';

        ALTER TABLE silver.AllocatedDemandCandidate
            ADD CONSTRAINT PK_silver_AllocatedDemandCandidate
            PRIMARY KEY NONCLUSTERED (OrderNumber, OrderLine) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- 15. silver.usp_Build_ForecastCurrent
--     B2 FIX (2026-05-17): Switched source.
--     OLD: SupplyForecast (7-col thin schema, FCST_1_ID/FCST_2_ID semantic unclear)
--     NEW: Wholesale_DemandPlanning_AFI.DemandForecast (23 cols, 12.27M rows, FRESH today,
--          36 fiscal months forward, channel split via DfcCustomerGroups+dfcFCSTTypeCode+dfcMgmtCode).
--     Replaces stale DemandForecastSnapshotWeekly (last 2024-03-25, stale 2.1 years).
--     Grain: (ItemSku, WarehouseCode, FiscalMonth) — monthly forecast values.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_ForecastCurrent AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.ForecastCurrent_stg') IS NOT NULL DROP TABLE silver.ForecastCurrent_stg;

        CREATE TABLE silver.ForecastCurrent_stg AS
        SELECT
            LTRIM(RTRIM(dfcItem))                              AS ItemSku,
            LTRIM(RTRIM(dfcWarehouse))                         AS WarehouseCode,
            CAST(dfcFiscalMonth AS INT)                        AS FiscalMonthYear,  -- YYYYMM int
            -- SUM across channels (DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode)
            SUM(CAST(dfcResultantForecast AS DECIMAL(18,4)))   AS ForecastQty,
            SUM(CAST(dfcPromotionalLift AS DECIMAL(18,4)))     AS PromoLiftQty,
            SUM(CAST(dfcForcedForecast AS DECIMAL(18,4)))      AS ForcedForecastQty,
            SUM(CAST(dfcOrderFutureQty AS DECIMAL(18,4)))      AS OrderFutureQty,
            CAST(MAX(dfcSnapshot) AS DATE)                     AS SourceSnapshotDate,
            CAST('Wholesale_DemandPlanning_AFI' AS VARCHAR(64))    AS SourceSystem,
            CAST('DemandForecast (channel SUM)' AS VARCHAR(128))   AS SourceTable,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[DemandForecast]
        WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
          AND LTRIM(RTRIM(dfcItem)) <> '' AND LTRIM(RTRIM(dfcWarehouse)) <> ''
        GROUP BY
            LTRIM(RTRIM(dfcItem)),
            LTRIM(RTRIM(dfcWarehouse)),
            CAST(dfcFiscalMonth AS INT);

        IF OBJECT_ID('silver.ForecastCurrent') IS NOT NULL DROP TABLE silver.ForecastCurrent;
        EXEC sp_rename 'silver.ForecastCurrent_stg', 'ForecastCurrent';

        ALTER TABLE silver.ForecastCurrent
            ADD CONSTRAINT PK_silver_ForecastCurrent
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, FiscalMonthYear) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- TIER 2 — large snapshot procs (sequential)
-- ════════════════════════════════════════════════════════

-- 16. silver.usp_Build_InventorySnapshotWeekly (557M rows, dinSnapshot=week-end)
IF OBJECT_ID('silver.InventorySnapshotWeekly') IS NULL
BEGIN
    CREATE TABLE silver.InventorySnapshotWeekly (
        ItemSku            VARCHAR(50)   NOT NULL,
        WarehouseCode      VARCHAR(50)   NOT NULL,
        SnapshotDate       DATE          NOT NULL,
        OnHandQty          DECIMAL(18,4) NULL,
        SafetyStockTarget  DECIMAL(18,4) NULL,
        IOSafetyStock      DECIMAL(18,4) NULL,
        OrderQty           DECIMAL(18,4) NULL,
        BuildQty           DECIMAL(18,4) NULL,
        SourceSystem       VARCHAR(64)   NULL,
        SourceTable        VARCHAR(128)  NULL,
        EtlLoadDate        DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
    ALTER TABLE silver.InventorySnapshotWeekly
        ADD CONSTRAINT PK_silver_InventorySnapshotWeekly
        PRIMARY KEY NONCLUSTERED (SnapshotDate, ItemSku, WarehouseCode) NOT ENFORCED;
END;
GO

CREATE OR ALTER PROCEDURE silver.usp_Build_InventorySnapshotWeekly AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @LastSnap DATE = (
        SELECT ISNULL(LastSnapshotDate, '1900-01-01')
        FROM silver.EtlWatermark WHERE TableName = 'InventorySnapshotWeekly'
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.InventorySnapshotWeekly WHERE SnapshotDate > @LastSnap;

        INSERT INTO silver.InventorySnapshotWeekly (
            ItemSku, WarehouseCode, SnapshotDate, OnHandQty,
            SafetyStockTarget, IOSafetyStock, OrderQty, BuildQty,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT ItemSku, WarehouseCode, SnapshotDate, OnHandQty,
               SafetyStockTarget, IOSafetyStock, OrderQty, BuildQty,
               SourceSystem, SourceTable, EtlLoadDate
        FROM (
            SELECT
                LTRIM(RTRIM(dinItem))                    AS ItemSku,
                LTRIM(RTRIM(dinWarehouse))               AS WarehouseCode,
                CAST(dinSnapshot AS DATE)                AS SnapshotDate,
                CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
                CAST(dinSafetyStock AS DECIMAL(18,4))    AS SafetyStockTarget,
                CAST(dinIOSafetyStock AS DECIMAL(18,4))  AS IOSafetyStock,
                CAST(dinOrderQuantity AS DECIMAL(18,4))  AS OrderQty,
                CAST(dinBuildQuantity AS DECIMAL(18,4))  AS BuildQty,
                CAST('SupplyChain_Enh_1' AS VARCHAR(64))                AS SourceSystem,
                CAST('DemandInventorySnapshotWeekly' AS VARCHAR(128))   AS SourceTable,
                SYSUTCDATETIME() AS EtlLoadDate,
                ROW_NUMBER() OVER (
                    PARTITION BY LTRIM(RTRIM(dinItem)),
                                 LTRIM(RTRIM(dinWarehouse)),
                                 CAST(dinSnapshot AS DATE)
                    ORDER BY dinSnapshot DESC
                ) AS rn
            FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotWeekly]
            WHERE CAST(dinSnapshot AS DATE) > @LastSnap
              AND dinItem IS NOT NULL AND dinWarehouse IS NOT NULL
        ) ranked
        WHERE rn = 1;

        UPDATE silver.EtlWatermark
        SET LastSnapshotDate = (SELECT MAX(SnapshotDate) FROM silver.InventorySnapshotWeekly),
            LastLoadDate     = SYSUTCDATETIME(),
            UpdatedAt        = SYSUTCDATETIME()
        WHERE TableName = 'InventorySnapshotWeekly';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- 17. silver.usp_Build_ForecastSnapshotWeekly
--     dfcSnapshot IS the week-ending (no separate dfcWeekEnding col).
--     Channel split exists: DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode → SUM.
IF OBJECT_ID('silver.ForecastSnapshotWeekly') IS NULL
BEGIN
    CREATE TABLE silver.ForecastSnapshotWeekly (
        ItemSku         VARCHAR(50)   NOT NULL,
        WarehouseCode   VARCHAR(50)   NOT NULL,
        WeekEndingDate  DATE          NOT NULL,
        ForecastQty     DECIMAL(18,4) NULL,
        PermComptQty    DECIMAL(18,4) NULL,
        SourceSystem    VARCHAR(64)   NULL,
        SourceTable     VARCHAR(128)  NULL,
        EtlLoadDate     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
    ALTER TABLE silver.ForecastSnapshotWeekly
        ADD CONSTRAINT PK_silver_ForecastSnapshotWeekly
        PRIMARY KEY NONCLUSTERED (WeekEndingDate, ItemSku, WarehouseCode) NOT ENFORCED;
END;
GO

CREATE OR ALTER PROCEDURE silver.usp_Build_ForecastSnapshotWeekly AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @LastSnap DATE = (
        SELECT ISNULL(LastSnapshotDate, '1900-01-01')
        FROM silver.EtlWatermark WHERE TableName = 'ForecastSnapshotWeekly'
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.ForecastSnapshotWeekly WHERE WeekEndingDate > @LastSnap;

        INSERT INTO silver.ForecastSnapshotWeekly (
            ItemSku, WarehouseCode, WeekEndingDate,
            ForecastQty, PermComptQty,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            LTRIM(RTRIM(dfcItem))                          AS ItemSku,
            LTRIM(RTRIM(dfcWarehouse))                     AS WarehouseCode,
            CAST(dfcSnapshot AS DATE)                      AS WeekEndingDate,
            -- SUM across channel splits (DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode)
            SUM(CAST(dfcResultantForecast AS DECIMAL(18,4))) AS ForecastQty,
            SUM(CAST(dfcPermComptQty AS DECIMAL(18,4)))      AS PermComptQty,
            CAST('SupplyChain_Enh_1' AS VARCHAR(64))                   AS SourceSystem,
            CAST('DemandForecastSnapshotWeekly' AS VARCHAR(128))       AS SourceTable,
            SYSUTCDATETIME()                               AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotWeekly]
        WHERE CAST(dfcSnapshot AS DATE) > @LastSnap
          AND dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
        GROUP BY
            LTRIM(RTRIM(dfcItem)),
            LTRIM(RTRIM(dfcWarehouse)),
            CAST(dfcSnapshot AS DATE);

        UPDATE silver.EtlWatermark
        SET LastSnapshotDate = (SELECT MAX(WeekEndingDate) FROM silver.ForecastSnapshotWeekly),
            LastLoadDate     = SYSUTCDATETIME(),
            UpdatedAt        = SYSUTCDATETIME()
        WHERE TableName = 'ForecastSnapshotWeekly';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '03_silver_base.sql complete: 14 base procs compiled (real columns verified).';
GO
