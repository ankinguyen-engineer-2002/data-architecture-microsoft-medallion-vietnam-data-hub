/*============================================================
  05_silver_snapshots.sql — Silver self-capture snapshot procs (Tier 4)
  Run on: SupplyChain Processing Warehouse
  Schedule:
    Daily:  usp_Snapshot_PurchaseOrder, _ManufacturingOrder, _HoldingTransfer
    Weekly (Saturday): usp_Snapshot_LogilityItemStatus
  All idempotent — rerun in same day deletes prior rows of that SnapshotDate first.
============================================================*/


-- ════════════════════════════════════════════════════════
-- silver.usp_Snapshot_PurchaseOrder
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Snapshot_PurchaseOrder AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @SnapshotDate DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.PurchaseOrderSnapshotDaily WHERE SnapshotDate = @SnapshotDate;

        INSERT INTO silver.PurchaseOrderSnapshotDaily (
            SnapshotDate, PoNumber, PoLine, VendorNumber,
            ItemSku, WarehouseCode, StatusCode,
            StockQty, OrderedQty, InTransitQtySource,
            POOnOrderQty, POInTransitQty, TotalOpenPOQty,
            DueDate, EstimatedArrivalDate, EstimatedDepartureDate,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            @SnapshotDate,
            PoNumber, PoLine, VendorNumber,
            ItemSku, WarehouseCode, StatusCode,
            StockQty, OrderedQty, InTransitQtySource,
            POOnOrderQty, POInTransitQty, TotalOpenPOQty,
            DueDate, EstimatedArrivalDate, EstimatedDepartureDate,
            SourceSystem, SourceTable, SYSUTCDATETIME()
        FROM silver.PurchaseOrder;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Snapshot_ManufacturingOrder
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Snapshot_ManufacturingOrder AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @SnapshotDate DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.ManufacturingOrderSnapshotDaily WHERE SnapshotDate = @SnapshotDate;

        INSERT INTO silver.ManufacturingOrderSnapshotDaily (
            SnapshotDate, MoNumber, ItemSku, WarehouseCode, StatusCode,
            OrderQty, ReceivedQty, MOOnOrderQty, DueDateKey,
            SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            @SnapshotDate,
            MoNumber, ItemSku, WarehouseCode, StatusCode,
            OrderQty, ReceivedQty, MOOnOrderQty, DueDateKey,
            CAST('Manufacturing_ProductionPlanning_AFI' AS VARCHAR(64)),
            CAST('MOMAST' AS VARCHAR(128)),
            SYSUTCDATETIME()
        FROM silver.ManufacturingOrder;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Snapshot_HoldingTransfer
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Snapshot_HoldingTransfer AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @SnapshotDate DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.HoldingTransferSnapshotDaily WHERE SnapshotDate = @SnapshotDate;

        INSERT INTO silver.HoldingTransferSnapshotDaily (
            SnapshotDate, TransferNumber, TransferLine,
            ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube,
            HeaderStatus, SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            @SnapshotDate,
            TransferNumber,
            ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS TransferLine,
            ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube,
            HeaderStatus,
            CAST('Manufacturing_Inventory_AFI' AS VARCHAR(64)),
            CAST('TFRDTL+TFRHDR' AS VARCHAR(128)),
            SYSUTCDATETIME()
        FROM silver.HoldingTransfer;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Snapshot_LogilityItemStatus (WEEKLY — Saturday only)
--   Snapshot semantically aligns with week-ending Saturday in BRD.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Snapshot_LogilityItemStatus AS
BEGIN
    SET XACT_ABORT ON;
    -- Use ISO week-ending Saturday
    DECLARE @SaturdayWE DATE = DATEADD(day,
        (7 - DATEPART(weekday, SYSUTCDATETIME())) % 7,
        CAST(SYSUTCDATETIME() AS DATE));

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM silver.LogilityItemStatusSnapshotWeekly WHERE WeekEndingDate = @SaturdayWE;

        INSERT INTO silver.LogilityItemStatusSnapshotWeekly (
            WeekEndingDate, ItemSku, WarehouseCode,
            ItemStatus, FutureStatus, StatusChangeDate,
            IsCertified, SourceSystem, SourceTable, EtlLoadDate
        )
        SELECT
            @SaturdayWE,
            ItemSku, WarehouseCode,
            ItemStatus, FutureStatus, StatusChangeDate,
            IsCertified,
            CAST('SupplyChain_Lakehouse' AS VARCHAR(64)),
            CAST('logility_demandfulfillment' AS VARCHAR(128)),
            SYSUTCDATETIME()
        FROM silver.LogilityItemStatus
        WHERE WeekEndingDate = (
            SELECT MAX(WeekEndingDate)
            FROM silver.LogilityItemStatus
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '05_silver_snapshots.sql complete: 4 snapshot capture procs compiled.';
GO
