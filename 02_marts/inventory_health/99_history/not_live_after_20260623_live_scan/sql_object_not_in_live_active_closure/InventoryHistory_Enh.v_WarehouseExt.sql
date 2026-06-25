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
