/*============================================================
  06_gold_dims.sql — Gold dimensions
  Run on: SupplyChain Gold Warehouse
  Prerequisite: gold schema exists (uncomment in 01_setup.sql).

  5 dims:
    gold.DimDate          (from Enterprise.MasterData_DW.DimDate)
    gold.DimItem          (from silver.ItemMaster)
    gold.DimWarehouse     (from silver.Warehouse)
    gold.DimVendor        (from silver.Vendor)
    gold.DimRuleVersion   (manual config — single row Phase 1)
============================================================*/


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_DimDate
--   72 cols verified — pull subset for fact joining + slicer attrs
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_DimDate AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.DimDate_stg') IS NOT NULL DROP TABLE gold.DimDate_stg;

        CREATE TABLE gold.DimDate_stg AS
        SELECT
            CAST(FORMAT(d.DateID, 'yyyyMMdd') AS INT)         AS DateKey,
            d.DateID                                          AS CalendarDate,
            d.FiscalDate                                      AS FiscalDate,
            d.FiscalWeekLastDate                              AS WeekEndingDate,
            d.FiscalWeek                                      AS FiscalWeek,
            d.FiscalWeekIndicator                             AS FiscalWeekIndicator,
            d.FiscalMonth                                     AS FiscalMonth,
            d.FiscalMonthYear                                 AS FiscalMonthYear,
            CASE WHEN d.FiscalDate = CAST(SYSUTCDATETIME() AS DATE) THEN 1 ELSE 0 END AS IsCurrentDate,
            CASE WHEN d.FiscalWeekLastDate = (
                SELECT MAX(FiscalWeekLastDate)
                FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate]
                WHERE FiscalDate <= CAST(SYSUTCDATETIME() AS DATE)
            ) THEN 1 ELSE 0 END                                AS IsCurrentWeek,
            CASE WHEN d.FiscalDate = (
                SELECT MAX(FiscalDate)
                FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate] m
                WHERE m.FiscalMonthYear = d.FiscalMonthYear
            ) THEN 1 ELSE 0 END                                AS IsMonthEnd,
            SYSUTCDATETIME()                                  AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate] d;

        IF OBJECT_ID('gold.DimDate') IS NOT NULL DROP TABLE gold.DimDate;
        EXEC sp_rename 'gold.DimDate_stg', 'DimDate';

        ALTER TABLE gold.DimDate
            ADD CONSTRAINT PK_gold_DimDate
            PRIMARY KEY NONCLUSTERED (DateKey) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_DimItem
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_DimItem AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.DimItem_stg') IS NOT NULL DROP TABLE gold.DimItem_stg;

        CREATE TABLE gold.DimItem_stg AS
        SELECT
            im.ItemSku,
            im.ItemDescription,
            im.ItemClassCode,
            im.ItemClassName,
            im.CategoryName,
            im.CategoryCode,
            im.CollectiveClass,
            im.SeriesNumber,
            im.SeriesName,
            im.AfiItemStatus,
            CASE
                WHEN im.DiscontinuedFlag = 1     THEN 'Discontinued'
                WHEN im.AfiItemStatus = 'N'      THEN 'New'
                WHEN im.AfiItemStatus = 'A'      THEN 'Active'
                WHEN im.AfiItemStatus IN ('D','R') THEN 'Inactive'
                ELSE 'Other'
            END                                                AS LifecycleStatus,
            im.PrimaryVendorNumber,
            im.PrimaryVendorName,
            im.Cubes,
            im.FobArcPrice,
            im.IsFinishedGoodsItem,
            im.DiscontinuedFlag,
            im.NewItemFlag,
            im.StatusCodeChangeDate,
            im.UnavailableFlag,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [silver].[ItemMaster] im;
        -- NOTE: This proc runs on Gold WH. If silver is in Processing WH, replace with 3-part name:
        -- FROM [SupplyChain_Processing_Warehouse].[silver].[ItemMaster] im

        IF OBJECT_ID('gold.DimItem') IS NOT NULL DROP TABLE gold.DimItem;
        EXEC sp_rename 'gold.DimItem_stg', 'DimItem';

        ALTER TABLE gold.DimItem
            ADD CONSTRAINT PK_gold_DimItem
            PRIMARY KEY NONCLUSTERED (ItemSku) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_DimWarehouse
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_DimWarehouse AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.DimWarehouse_stg') IS NOT NULL DROP TABLE gold.DimWarehouse_stg;

        CREATE TABLE gold.DimWarehouse_stg AS
        SELECT
            w.WarehouseCode,
            w.WarehouseName,
            w.WarehouseType,
            w.WarehouseOrderGroup,
            w.WarehouseSourceId,
            w.SellableWarehouseFlag,
            w.ControlledFlag,
            w.WhereMadeCode,
            w.ManufacturingSite,
            w.IntransitWarehouseCode,
            w.IsFinishedGoodsWarehouse,
            w.IsManufacturingWarehouse,
            w.TotalAvailableWarehouseCube,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [silver].[Warehouse] w;

        IF OBJECT_ID('gold.DimWarehouse') IS NOT NULL DROP TABLE gold.DimWarehouse;
        EXEC sp_rename 'gold.DimWarehouse_stg', 'DimWarehouse';

        ALTER TABLE gold.DimWarehouse
            ADD CONSTRAINT PK_gold_DimWarehouse
            PRIMARY KEY NONCLUSTERED (WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_DimVendor
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_DimVendor AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.DimVendor_stg') IS NOT NULL DROP TABLE gold.DimVendor_stg;

        CREATE TABLE gold.DimVendor_stg AS
        SELECT
            v.VendorNumber,
            v.VendorName,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [silver].[Vendor] v;

        IF OBJECT_ID('gold.DimVendor') IS NOT NULL DROP TABLE gold.DimVendor;
        EXEC sp_rename 'gold.DimVendor_stg', 'DimVendor';

        ALTER TABLE gold.DimVendor
            ADD CONSTRAINT PK_gold_DimVendor
            PRIMARY KEY NONCLUSTERED (VendorNumber) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_DimRuleVersion (manual seed Phase 1)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_DimRuleVersion AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.DimRuleVersion') IS NOT NULL DROP TABLE gold.DimRuleVersion;

        CREATE TABLE gold.DimRuleVersion (
            RuleVersionKey      BIGINT NOT NULL,
            RuleName            VARCHAR(100) NULL,
            EffectiveStartDate  DATE NULL,
            EffectiveEndDate    DATE NULL,
            RuleDescription     VARCHAR(500) NULL,
            EtlLoadDate         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );

        INSERT INTO gold.DimRuleVersion (RuleVersionKey, RuleName, EffectiveStartDate, EffectiveEndDate, RuleDescription)
        VALUES
        (1, 'InventoryHealth_BRD_v1', '2026-01-01', NULL,
            'BRD v1 ruleset: Inactive=AfiStatus IN (D,R) AND OnHand+OnOrder=0; '
            'SLOB=AfiStatus<>N AND LastInvoice<AsOf-17W; Classification thresholds 0.5/1.5/17/52/104; '
            'AWD=13W forward forecast / 13 fallback 13W historical / 13; ATP=Week2');

        ALTER TABLE gold.DimRuleVersion
            ADD CONSTRAINT PK_gold_DimRuleVersion
            PRIMARY KEY NONCLUSTERED (RuleVersionKey) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '06_gold_dims.sql complete: 5 dim procs compiled.';
GO
