-- SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimWarehouse
CREATE   VIEW Shared_DW_Wrk.v_DimWarehouse AS
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
                  THEN 1 ELSE 0 END AS BIT)                 AS IsManufacturingWarehouse
    FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster]
    WHERE wmaWarehouse IS NOT NULL AND TRIM(wmaWarehouse) <> ''
),
-- capacity_raw from below linkek (Sheet Capacity)
-- https://masterashley.sharepoint.com/sites/Global_Supply_Chain_Analytics/Shared%20Documents/Data%20Project/20260211%20Inventory%20Health/excel_source/SS%20vs%20Capacity%20Projections%2020260312.xlsx?d=wc85ce29b9b28430b891faa85ead321aa&csf=1&web=1&e=dkK5Ze
capacity_raw AS (
    SELECT *
    FROM (VALUES
        ('CSG', '1',   CAST(477532 AS DECIMAL(18,4))),
        ('CSG', '5',   CAST(578193 AS DECIMAL(18,4))),
        ('CSG', '15',  CAST(488406 AS DECIMAL(18,4))),
        ('CSG', '17',  CAST(470072 AS DECIMAL(18,4))),
        ('CSG', '28',  CAST(211193 AS DECIMAL(18,4))),
        ('CSG', '42',  CAST(188160 AS DECIMAL(18,4))),
        ('CSG', '335', CAST(184968 AS DECIMAL(18,4))),
        ('CSG', 'ECR', CAST(525928 AS DECIMAL(18,4))),
        ('UPH', '1',   CAST(100000 AS DECIMAL(18,4))),
        ('UPH', '5',   CAST(129828 AS DECIMAL(18,4))),
        ('UPH', '15',  CAST(99360  AS DECIMAL(18,4))),
        ('UPH', '17',  CAST(113656 AS DECIMAL(18,4))),
        ('UPH', '28',  CAST(62586  AS DECIMAL(18,4))),
        ('UPH', '42',  CAST(49500  AS DECIMAL(18,4))),
        ('UPH', '335', CAST(68298  AS DECIMAL(18,4))),
        ('UPH', 'ECR', CAST(134688 AS DECIMAL(18,4)))
    ) v(Storage, WarehouseCode, CurrentCapacity)
),
capacity_by_wh AS (
    SELECT
        WarehouseCode,
        SUM(CurrentCapacity) AS TotalWarehouseCube
    FROM capacity_raw
    GROUP BY WarehouseCode
)
SELECT
    COALESCE(fa.WarehouseCode, ih.WarehouseCode)             AS WarehouseCode,
    CAST(CASE
            WHEN COALESCE(fa.WarehouseCode, ih.WarehouseCode) IN ('1','5','15','16','17','19','28','42','70','ECR')
                THEN 'AFI'
            WHEN COALESCE(fa.WarehouseCode, ih.WarehouseCode) IN ('335','C35')
                THEN 'Ashton'
            WHEN COALESCE(fa.WarehouseCode, ih.WarehouseCode) IN ('AE','C','CNW','IOR')
                THEN 'C/CNW'
            WHEN COALESCE(fa.WarehouseCode, ih.WarehouseCode) IN ('12','20','201')
                THEN 'PROD'
            WHEN COALESCE(fa.WarehouseCode, ih.WarehouseCode) IN ('1A','5A','15A','17A','19A','28A','42A','ECA')
                THEN 'RH'
            ELSE 'No longer Used'
         END AS VARCHAR(50))                                 AS WarehouseGroup,
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
    cap.TotalWarehouseCube,
    CAST(GETUTCDATE() AS DATETIME2(6))                       AS LoadDT
FROM fa
FULL OUTER JOIN ih
    ON fa.WarehouseCode = ih.WarehouseCode
LEFT JOIN capacity_by_wh cap
    ON cap.WarehouseCode = COALESCE(fa.WarehouseCode, ih.WarehouseCode);
