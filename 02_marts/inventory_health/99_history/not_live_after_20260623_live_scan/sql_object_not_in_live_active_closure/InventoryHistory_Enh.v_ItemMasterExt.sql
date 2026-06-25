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
