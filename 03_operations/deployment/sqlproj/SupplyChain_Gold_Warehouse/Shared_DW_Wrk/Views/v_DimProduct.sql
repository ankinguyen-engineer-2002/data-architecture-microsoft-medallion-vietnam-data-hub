-- Shared_DW_Wrk.v_DimProduct
CREATE   VIEW Shared_DW_Wrk.v_DimProduct AS
-- ===========================================================================
-- Shared_DW.v_DimProduct - canonical shared item/product dimension
-- Source of record: SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.v_ItemMaster
-- v_ItemMaster is union/dedup from DimItemMaster + ITMEXT.
-- ===========================================================================
SELECT
    CAST(TRIM(CAST(d.[ItemSKU] AS VARCHAR(8000))) AS VARCHAR(50)) AS [ItemSKU],
    d.[Description],
    d.[Seats],
    d.[CEXCode],
    d.[UnitWeightLbs],
    d.[ItemClassCode],
    d.[ItemClassDescription],
    d.[ProductWidthInches],
    d.[ProductDepthInches],
    d.[ProductHeightInches],
    d.[CartonWidthInches],
    d.[CartonDepthInches],
    d.[CartonHeightInches],
    d.[Cubes],
    d.[ExtSeriesNumber],
    d.[FOBArcPrice],
    d.[AFIItemStatus],
    d.[FutureStatus],
    d.[CollectiveClass],
    d.[AFIFinanceDivisionCode],
    d.[AFIFinanceDivisionName],
    d.[AFIItemStatusCode],
    d.[AFISalesCategoryCode],
    d.[AFISalesCategoryName],
    d.[AFISalesDivisionCode],
    d.[AFISalesDivisionName],
    d.[CategoryCode],
    d.[CategoryName],
    d.[CollectiveClassCode],
    d.[CollectiveClassName],
    d.[CurrentSCPManufacturingStatusCode],
    d.[CurrentStatusCode],
    d.[CurrentUnitCost],
    d.[SourceCoverage],
    d.[SelectedSourceTable],
    d.[LoadDT],
    CAST(CASE
        WHEN TRIM(CAST(d.[AFIItemStatus] AS VARCHAR(8000))) = 'N' THEN 'New'
        WHEN TRIM(CAST(d.[AFIItemStatus] AS VARCHAR(8000))) = 'A' THEN 'Active'
        WHEN TRIM(CAST(d.[AFIItemStatus] AS VARCHAR(8000))) IN ('D','R') THEN 'Inactive'
        WHEN d.[AFIItemStatus] IS NULL THEN 'Unknown'
        ELSE 'Other'
    END AS VARCHAR(20)) AS [LifecycleStatus],
    CAST(CASE
        WHEN LEFT(TRIM(CAST(d.[ItemClassCode] AS VARCHAR(8000))), 1) = 'Z'
         AND RIGHT(TRIM(CAST(d.[ItemClassCode] AS VARCHAR(8000))), 1) = 'K'
        THEN 1 ELSE 0 END AS BIT) AS [IsFinishedGoodsItem],
    CAST(ISNULL(u.[UnavailableFlag], 0) AS BIT) AS [UnavailableFlag],
    CAST(GETUTCDATE() AS DATETIME2(6)) AS [GoldLoadDT]
FROM [SupplyChain_Processing_Warehouse].[ReferenceMaster_Enh].[ItemMaster] AS d
LEFT JOIN (
    SELECT
        TRIM(CAST([ITNBR] AS VARCHAR(8000))) AS [ItemSKU],
        MAX(CASE WHEN TRIM(CAST([MFPUS] AS VARCHAR(8000))) = 'U' THEN 1 ELSE 0 END) AS [UnavailableFlag]
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
    WHERE [ITNBR] IS NOT NULL
      AND TRIM(CAST([ITNBR] AS VARCHAR(8000))) <> ''
    GROUP BY TRIM(CAST([ITNBR] AS VARCHAR(8000)))
) AS u
    ON u.[ItemSKU] = TRIM(CAST(d.[ItemSKU] AS VARCHAR(8000)))
WHERE d.[ItemSKU] IS NOT NULL
  AND TRIM(CAST(d.[ItemSKU] AS VARCHAR(8000))) <> '';
