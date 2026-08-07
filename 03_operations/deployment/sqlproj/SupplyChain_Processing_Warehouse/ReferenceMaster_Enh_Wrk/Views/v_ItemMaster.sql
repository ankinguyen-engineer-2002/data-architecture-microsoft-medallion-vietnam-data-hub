-- ReferenceMaster_Enh_Wrk.v_ItemMaster
CREATE     VIEW [ReferenceMaster_Enh_Wrk].[v_ItemMaster] AS
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
        CAST(NULL AS VARCHAR(8000)) AS ItemClassDescription,
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
        CASE
            WHEN TRIM(AFIItemStatus) = ''
            THEN 'C'
            ELSE AFIItemStatus
        END AS AFIItemStatus,
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
initial_invoice AS (
    SELECT
        TRIM(CAST(ID.ItemSKU AS VARCHAR(8000))) AS ItemSKU,
        COALESCE(
            MIN(CASE
                    WHEN TRIM(CAST(ID.Warehouse AS VARCHAR(8000)))
                         IN ('1', '15', '17', '19', '28', '42', '70', '5', 'ECR')
                    THEN CAST(ID.InvoiceDate AS DATE)
                END),
            MIN(CAST(ID.InvoiceDate AS DATE))
        ) AS InitialInvoiceDate
    FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail] AS ID
    WHERE ID.ItemSKU IS NOT NULL
      AND TRIM(CAST(ID.ItemSKU AS VARCHAR(8000))) <> ''
      AND TRIM(CAST(ID.Warehouse AS VARCHAR(8000))) <> '55'
      AND ID.InvoiceDate IS NOT NULL
    GROUP BY TRIM(CAST(ID.ItemSKU AS VARCHAR(8000)))
),
itmext_gdesc AS (
    SELECT
        TRIM(CAST(ITNBR AS VARCHAR(8000))) AS ItemSKU,
        MAX(TRIM(CAST(GDESCD AS VARCHAR(8000)))) AS GeneralDescriptionCode
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMEXT]
    WHERE ITNBR IS NOT NULL
      AND TRIM(CAST(ITNBR AS VARCHAR(8000))) <> ''
    GROUP BY TRIM(CAST(ITNBR AS VARCHAR(8000)))
)
SELECT
    d.ItemSKU,
    d.Description,
    d.Seats,
    d.CEXCode,
    d.UnitWeightLbs,
    d.ItemClassCode,
    CAST(COALESCE(
        NULLIF(TRIM(CAST(d.ItemClassDescription AS VARCHAR(8000))), ''),
        NULLIF(TRIM(CAST(cls.DESCR AS VARCHAR(8000))), '')
    ) AS VARCHAR(8000)) AS ItemClassDescription,
    d.ProductWidthInches,
    d.ProductDepthInches,
    d.ProductHeightInches,
    d.CartonWidthInches,
    d.CartonDepthInches,
    d.CartonHeightInches,
    d.Cubes,
    d.ExtSeriesNumber,
    d.FOBArcPrice,
    d.AFIItemStatus,
    CAST(
        CASE
            WHEN UPPER(TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))) IN ('', 'NULL') THEN NULL
            ELSE TRIM(CAST(COALESCE(ipk.ienFutureStatus, npk.npkFutureStatus) AS VARCHAR(8000)))
        END AS VARCHAR(8000)
    ) AS FutureStatus,
    d.CollectiveClass,
    d.AFIFinanceDivisionCode,
    d.AFIFinanceDivisionName,
    d.AFIItemStatusCode,
    d.AFISalesCategoryCode,
    d.AFISalesCategoryName,
    d.AFISalesDivisionCode,
    d.AFISalesDivisionName,
    d.CategoryCode,
    d.CategoryName,
    d.CollectiveClassCode,
    d.CollectiveClassName,
    d.CurrentSCPManufacturingStatusCode,
    d.CurrentStatusCode,
    d.CurrentUnitCost,
    CAST(gd.GeneralDescriptionCode AS VARCHAR(50)) AS GeneralDescriptionCode,
    CAST(inv.InitialInvoiceDate AS DATE) AS InitialInvoiceDate,
    CASE
        WHEN d.SourceRecordCount > 1 THEN 'Both'
        ELSE d.SourceTable
    END AS SourceCoverage,
    d.SourceTable AS SelectedSourceTable,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS LoadDT
FROM dedup AS d
LEFT JOIN [Enterprise_Lakehouse].[ItemMaster_AFI].[AITMCLS] AS cls
    ON TRIM(CAST(d.ItemClassCode AS VARCHAR(8000))) = TRIM(CAST(cls.ITMCL AS VARCHAR(8000)))
LEFT JOIN [Enterprise_Lakehouse].[MasterData_ProductKnowledge].[Item_ENV] AS ipk
    ON d.ItemSKU = TRIM(CAST(ipk.ienItemNumber AS VARCHAR(8000)))
   AND ipk.ienEnvironmentCode = 'AFI'
LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing].[NonPkItems] AS npk
    ON d.ItemSKU = TRIM(CAST(npk.npkItemNumber AS VARCHAR(8000)))
LEFT JOIN itmext_gdesc AS gd
    ON d.ItemSKU = gd.ItemSKU
LEFT JOIN initial_invoice AS inv
    ON d.ItemSKU = inv.ItemSKU
WHERE d.rn = 1;

GO
