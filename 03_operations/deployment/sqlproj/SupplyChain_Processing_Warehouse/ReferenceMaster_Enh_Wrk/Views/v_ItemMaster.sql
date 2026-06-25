-- ReferenceMaster_Enh_Wrk.v_ItemMaster
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_ItemMaster] AS
WITH itmext AS (
    SELECT
        CAST(TRIM(CAST(src.ITNBR AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemSKU,
        CAST(
            COALESCE(
                NULLIF(TRIM(CAST(src.PRDDDES AS VARCHAR(8000))), ''),
                NULLIF(TRIM(CAST(src.GDESCD AS VARCHAR(8000))), '')
            ) AS VARCHAR(8000)
        ) AS Description,
        CAST(src.NBSEAT AS DECIMAL(18,4)) AS Seats,
        CAST(TRIM(CAST(src.CEX AS VARCHAR(8000))) AS VARCHAR(50)) AS CEXCode,
        CAST(src.ITMWEGHT AS DECIMAL(18,4)) AS UnitWeightLbs,
        CAST(TRIM(CAST(src.ITMITCLS AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemClassCode,
        CAST(TRIM(CAST(cls.DESCR AS VARCHAR(8000))) AS VARCHAR(8000)) AS ItemClassDescription,
        CAST(src.PRDLIN AS DECIMAL(18,4)) AS ProductWidthInches,
        CAST(src.PRDWIN AS DECIMAL(18,4)) AS ProductDepthInches,
        CAST(src.PRDHIN AS DECIMAL(18,4)) AS ProductHeightInches,
        CAST(src.CRTLIN AS DECIMAL(18,4)) AS CartonWidthInches,
        CAST(src.CRTWIN AS DECIMAL(18,4)) AS CartonDepthInches,
        CAST(src.CRTHIN AS DECIMAL(18,4)) AS CartonHeightInches,
        CAST(src.CUBES AS DECIMAL(18,4)) AS Cubes,
        CAST(TRIM(CAST(src.SERIES AS VARCHAR(8000))) AS VARCHAR(50)) AS ExtSeriesNumber,
        CAST(NULL AS DECIMAL(18,4)) AS FOBArcPrice,
        CAST(NULL AS VARCHAR(100)) AS AFIItemStatus,
        CAST(
            CASE
                WHEN UPPER(TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))) IN ('', 'NULL') THEN NULL
                ELSE TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))
            END AS VARCHAR(8000)
        ) AS FutureStatus,
        CAST(NULL AS VARCHAR(100)) AS CollectiveClass,
        CAST(NULL AS VARCHAR(50)) AS AFIFinanceDivisionCode,
        CAST(NULL AS VARCHAR(100)) AS AFIFinanceDivisionName,
        CAST(NULL AS VARCHAR(50)) AS AFIItemStatusCode,
        CAST(NULL AS VARCHAR(50)) AS AFISalesCategoryCode,
        CAST(NULL AS VARCHAR(100)) AS AFISalesCategoryName,
        CAST(NULL AS VARCHAR(50)) AS AFISalesDivisionCode,
        CAST(NULL AS VARCHAR(100)) AS AFISalesDivisionName,
        CAST(NULL AS VARCHAR(50)) AS CategoryCode,
        CAST(NULL AS VARCHAR(100)) AS CategoryName,
        CAST(NULL AS VARCHAR(50)) AS CollectiveClassCode,
        CAST(NULL AS VARCHAR(100)) AS CollectiveClassName,
        CAST(NULL AS VARCHAR(50)) AS CurrentSCPManufacturingStatusCode,
        CAST(NULL AS VARCHAR(50)) AS CurrentStatusCode,
        CAST(NULL AS DECIMAL(18,4)) AS CurrentUnitCost,
        CAST('ITMEXT' AS VARCHAR(50)) AS SourceTable,
        CAST(2 AS INT) AS SourcePriority
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMEXT] AS src
    LEFT JOIN [Enterprise_Lakehouse].[ItemMaster_AFI].[AITMCLS] AS cls
        ON TRIM(CAST(src.ITMITCLS AS VARCHAR(8000))) = TRIM(CAST(cls.ITMCL AS VARCHAR(8000)))
    LEFT JOIN [Enterprise_Lakehouse].[MasterData_ProductKnowledge].[Item_ENV] AS ipk
        ON TRIM(CAST(src.ITNBR AS VARCHAR(8000))) = TRIM(CAST(ipk.ienItemNumber AS VARCHAR(8000)))
       AND ipk.ienEnvironmentCode = 'AFI'
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing].[NonPkItems] AS npk
        ON TRIM(CAST(src.ITNBR AS VARCHAR(8000))) = TRIM(CAST(npk.npkItemNumber AS VARCHAR(8000)))
    WHERE src.ITNBR IS NOT NULL
      AND TRIM(CAST(src.ITNBR AS VARCHAR(8000))) <> ''
),
dim_item AS (
    SELECT
        CAST(TRIM(CAST(src.ItemSKU AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemSKU,
        CAST(NULLIF(TRIM(CAST(src.ItemDescription AS VARCHAR(8000))), '') AS VARCHAR(8000)) AS Description,
        CAST(src.Seats AS DECIMAL(18,4)) AS Seats,
        CAST(TRIM(CAST(src.CEXCode AS VARCHAR(8000))) AS VARCHAR(50)) AS CEXCode,
        CAST(src.UnitWeightLbs AS DECIMAL(18,4)) AS UnitWeightLbs,
        CAST(TRIM(CAST(src.ItemClassCode AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemClassCode,
        CAST(TRIM(CAST(src.ItemClassName AS VARCHAR(8000))) AS VARCHAR(8000)) AS ItemClassDescription,
        CAST(src.ProductWidthInches AS DECIMAL(18,4)) AS ProductWidthInches,
        CAST(src.ProductDepthInches AS DECIMAL(18,4)) AS ProductDepthInches,
        CAST(src.ProductHeightInches AS DECIMAL(18,4)) AS ProductHeightInches,
        CAST(src.CartonWidthInches AS DECIMAL(18,4)) AS CartonWidthInches,
        CAST(src.CartonDepthInches AS DECIMAL(18,4)) AS CartonDepthInches,
        CAST(src.CartonHeightInches AS DECIMAL(18,4)) AS CartonHeightInches,
        CAST(src.Cubes AS DECIMAL(18,4)) AS Cubes,
        CAST(TRIM(CAST(src.ExtSeriesNumber AS VARCHAR(8000))) AS VARCHAR(50)) AS ExtSeriesNumber,
        CAST(src.FOBArcPrice AS DECIMAL(18,4)) AS FOBArcPrice,
        CAST(TRIM(CAST(src.AFIItemStatus AS VARCHAR(8000))) AS VARCHAR(100)) AS AFIItemStatus,
        CAST(
            CASE
                WHEN UPPER(TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))) IN ('', 'NULL') THEN NULL
                ELSE TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))
            END AS VARCHAR(8000)
        ) AS FutureStatus,
        CAST(TRIM(CAST(src.CollectiveClass AS VARCHAR(8000))) AS VARCHAR(100)) AS CollectiveClass,
        CAST(TRIM(CAST(src.AFIFinanceDivisionCode AS VARCHAR(8000))) AS VARCHAR(50)) AS AFIFinanceDivisionCode,
        CAST(TRIM(CAST(src.AFIFinanceDivision AS VARCHAR(8000))) AS VARCHAR(100)) AS AFIFinanceDivisionName,
        CAST(TRIM(CAST(src.AFIItemStatus AS VARCHAR(8000))) AS VARCHAR(50)) AS AFIItemStatusCode,
        CAST(TRIM(CAST(src.AFISalesCategoryCode AS VARCHAR(8000))) AS VARCHAR(50)) AS AFISalesCategoryCode,
        CAST(TRIM(CAST(src.AFISalesCategory AS VARCHAR(8000))) AS VARCHAR(100)) AS AFISalesCategoryName,
        CAST(TRIM(CAST(src.AFISalesDivisionCode AS VARCHAR(8000))) AS VARCHAR(50)) AS AFISalesDivisionCode,
        CAST(TRIM(CAST(src.AFISalesDivision AS VARCHAR(8000))) AS VARCHAR(100)) AS AFISalesDivisionName,
        CAST(TRIM(CAST(src.RetailCategoryCode AS VARCHAR(8000))) AS VARCHAR(50)) AS CategoryCode,
        CAST(TRIM(CAST(src.RetailCategoryName AS VARCHAR(8000))) AS VARCHAR(100)) AS CategoryName,
        CAST(TRIM(CAST(src.CollectiveClass AS VARCHAR(8000))) AS VARCHAR(50)) AS CollectiveClassCode,
        CAST(TRIM(CAST(src.CollectiveClass AS VARCHAR(8000))) AS VARCHAR(100)) AS CollectiveClassName,
        CAST(TRIM(CAST(src.ManufacturingStatus AS VARCHAR(8000))) AS VARCHAR(50)) AS CurrentSCPManufacturingStatusCode,
        CAST(TRIM(CAST(src.PreviousStatusCode AS VARCHAR(8000))) AS VARCHAR(50)) AS CurrentStatusCode,
        CAST(src.CurrentUnitCost AS DECIMAL(18,4)) AS CurrentUnitCost,
        CAST('DimItemMaster' AS VARCHAR(50)) AS SourceTable,
        CAST(1 AS INT) AS SourcePriority
    FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] AS src
    LEFT JOIN [Enterprise_Lakehouse].[MasterData_ProductKnowledge].[Item_ENV] AS ipk
        ON TRIM(CAST(src.ItemSKU AS VARCHAR(8000))) = TRIM(CAST(ipk.ienItemNumber AS VARCHAR(8000)))
       AND ipk.ienEnvironmentCode = 'AFI'
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing].[NonPkItems] AS npk
        ON TRIM(CAST(src.ItemSKU AS VARCHAR(8000))) = TRIM(CAST(npk.npkItemNumber AS VARCHAR(8000)))
    WHERE src.ItemSKU IS NOT NULL
      AND TRIM(CAST(src.ItemSKU AS VARCHAR(8000))) <> ''
),
unioned AS (
    SELECT * FROM dim_item
    UNION ALL
    SELECT * FROM itmext
),
dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSKU
            ORDER BY SourcePriority
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY ItemSKU
        ) AS SourceRecordCount
    FROM unioned
),
__bob_source AS (
SELECT
    ItemSKU,
    Description,
    Seats,
    CEXCode,
    UnitWeightLbs,
    ItemClassCode,
    ItemClassDescription,
    ProductWidthInches,
    ProductDepthInches,
    ProductHeightInches,
    CartonWidthInches,
    CartonDepthInches,
    CartonHeightInches,
    Cubes,
    ExtSeriesNumber,
    FOBArcPrice,
    AFIItemStatus,
    FutureStatus,
    CollectiveClass,
    AFIFinanceDivisionCode,
    AFIFinanceDivisionName,
    AFIItemStatusCode,
    AFISalesCategoryCode,
    AFISalesCategoryName,
    AFISalesDivisionCode,
    AFISalesDivisionName,
    CategoryCode,
    CategoryName,
    CollectiveClassCode,
    CollectiveClassName,
    CurrentSCPManufacturingStatusCode,
    CurrentStatusCode,
    CurrentUnitCost,
    CASE
        WHEN SourceRecordCount > 1 THEN 'Both'
        ELSE SourceTable
    END AS SourceCoverage,
    SourceTable AS SelectedSourceTable
FROM dedup
WHERE rn = 1
)
SELECT
    [ItemSKU] = src.[ItemSKU],
    [Description] = src.[Description],
    [Seats] = src.[Seats],
    [CEXCode] = src.[CEXCode],
    [UnitWeightLbs] = src.[UnitWeightLbs],
    [ItemClassCode] = src.[ItemClassCode],
    [ItemClassDescription] = src.[ItemClassDescription],
    [ProductWidthInches] = src.[ProductWidthInches],
    [ProductDepthInches] = src.[ProductDepthInches],
    [ProductHeightInches] = src.[ProductHeightInches],
    [CartonWidthInches] = src.[CartonWidthInches],
    [CartonDepthInches] = src.[CartonDepthInches],
    [CartonHeightInches] = src.[CartonHeightInches],
    [Cubes] = src.[Cubes],
    [ExtSeriesNumber] = src.[ExtSeriesNumber],
    [FOBArcPrice] = src.[FOBArcPrice],
    [AFIItemStatus] = src.[AFIItemStatus],
    [FutureStatus] = src.[FutureStatus],
    [CollectiveClass] = src.[CollectiveClass],
    [AFIFinanceDivisionCode] = src.[AFIFinanceDivisionCode],
    [AFIFinanceDivisionName] = src.[AFIFinanceDivisionName],
    [AFIItemStatusCode] = src.[AFIItemStatusCode],
    [AFISalesCategoryCode] = src.[AFISalesCategoryCode],
    [AFISalesCategoryName] = src.[AFISalesCategoryName],
    [AFISalesDivisionCode] = src.[AFISalesDivisionCode],
    [AFISalesDivisionName] = src.[AFISalesDivisionName],
    [CategoryCode] = src.[CategoryCode],
    [CategoryName] = src.[CategoryName],
    [CollectiveClassCode] = src.[CollectiveClassCode],
    [CollectiveClassName] = src.[CollectiveClassName],
    [CurrentSCPManufacturingStatusCode] = src.[CurrentSCPManufacturingStatusCode],
    [CurrentStatusCode] = src.[CurrentStatusCode],
    [CurrentUnitCost] = src.[CurrentUnitCost],
    [SourceCoverage] = src.[SourceCoverage],
    [SelectedSourceTable] = src.[SelectedSourceTable],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
