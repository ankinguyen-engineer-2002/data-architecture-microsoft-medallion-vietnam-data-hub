/*============================================================
  01_setup.sql — Inventory Health ETL infrastructure
  Run on: BOTH SupplyChain Processing Warehouse (silver) + Gold Warehouse (gold)

  Sections:
    A. Schemas
    B. EtlWatermark (silver only)
    C. Snapshot table DDLs (silver only — 4 daily/weekly snapshot capture tables)
============================================================*/

-- ========================================================
-- A. SCHEMAS
-- ========================================================
-- Run in SupplyChain Processing Warehouse:
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver AUTHORIZATION dbo;');
GO

-- Run in SupplyChain Gold Warehouse:
-- IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
--     EXEC('CREATE SCHEMA gold AUTHORIZATION dbo;');
-- GO


-- ========================================================
-- B. ETL WATERMARK (silver only)
-- ========================================================
IF OBJECT_ID('silver.EtlWatermark') IS NOT NULL DROP TABLE silver.EtlWatermark;
GO

CREATE TABLE silver.EtlWatermark (
    TableName               VARCHAR(128) NOT NULL,
    LastLoadDate            DATETIME2    NULL,
    LastSnapshotDate        DATE         NULL,
    LastInvoiceDate         DATE         NULL,
    LastTransactionDate     DATE         NULL,
    EtlBatchId              VARCHAR(64)  NULL,
    UpdatedAt               DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

ALTER TABLE silver.EtlWatermark
    ADD CONSTRAINT PK_silver_EtlWatermark
    PRIMARY KEY NONCLUSTERED (TableName) NOT ENFORCED;
GO

-- Seed initial watermarks (epoch start)
INSERT INTO silver.EtlWatermark (TableName, LastLoadDate, LastSnapshotDate, LastInvoiceDate, LastTransactionDate)
VALUES
    ('InventorySnapshotWeekly',    NULL, '1900-01-01', NULL, NULL),
    ('ForecastSnapshotWeekly',     NULL, '1900-01-01', NULL, NULL),
    ('SalesShipment',              NULL, NULL, '1900-01-01', NULL),
    ('MovementHistory',            NULL, NULL, NULL, '1900-01-01'),
    ('ItemBalanceHistory',         NULL, '1900-01-01', NULL, NULL);
GO


-- ========================================================
-- C. SNAPSHOT CAPTURE TABLE DDLs (silver, daily/weekly)
-- ========================================================

-- C.1 silver.PurchaseOrderSnapshotDaily
IF OBJECT_ID('silver.PurchaseOrderSnapshotDaily') IS NOT NULL DROP TABLE silver.PurchaseOrderSnapshotDaily;
GO
CREATE TABLE silver.PurchaseOrderSnapshotDaily (
    SnapshotDate              DATE         NOT NULL,
    PoNumber                  VARCHAR(50)  NOT NULL,
    PoLine                    INT          NOT NULL,
    VendorNumber              VARCHAR(50)  NULL,
    ItemSku                   VARCHAR(50)  NULL,
    WarehouseCode             VARCHAR(50)  NULL,
    StatusCode                INT          NULL,
    StockQty                  DECIMAL(18,4) NULL,
    OrderedQty                DECIMAL(18,4) NULL,
    InTransitQtySource        DECIMAL(18,4) NULL,
    POOnOrderQty              DECIMAL(18,4) NULL,
    POInTransitQty            DECIMAL(18,4) NULL,
    TotalOpenPOQty            DECIMAL(18,4) NULL,
    DueDate                   DATE         NULL,
    EstimatedArrivalDate      DATE         NULL,
    EstimatedDepartureDate    DATE         NULL,
    SourceSystem              VARCHAR(64)  NULL,
    SourceTable               VARCHAR(128) NULL,
    EtlLoadDate               DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
ALTER TABLE silver.PurchaseOrderSnapshotDaily
    ADD CONSTRAINT PK_silver_PurchaseOrderSnapshotDaily
    PRIMARY KEY NONCLUSTERED (SnapshotDate, PoNumber, PoLine) NOT ENFORCED;
GO


-- C.2 silver.ManufacturingOrderSnapshotDaily
IF OBJECT_ID('silver.ManufacturingOrderSnapshotDaily') IS NOT NULL DROP TABLE silver.ManufacturingOrderSnapshotDaily;
GO
CREATE TABLE silver.ManufacturingOrderSnapshotDaily (
    SnapshotDate              DATE         NOT NULL,
    MoNumber                  VARCHAR(50)  NOT NULL,
    ItemSku                   VARCHAR(50)  NOT NULL,
    WarehouseCode             VARCHAR(50)  NOT NULL,
    StatusCode                INT          NULL,
    OrderQty                  DECIMAL(18,4) NULL,
    ReceivedQty               DECIMAL(18,4) NULL,
    MOOnOrderQty              DECIMAL(18,4) NULL,
    DueDateKey                INT          NULL,
    SourceSystem              VARCHAR(64)  NULL,
    SourceTable               VARCHAR(128) NULL,
    EtlLoadDate               DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
ALTER TABLE silver.ManufacturingOrderSnapshotDaily
    ADD CONSTRAINT PK_silver_ManufacturingOrderSnapshotDaily
    PRIMARY KEY NONCLUSTERED (SnapshotDate, MoNumber, ItemSku, WarehouseCode) NOT ENFORCED;
GO


-- C.3 silver.HoldingTransferSnapshotDaily
IF OBJECT_ID('silver.HoldingTransferSnapshotDaily') IS NOT NULL DROP TABLE silver.HoldingTransferSnapshotDaily;
GO
CREATE TABLE silver.HoldingTransferSnapshotDaily (
    SnapshotDate              DATE         NOT NULL,
    TransferNumber            VARCHAR(50)  NOT NULL,
    TransferLine              INT          NOT NULL,
    ItemSku                   VARCHAR(50)  NULL,
    WarehouseCode             VARCHAR(50)  NULL,
    TransferQty               DECIMAL(18,4) NULL,
    ShippedQty                DECIMAL(18,4) NULL,
    TransferCube              DECIMAL(18,4) NULL,
    HeaderStatus              VARCHAR(10)  NULL,
    SourceSystem              VARCHAR(64)  NULL,
    SourceTable               VARCHAR(128) NULL,
    EtlLoadDate               DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
ALTER TABLE silver.HoldingTransferSnapshotDaily
    ADD CONSTRAINT PK_silver_HoldingTransferSnapshotDaily
    PRIMARY KEY NONCLUSTERED (SnapshotDate, TransferNumber, TransferLine) NOT ENFORCED;
GO


-- C.4 silver.LogilityItemStatusSnapshotWeekly
IF OBJECT_ID('silver.LogilityItemStatusSnapshotWeekly') IS NOT NULL DROP TABLE silver.LogilityItemStatusSnapshotWeekly;
GO
CREATE TABLE silver.LogilityItemStatusSnapshotWeekly (
    WeekEndingDate            DATE         NOT NULL,
    ItemSku                   VARCHAR(50)  NOT NULL,
    WarehouseCode             VARCHAR(50)  NOT NULL,
    ItemStatus                VARCHAR(20)  NULL,
    FutureStatus              VARCHAR(20)  NULL,
    StatusChangeDate          DATE         NULL,
    IsCertified               BIT          NOT NULL DEFAULT 1,
    SourceSystem              VARCHAR(64)  NULL,
    SourceTable               VARCHAR(128) NULL,
    EtlLoadDate               DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
ALTER TABLE silver.LogilityItemStatusSnapshotWeekly
    ADD CONSTRAINT PK_silver_LogilityItemStatusSnapshotWeekly
    PRIMARY KEY NONCLUSTERED (WeekEndingDate, ItemSku, WarehouseCode) NOT ENFORCED;
GO


PRINT '01_setup.sql complete: schemas + EtlWatermark + 4 snapshot tables created.';
GO
