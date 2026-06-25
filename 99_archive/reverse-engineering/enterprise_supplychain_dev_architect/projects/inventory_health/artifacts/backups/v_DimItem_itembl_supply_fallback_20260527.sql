-- ---- InventoryHealth_DW.v_DimItem ----
-- Derived from _ItemMasterExt + computed LifecycleStatus.
-- Schema matches deliverable v1 gold.DimItem (downstream DAX measures depend on these cols).
CREATE OR ALTER VIEW InventoryHealth_DW.v_DimItem AS
WITH _ItemMasterExt AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ItemMasterExt
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
            WHEN LEFT(TRIM(d.ItemClassCode),1) = 'Z' AND RIGHT(TRIM(d.ItemClassCode),1) = 'K'
            THEN 1 ELSE 0 END AS BIT)                          AS IsFinishedGoodsItem,
        CAST(d.DiscontinuedFlag             AS BIT)            AS DiscontinuedFlag,
        CAST(d.NewItemFlag                  AS BIT)            AS NewItemFlag,
        CAST(d.StatusCodeChangeDate         AS DATE)           AS StatusCodeChangeDate,
        CAST(ISNULL(u.UnavailableFlag, 0)   AS BIT)            AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
    LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
           ON TRIM(v.VendorNumber) = TRIM(d.PrimaryVendor)
    LEFT JOIN (
        SELECT TRIM(ITNBR) AS ItemSku,
               MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
        WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
        GROUP BY TRIM(ITNBR)
    ) u ON u.ItemSku = TRIM(d.ItemSKU)
    WHERE d.ItemSKU IS NOT NULL AND TRIM(d.ItemSKU) <> ''
),
_CurrentSupplyItems AS (
    SELECT ItemSku
    FROM (
        SELECT ItemSku
        FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
        WHERE SnapshotDate = (
            SELECT MAX(SnapshotDate)
            FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
        )
        GROUP BY ItemSku, WarehouseCode
        HAVING SUM(CAST(POOnOrderQty AS DECIMAL(38,4))) <> 0
            OR SUM(CAST(POInTransitQty AS DECIMAL(38,4))) <> 0

        UNION

        SELECT ItemSku
        FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
        WHERE SnapshotDate = (
            SELECT MAX(SnapshotDate)
            FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
        )
        GROUP BY ItemSku, WarehouseCode
        HAVING SUM(CAST(MOOnOrderQty AS DECIMAL(38,4))) <> 0
    ) s
    GROUP BY ItemSku
),
_ItemblFallback AS (
    SELECT
        CAST(TRIM(b.ITNBR) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(b.ITNBR) AS VARCHAR(200)) AS ItemDescription,
        CAST(MAX(TRIM(b.ITCLS)) AS VARCHAR(50)) AS ItemClassCode,
        CAST('Unknown' AS VARCHAR(100)) AS ItemClassName,
        CAST('Unknown' AS VARCHAR(100)) AS CategoryName,
        CAST(NULL AS VARCHAR(50)) AS CategoryCode,
        CAST(NULL AS VARCHAR(50)) AS CollectiveClass,
        CAST(NULL AS VARCHAR(50)) AS SeriesNumber,
        CAST(NULL AS VARCHAR(100)) AS SeriesName,
        CAST(NULL AS VARCHAR(200)) AS SeriesDescription,
        CAST('UNK' AS VARCHAR(10)) AS AfiItemStatus,
        CAST(NULL AS VARCHAR(50)) AS PrimaryVendorNumber,
        CAST(NULL AS VARCHAR(200)) AS PrimaryVendorName,
        CAST(NULL AS DECIMAL(18,4)) AS Cubes,
        CAST(NULL AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(CASE WHEN LEFT(MAX(TRIM(b.ITCLS)),1) = 'Z' AND RIGHT(MAX(TRIM(b.ITCLS)),1) = 'K'
                  THEN 1 ELSE 0 END AS BIT) AS IsFinishedGoodsItem,
        CAST(0 AS BIT) AS DiscontinuedFlag,
        CAST(0 AS BIT) AS NewItemFlag,
        CAST(NULL AS DATE) AS StatusCodeChangeDate,
        CAST(ISNULL(MAX(u.UnavailableFlag), 0) AS BIT) AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    JOIN _CurrentSupplyItems s
      ON s.ItemSku = TRIM(b.ITNBR)
    LEFT JOIN _ItemMasterExt im
      ON im.ItemSku = TRIM(b.ITNBR)
    LEFT JOIN (
        SELECT TRIM(ITNBR) AS ItemSku,
               MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
        WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
        GROUP BY TRIM(ITNBR)
    ) u ON u.ItemSku = TRIM(b.ITNBR)
    WHERE b.ITNBR IS NOT NULL AND TRIM(b.ITNBR) <> ''
      AND im.ItemSku IS NULL
    GROUP BY TRIM(b.ITNBR)
)
SELECT
    CAST(im.ItemSku                AS VARCHAR(50))    AS ItemSku,
    CAST(im.ItemDescription        AS VARCHAR(200))   AS ItemDescription,
    CAST(im.ItemClassCode          AS VARCHAR(50))    AS ItemClassCode,
    CAST(im.ItemClassName          AS VARCHAR(100))   AS ItemClassName,
    CAST(im.CategoryName           AS VARCHAR(100))   AS CategoryName,
    CAST(im.CategoryCode           AS VARCHAR(50))    AS CategoryCode,
    CAST(im.CollectiveClass        AS VARCHAR(50))    AS CollectiveClass,
    CAST(im.SeriesNumber           AS VARCHAR(50))    AS SeriesNumber,
    CAST(im.SeriesName             AS VARCHAR(100))   AS SeriesName,
    CAST(im.AfiItemStatus          AS VARCHAR(10))    AS AfiItemStatus,
    CAST(CASE
        WHEN im.DiscontinuedFlag = 1      THEN 'Discontinued'
        WHEN im.AfiItemStatus = 'N'       THEN 'New'
        WHEN im.AfiItemStatus = 'A'       THEN 'Active'
        WHEN im.AfiItemStatus IN ('D','R') THEN 'Inactive'
        ELSE 'Other'
    END AS VARCHAR(20))                              AS LifecycleStatus,
    CAST(im.PrimaryVendorNumber    AS VARCHAR(50))    AS PrimaryVendorNumber,
    CAST(im.PrimaryVendorName      AS VARCHAR(200))   AS PrimaryVendorName,
    CAST(im.Cubes                  AS DECIMAL(18,4))  AS Cubes,
    CAST(im.FobArcPrice            AS DECIMAL(18,4))  AS FobArcPrice,
    CAST(im.IsFinishedGoodsItem    AS BIT)            AS IsFinishedGoodsItem,
    CAST(im.DiscontinuedFlag       AS BIT)            AS DiscontinuedFlag,
    CAST(im.NewItemFlag            AS BIT)            AS NewItemFlag,
    CAST(im.StatusCodeChangeDate   AS DATE)           AS StatusCodeChangeDate,
    CAST(im.UnavailableFlag        AS BIT)            AS UnavailableFlag
FROM _ItemMasterExt im
UNION ALL
SELECT
    CAST(fb.ItemSku                AS VARCHAR(50))    AS ItemSku,
    CAST(fb.ItemDescription        AS VARCHAR(200))   AS ItemDescription,
    CAST(fb.ItemClassCode          AS VARCHAR(50))    AS ItemClassCode,
    CAST(fb.ItemClassName          AS VARCHAR(100))   AS ItemClassName,
    CAST(fb.CategoryName           AS VARCHAR(100))   AS CategoryName,
    CAST(fb.CategoryCode           AS VARCHAR(50))    AS CategoryCode,
    CAST(fb.CollectiveClass        AS VARCHAR(50))    AS CollectiveClass,
    CAST(fb.SeriesNumber           AS VARCHAR(50))    AS SeriesNumber,
    CAST(fb.SeriesName             AS VARCHAR(100))   AS SeriesName,
    CAST(fb.AfiItemStatus          AS VARCHAR(10))    AS AfiItemStatus,
    CAST('Unknown'                 AS VARCHAR(20))    AS LifecycleStatus,
    CAST(fb.PrimaryVendorNumber    AS VARCHAR(50))    AS PrimaryVendorNumber,
    CAST(fb.PrimaryVendorName      AS VARCHAR(200))   AS PrimaryVendorName,
    CAST(fb.Cubes                  AS DECIMAL(18,4))  AS Cubes,
    CAST(fb.FobArcPrice            AS DECIMAL(18,4))  AS FobArcPrice,
    CAST(fb.IsFinishedGoodsItem    AS BIT)            AS IsFinishedGoodsItem,
    CAST(fb.DiscontinuedFlag       AS BIT)            AS DiscontinuedFlag,
    CAST(fb.NewItemFlag            AS BIT)            AS NewItemFlag,
    CAST(fb.StatusCodeChangeDate   AS DATE)           AS StatusCodeChangeDate,
    CAST(fb.UnavailableFlag        AS BIT)            AS UnavailableFlag
FROM _ItemblFallback fb
