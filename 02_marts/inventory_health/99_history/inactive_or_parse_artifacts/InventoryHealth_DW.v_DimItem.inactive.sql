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
