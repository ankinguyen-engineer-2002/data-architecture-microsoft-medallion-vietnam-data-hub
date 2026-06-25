-- ---- Shared_DW.v_DimWarehouse ----
-- 2026-05-29: moved from mart-specific ForecastAccuracy_DW / InventoryHealth_DW
-- to Shared_DW. Superset grain is one row per WarehouseCode.
-- 2026-05-29: WarehouseLocation is a report display label, not D/W type.
-- Preserve D/W in WarehouseType from AshleyWarehouseMaster.
CREATE VIEW Shared_DW.v_DimWarehouse AS
WITH fa AS (
    SELECT
        CAST(TRIM(WarehouseCode) AS VARCHAR(50))             AS WarehouseCode,
        CAST(AFIWarehousesKey AS INT)                        AS AFIWarehousesKey,
        CAST(TRIM(IntransitWarehouse) AS VARCHAR(50))        AS IntransitWarehouse,
        CAST(TRIM(ContainerDirectWarehouse) AS VARCHAR(50))  AS ContainerDirectWarehouse,
        CAST(ControlledWarehouse AS INT)                     AS ControlledWarehouse,
        CAST(TRIM(WarehouseLocation) AS VARCHAR(100))        AS WarehouseLocation,
        CAST(TRIM(WarehouseOrderGroup) AS VARCHAR(100))      AS WarehouseOrderGroup,
        CAST(FinanceInventoryReportFlag AS INT)              AS FinanceInventoryReportFlag
    FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Warehouse
    WHERE WarehouseCode IS NOT NULL AND TRIM(WarehouseCode) <> ''
),
ih AS (
    SELECT
        CAST(TRIM(wmaWarehouse) AS VARCHAR(50))              AS WarehouseCode,
        CAST(TRIM(wmaWarehouse) AS VARCHAR(50))              AS WarehouseName,
        CAST(TRIM(wmaWarehouseType) AS VARCHAR(100))         AS WarehouseType,
        CAST(TRIM(wmaWarehouseOrderGroup) AS VARCHAR(50))    AS IH_WarehouseOrderGroup,
        CAST(TRIM(wmaWarehouseSourceId) AS VARCHAR(50))      AS WarehouseSourceId,
        CAST(wmaSellableWarehouse AS BIT)                    AS SellableWarehouseFlag,
        CAST(wmaControlled AS BIT)                           AS ControlledFlag,
        CAST(TRIM(wmaWhereMade) AS VARCHAR(50))              AS WhereMadeCode,
        CAST(TRIM(wmaManufacturingSite) AS VARCHAR(50))      AS ManufacturingSite,
        CAST(TRIM(wmaIntransitWarehouse) AS VARCHAR(50))     AS IntransitWarehouseCode,
        CAST(CASE WHEN TRIM(wmaWarehouse) IN ('1','5','15','17','28','335','ECR')
                  THEN 1 ELSE 0 END AS BIT)                 AS IsFinishedGoodsWarehouse,
        CAST(CASE WHEN TRIM(wmaWarehouse) NOT IN ('1','5','15','17','28','335','ECR')
                  THEN 1 ELSE 0 END AS BIT)                 AS IsManufacturingWarehouse,
        CAST(NULL AS DECIMAL(18,4))                          AS TotalAvailableWarehouseCube
    FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster]
    WHERE wmaWarehouse IS NOT NULL AND TRIM(wmaWarehouse) <> ''
)
SELECT
    COALESCE(fa.WarehouseCode, ih.WarehouseCode)             AS WarehouseCode,
    fa.AFIWarehousesKey,
    fa.IntransitWarehouse,
    fa.ContainerDirectWarehouse,
    fa.ControlledWarehouse,
    CAST(COALESCE(NULLIF(fa.WarehouseOrderGroup, ''),
                  NULLIF(fa.WarehouseLocation, ''),
                  NULLIF(ih.IH_WarehouseOrderGroup, ''),
                  COALESCE(fa.WarehouseCode, ih.WarehouseCode)) AS VARCHAR(100)) AS WarehouseLocation,
    COALESCE(fa.WarehouseOrderGroup, ih.IH_WarehouseOrderGroup) AS WarehouseOrderGroup,
    fa.FinanceInventoryReportFlag,
    ih.WarehouseName,
    ih.WarehouseType,
    ih.WarehouseSourceId,
    ih.SellableWarehouseFlag,
    ih.ControlledFlag,
    ih.WhereMadeCode,
    ih.ManufacturingSite,
    ih.IntransitWarehouseCode,
    ih.IsFinishedGoodsWarehouse,
    ih.IsManufacturingWarehouse,
    ih.TotalAvailableWarehouseCube,
    CAST(GETUTCDATE() AS DATETIME2(6))                       AS LoadDT
FROM fa
FULL OUTER JOIN ih
    ON fa.WarehouseCode = ih.WarehouseCode

GO
