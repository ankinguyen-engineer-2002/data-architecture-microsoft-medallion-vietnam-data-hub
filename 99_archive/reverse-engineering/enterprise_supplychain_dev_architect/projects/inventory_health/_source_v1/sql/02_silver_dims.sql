/*============================================================
  02_silver_dims.sql — Silver dim helpers (Tier 0)
  Run on: SupplyChain Processing Warehouse
  All columns verified vs Lakehouse INFORMATION_SCHEMA on 2026-05-14.

  3 procs:
    silver.usp_Build_ItemMaster     (DimItemMaster + VendorMaster + ITBEXT.MFPUS)
    silver.usp_Build_Warehouse      (AshleyWarehouseMaster — no name col)
    silver.usp_Build_Vendor         (VendorMaster)
============================================================*/


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_ItemMaster
--   DimItemMaster (173 cols) — verified: ItemSKU, ItemDescription, ItemClassCode,
--     CollectiveClass, AFIItemStatus, PrimaryVendor, Cubes, FOBArcPrice,
--     DiscontinuedFlag, NewItemFlag, StatusCodeChangeDate
--   Series → use SeriesNumber + SeriesName
--   Category → no simple col; use RetailCategoryName
--   ITBEXT (50 cols) — ITNBR, HOUSE, MFPUS at top
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_ItemMaster AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.ItemMaster_stg') IS NOT NULL DROP TABLE silver.ItemMaster_stg;

        CREATE TABLE silver.ItemMaster_stg AS
        WITH unavailable AS (
            -- ITBEXT.MFPUS = 'U' → Unavailable Status flag at Item-WH grain
            SELECT
                LTRIM(RTRIM(ITNBR)) AS ItemSku,
                MAX(CASE WHEN LTRIM(RTRIM(MFPUS)) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
            FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
            WHERE ITNBR IS NOT NULL AND LTRIM(RTRIM(ITNBR)) <> ''
            GROUP BY LTRIM(RTRIM(ITNBR))
        )
        SELECT
            LTRIM(RTRIM(d.ItemSKU))                            AS ItemSku,
            CAST(d.ItemDescription AS VARCHAR(200))            AS ItemDescription,
            LTRIM(RTRIM(d.ItemClassCode))                      AS ItemClassCode,
            CAST(d.ItemClassName AS VARCHAR(100))              AS ItemClassName,
            CAST(d.RetailCategoryName AS VARCHAR(100))         AS CategoryName,
            CAST(d.RetailCategoryCode AS VARCHAR(50))          AS CategoryCode,
            CAST(d.CollectiveClass AS VARCHAR(50))             AS CollectiveClass,
            CAST(d.SeriesNumber AS VARCHAR(50))                AS SeriesNumber,
            CAST(d.SeriesName AS VARCHAR(100))                 AS SeriesName,
            CAST(d.SeriesDescription AS VARCHAR(200))          AS SeriesDescription,
            LTRIM(RTRIM(d.AFIItemStatus))                      AS AfiItemStatus,
            LTRIM(RTRIM(d.PrimaryVendor))                      AS PrimaryVendorNumber,
            CAST(v.VendorName AS VARCHAR(200))                 AS PrimaryVendorName,
            CAST(d.Cubes AS DECIMAL(18,4))                     AS Cubes,
            CAST(d.FOBArcPrice AS DECIMAL(18,4))               AS FobArcPrice,
            CASE
                WHEN LEFT(LTRIM(RTRIM(d.ItemClassCode)), 1) = 'Z'
                 AND RIGHT(LTRIM(RTRIM(d.ItemClassCode)), 1) = 'K'
                THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
            END                                                AS IsFinishedGoodsItem,
            CAST(d.DiscontinuedFlag AS BIT)                    AS DiscontinuedFlag,
            CAST(d.NewItemFlag AS BIT)                         AS NewItemFlag,
            CAST(d.StatusCodeChangeDate AS DATE)               AS StatusCodeChangeDate,
            CAST(ISNULL(u.UnavailableFlag, 0) AS BIT)          AS UnavailableFlag,
            CAST('MasterData_DW+ITBEXT' AS VARCHAR(64))        AS SourceSystem,
            CAST('DimItemMaster+ITBEXT(MFPUS)' AS VARCHAR(128)) AS SourceTable,
            SYSUTCDATETIME()                                   AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
        LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
               ON LTRIM(RTRIM(v.VendorNumber)) = LTRIM(RTRIM(d.PrimaryVendor))
        LEFT JOIN unavailable u
               ON u.ItemSku = LTRIM(RTRIM(d.ItemSKU))
        WHERE d.ItemSKU IS NOT NULL AND LTRIM(RTRIM(d.ItemSKU)) <> '';

        IF OBJECT_ID('silver.ItemMaster') IS NOT NULL DROP TABLE silver.ItemMaster;
        EXEC sp_rename 'silver.ItemMaster_stg', 'ItemMaster';

        ALTER TABLE silver.ItemMaster
            ADD CONSTRAINT PK_silver_ItemMaster
            PRIMARY KEY NONCLUSTERED (ItemSku) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_Warehouse
--   AshleyWarehouseMaster (29 cols) — NO warehouse-name column; use wmaWarehouse as code-only.
--   IntransitWarehouse pair, SellableWarehouse bit, WarehouseType verified.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_Warehouse AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.Warehouse_stg') IS NOT NULL DROP TABLE silver.Warehouse_stg;

        CREATE TABLE silver.Warehouse_stg AS
        SELECT
            LTRIM(RTRIM(w.wmaWarehouse))                              AS WarehouseCode,
            LTRIM(RTRIM(w.wmaWarehouse))                              AS WarehouseName,   -- no name col available
            CAST(w.wmaWarehouseType AS VARCHAR(100))                  AS WarehouseType,
            CAST(w.wmaWarehouseOrderGroup AS VARCHAR(50))             AS WarehouseOrderGroup,
            CAST(w.wmaWarehouseSourceId AS VARCHAR(50))               AS WarehouseSourceId,
            CAST(w.wmaSellableWarehouse AS BIT)                       AS SellableWarehouseFlag,
            CAST(w.wmaControlled AS BIT)                              AS ControlledFlag,
            CAST(w.wmaWhereMade AS VARCHAR(50))                       AS WhereMadeCode,
            CAST(w.wmaManufacturingSite AS VARCHAR(50))               AS ManufacturingSite,
            LTRIM(RTRIM(w.wmaIntransitWarehouse))                     AS IntransitWarehouseCode,
            CASE WHEN LTRIM(RTRIM(w.wmaWarehouse))
                      IN ('1','5','15','17','28','335','ECR')
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END           AS IsFinishedGoodsWarehouse,
            CASE WHEN LTRIM(RTRIM(w.wmaWarehouse))
                      NOT IN ('1','5','15','17','28','335','ECR')
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END           AS IsManufacturingWarehouse,
            -- B3: WH exclusion list (direct-to-customer / RP) — from sếp's PurchaseOrderSnapshot query
            CASE WHEN LTRIM(RTRIM(w.wmaWarehouse))
                      IN ('C','CNW','AF','IOR','C35','55','MAX')
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END           AS IsExcludedDirectCustomerRP,
            -- Extended network list (matrix v3 alt): for total-network inventory context
            CASE WHEN LTRIM(RTRIM(w.wmaWarehouse))
                      IN ('1','5','15','17','28','42','ECR','3','12','16','19')
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END           AS IsNetworkInventoryWarehouse,
            CAST(NULL AS DECIMAL(18,4))                               AS TotalAvailableWarehouseCube,
            CAST('Wholesale_Codis_AFI' AS VARCHAR(64))                AS SourceSystem,
            CAST('AshleyWarehouseMaster' AS VARCHAR(128))             AS SourceTable,
            SYSUTCDATETIME()                                          AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster] w
        WHERE w.wmaWarehouse IS NOT NULL AND LTRIM(RTRIM(w.wmaWarehouse)) <> '';

        IF OBJECT_ID('silver.Warehouse') IS NOT NULL DROP TABLE silver.Warehouse;
        EXEC sp_rename 'silver.Warehouse_stg', 'Warehouse';

        ALTER TABLE silver.Warehouse
            ADD CONSTRAINT PK_silver_Warehouse
            PRIMARY KEY NONCLUSTERED (WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_Vendor
--   VendorMaster (51 cols, 86,598 rows) — VendorNumber + VendorName verified.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_Vendor AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.Vendor_stg') IS NOT NULL DROP TABLE silver.Vendor_stg;

        CREATE TABLE silver.Vendor_stg AS
        SELECT
            LTRIM(RTRIM(v.VendorNumber))                              AS VendorNumber,
            CAST(v.VendorName AS VARCHAR(200))                        AS VendorName,
            CAST('Purchasing_AFI' AS VARCHAR(64))                     AS SourceSystem,
            CAST('VendorMaster' AS VARCHAR(128))                      AS SourceTable,
            SYSUTCDATETIME()                                          AS EtlLoadDate
        FROM [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
        WHERE v.VendorNumber IS NOT NULL AND LTRIM(RTRIM(v.VendorNumber)) <> '';

        IF OBJECT_ID('silver.Vendor') IS NOT NULL DROP TABLE silver.Vendor;
        EXEC sp_rename 'silver.Vendor_stg', 'Vendor';

        ALTER TABLE silver.Vendor
            ADD CONSTRAINT PK_silver_Vendor
            PRIMARY KEY NONCLUSTERED (VendorNumber) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '02_silver_dims.sql complete: 3 dim helper procs (verified columns).';
GO
