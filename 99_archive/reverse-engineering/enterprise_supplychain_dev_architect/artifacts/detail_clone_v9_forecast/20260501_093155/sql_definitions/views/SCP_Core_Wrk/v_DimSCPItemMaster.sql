-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimSCPItemMaster
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE       VIEW [SCP_CORE_WRK].[v_DimSCPItemMaster] AS (SELECT RTRIM([DIM].[ItemSKU]) AS [Item SKU]
      ,[DIM].[ItemDescription] AS [Item Description]
      ,CONCAT(RTRIM([DIM].[ItemSKU]),' - ',[DIM].[ItemDescription]) AS [Item SKU Description]
      ,[DIM].[ItemCode] AS [Item Code]
      ,[DIM].[SeriesNumber] AS [Series Number]
      ,[DIM].[ExtSeriesNumber] AS [Ext Series Number]
      ,[EXT].[SERIES] AS [Planning Series]
      ,[DIM].[SeriesName] AS [Series Name]
      ,[DIM].[SeriesColor] AS [Series Color]
      ,[DIM].[Colors] AS [Colors]
      ,[DIM].[FrameNumber] AS [Frame Number]
      ,[DIM].[SeriesDescription] AS [Series Description]
      ,RTRIM(COALESCE([IPK].[ienForecastPlannerID],[NPK].[npkForecastPlannerID])) AS [Item Forecast Planner ID]
      ,[DIM].[ItemForecastPlannerID] AS [Item Forecast Planner ID (Dim)]
      ,[DIM].[AFIItemStatus] AS [AFI Item Status]
      ,RTRIM(COALESCE([IPK].[ienFutureStatus],[NPK].[npkFutureStatus])) AS [Future Status]
      ,[DIM].[ItemName] AS [Item Name]
      ,[DIM].[ItemClass] AS [Item Class]
      ,[DIM].[ItemClassCode] AS [Item Class Code]
      ,[DIM].[ItemClassName] AS [Item Class Name]
      ,[DIM].[CollectiveClass] AS [Collective Class]
      ,[DIM].[AFISalesDivision] AS [AFI Sales Division]
      ,[DIM].[ItemGrouping] AS [Item Grouping]
      ,[DIM].[AssociationCode] AS [Association Code]
      ,[DIM].[Showroom] AS [Showroom]
      ,[DIM].[ProductLine] AS [Product Line]
      --,RTRIM([GDC].[GDICS]) AS [General Description]
      ,RTRIM(COALESCE([IPK].[ienHoldBuyCode],[NPK].[npkHoldBuyCode])) AS [Hold Buy Code]
      ,[DIM].[ItemImage] AS [Item Image]
      ,[Image URL] = 
		CASE DIM.[ItemImage]
			WHEN '' THEN NULL
			WHEN NULL THEN NULL
            ELSE CONCAT('http://www.ashleydirect.com/graphics/',DIM.[ItemImage])
        END
      ,[DIM].[QtyInBox] AS [Quantity In Box]
      ,[DIM].[UOM] AS [UOM]
      ,[DIM].[Cubes] AS [Cubes]
      ,[DIM].[Seats] AS [Seats]
      ,[DIM].[ProductHeightMeters] AS [Product Height Meters]
      ,[DIM].[ProductWidthMeters] AS [Product Width Meters]
      ,[DIM].[ProductDepthMeters] AS [Product Depth Meters]
      ,[DIM].[CartonHeightMeters] AS [Carton Height Meters]
      ,[DIM].[CartonWidthMeters] AS [Carton Width Meters]
      ,[DIM].[CartonDepthMeters] AS [Carton Depth Meters]
      ,[DIM].[ProductHeightInches] AS [Product Height Inches]
      ,[DIM].[ProductWidthInches] AS [Product Width Inches]
      ,[DIM].[ProductDepthInches] AS [Product Depth Inches]
      ,[DIM].[CartonHeightInches] AS [Carton Height Inches]
      ,[DIM].[CartonWidthInches] AS [Carton Width Inches]
      ,[DIM].[CartonDepthInches] AS [Carton Depth Inches]
      ,[DIM].[ItemDescriptionSeries] AS [Item Description Series]
      ,[DIM].[SHItemDescriptionSeries] AS [SH Item Description Series]
      ,[DIM].[SHSeriesDescription] AS [SH Series Description]
      ,[DIM].[ItemDescriptionSeriesItemColor] AS [Item Description Series Item Color]
      ,[DIM].[ChildStyleDescription] AS [Child Style Description]
      ,[DIM].[ParentStyleDescription] AS [Parent Style Description]
      ,[DIM].[ItemConsumerDescription] AS [Item Consumer Description]
      ,[DIM].[RetailTypeDescription] AS [Retail Type Description]
      ,[DIM].[MainPieceItem] AS [Main Piece Item]
      ,[DIM].[RetailCategoryCode] AS [Retail Category Code]
      ,[DIM].[RetailCategoryDescription] AS [Retail Category Description]
      ,[DIM].[RetailCategoryName] AS [Retail Category Name]
      ,[DIM].[RetailDepartmentName] AS [Retail Department Name]
      ,[DIM].[RetailCategoryGroup] AS [Retail Category Group]
      ,[DIM].[RetailCategoryChargeType] AS [Retail Category Charge Type]
      ,[DIM].[AFIFinanceDivision] AS [AFI Finance Division]
      ,[DIM].[AFIFinanceDivisionCode] AS [AFI Finance Division Code]
      ,[DIM].[AFISalesCategoryCode] AS [AFI Sales Category Code]
      ,[DIM].[AFISalesCategory] AS [AFI Sales Category]
      ,[DIM].[ItemStyleCode] AS [Item Style Code]
      ,[DIM].[ItemStyleGroup] AS [Item Style Group]
      ,[DIM].[ItemStyle] AS [Item Style]
      ,[DIM].[Division] AS [Division]
      ,[DIM].[AFISalesDivisionCode] AS [AFI Sales Division Code]
      ,[DIM].[KeyItem] AS [Key Item]
      ,[DIM].[ItemType] AS [Item Type]
      ,[DIM].[SellableItemFlag] AS [Sellable Item Flag]
      ,[DIM].[ManufacturingStatus] AS [Manufacturing Status]
      ,[DIM].[ResponsibleOffice] AS [Responsible Office]
      ,[DIM].[ResponsibleOfficeName] AS [Responsible Office Name]
      ,[DIM].[ImportDomesticCode] AS [Import Domestic Code]
      ,[DIM].[CountryofOrigin] AS [Country Of Origin]
      ,[DIM].[PrimaryVendor] AS [Primary Vendor]
      ,[DIM].[ManufacturingStatusChangeDate] AS [Manufacturing Status Change Date]
      ,[DIM].[NewItemFlag] AS [New Item Flag]
      ,[DIM].[DiscontinuedFlag] AS [Discontinued Flag]
      ,[DIM].[DiscontinuedYearPeriod] AS [Discontinued Year Period]
      ,[DIM].[CommonCarrierFlag] AS [Common Carrier Flag]
      ,[DIM].[ExpressShipFlag] AS [Express Ship Flag]
      ,[DIM].[DiscontinuedDate] AS [Discontinued Date]
      ,[DIM].[SeriesDateArchived] AS [Series Date Archived]
      ,[DIM].[SeriesDiscontinuedFlag] AS [Series Discontinued Flag]
      ,[DIM].[PreviousStatusCode] AS [Previous Status Code]
      ,[DIM].[StatusCodeChangeDate] AS [Status Code Change Date]
      ,[DIM].[CurrentUnitCost] AS [Current Unit Cost]
      ,[DIM].[CEXCode] AS [CEX Code]
      ,[DIM].[MarketIntroducedAt] AS [Market Introduced At]
      ,[DIM].[MerchandisingCategory] AS [Merchandising Category]
      ,[DIM].[PricePoint] AS [Price Point]
      ,[DIM].[SeriesGrouping] AS [Series Grouping]
      ,[DIM].[MasterGroupCode] AS [Master Group Code]
      ,[DIM].[MarketingItemStatus] AS [Marketing Item Status]
      ,[DIM].[MarketingStatusDescription] AS [Marketing Status Description]
      ,[DIM].[Lifestyle] AS [Lifestyle]
      ,[DIM].[CommodityItem] AS [Commodity Item]
      ,[DIM].[F123ProductFlag] AS [F123 Product Flag]
      ,[DIM].[HSCoreProductFlag] AS [HS Core Product Flag]
      ,[DIM].[HSProprietaryProductFlag] AS [HS Proprietary Product Flag]
      ,[DIM].[HSExclusiveFlag] AS [HS Exclusive Flag]
      ,[DIM].[BerklineProductFlag] AS [Berkline Product Flag]
      ,[DIM].[BenchcraftProductFlag] AS [Benchcraft Product Flag]
      ,[DIM].[NewMillenniumProductFlag] AS [New Millennium Product Flag]
      ,[DIM].[BardiniProductFlag] AS [Bardini Product Flag]
      ,[DIM].[ShanghaiStore] AS [Shanghai Store]
      ,[DIM].[DefaultGroup] AS [Default Group]
      ,[DIM].[GoodBetterBestForPricePoint] AS [Good Better Best For Price Point]
      ,[DIM].[GBBSortId] AS [GBB Sort Id]
      ,[DIM].[InitialInvoicePeriod] AS [Initial Invoice Period]
      ,[DIM].[InitialInvoiceQty] AS [Initial Invoice Qty]
      ,[DIM].[MarketBeginDate] AS [Market Begin Date]
      ,[DIM].[MarketEndDate] AS [Market End Date]
      ,[DIM].[FOBArcPrice] AS [FOB Arc Price]
      ,[DIM].[DivisionRanking] AS [Division Ranking]
      ,[DIM].[TrendArrow] AS [Trend Arrow]
      ,[DIM].[ItemMerchGridOverridePhoto] AS [Item Merch Grid Override Photo]
      ,[DIM].[GroupPriceIncr] AS [Group Price Incr]
      ,[DIM].[GroupPricePointType] AS [Group Price Point Type]
      ,[DIM].[ExclusiveComment] AS [Exclusive Comment]
      ,[DIM].[SeriesImage] AS [Series Image]
      ,[DIM].[SofaTableSeriesFlag] AS [Sofa Table Series Flag]
      ,[DIM].[ReclinerSeriesFlag] AS [Recliner Series Flag]
      ,[DIM].[PowerMotionSeriesFlag] AS [Power Motion Series Flag]
      ,[DIM].[WedgeSeriesFlag] AS [Wedge Series Flag]
      ,[DIM].[DiningSeriesFlag] AS [Dining Series Flag]
      ,[DIM].[ItemThirdPartyItem] AS [Item Third Party Item]
      ,[DIM].[SeriesThirdParty] AS [Series Third Party]
      ,[DIM].[ItemHomeStoreProductLine] AS [Item Home Store Product Line]
      ,[DIM].[ItemEcomMerchantNotes] AS [Item Ecom Merchant Notes]
      ,[DIM].[ItemAmazonBrandOwner] AS [Item Amazon Brand Owner]
      ,[DIM].[ItemSupplierDirectShipOnly] AS [Item Supplier Direct Ship Only]
      ,[DIM].[ConsumerChoiceFlag] AS [Consumer Choice Flag]
      ,[DIM].[EligibleForProtectionPlan] AS [Eligible For Protection Plan]
      ,[DIM].[IsProtectionPlan] AS [Is Protection Plan]
      ,[DIM].[FriendlyDimensions] AS [Friendly Dimensions]
      ,[DIM].[Knockout] AS [Knockout]
      ,[DIM].[Scene7ImageSet] AS [Scene7 Image Set]
      ,[DIM].[FluffAFI] AS [Fluff AFI]
      ,[DIM].[SeriesPrimary] AS [Series Primary]
      ,[DIM].[SeriesMainImage] AS [Series Main Image]
      ,[DIM].[StandAloneFlag] AS [Stand Alone Flag]
      ,[DIM].[SuppWeightNetWeightLbs] AS [Supp Weight Net Weight Lbs]
      ,[DIM].[UnitWeightLbs] AS [Unit Weight Lbs]
      ,[DIM].[UPC] AS [UPC]
      ,[DIM].[RetailBrandName] AS [Retail Brand Name]
      ,[DIM].[MfgWarranty] AS [Mfg Warranty]
      ,[DIM].[Material] AS [Material]
      ,[DIM].[SeriesFeatures] AS [Series Features]
      ,[DIM].[ItemIsRTA] AS [Item Is RTA]
      ,[DIM].[PrimaryChannelSku] AS [Primary Channel Sku]
      ,[DIM].[PrimarySeriesName] AS [Primary Series Name]
      ,[DIM].[PrimarySeriesNumber] AS [Primary Series Number]
      ,[DIM].[ERetailChannelSku] AS [E Retail Channel Sku]
      ,[DIM].[ERetailSeriesName] AS [E Retail Series Name]
      ,[DIM].[ERetailSeriesNumber] AS [E Retail Series Number]
      ,[DIM].[ItemTableShapeType] AS [Item Table Shape Type]
      ,[DIM].[ItemBedSizeType] AS [Item Bed Size Type]
      ,[DIM].[ItemBedStyleType] AS [Item Bed Style Type]
      ,[DIM].[ItemGeneralColor] AS [Item General Color]
      ,[DIM].[ItemPricePointRating] AS [Item Price Point Rating]
      ,CASE
            WHEN [DIM].[ItemClassCode] IN ('MATT','UESW','USKE','UTRK','WVBC',
                                            'WVCD','WVCS','WVCU','WVHC','WVHD',
                                            'WVUP','WVWB','ZACK','ZAMK',       -- #'ZBIS' Removed Purchased Beds
                                            'ZDCK','ZDLK','ZDMK','ZJBK','ZJFK',
                                            'ZJIK','ZJLK',                     -- # Resident Home Bedding Kits
                                            'ZKBK','ZMCK','ZMLK','ZUCK','ZUMK',
                                            'ZXCK','ZXLK','ZXMK',
                                            'WVVG','WVVF'
                                            )
                THEN 'PART'
            ELSE ''
        END AS [Part Flag]
      ,CASE
            WHEN [DIM].[ItemClassCode] LIKE 'Z__K' AND RIGHT(RTRIM([DIM].[ItemSKU]),2) = 'UN'
                THEN 'UN'
            WHEN [DIM].[ItemClassCode] IN ('WVVG','WVVF') AND RIGHT(RTRIM([DIM].[ItemSKU]),2) = 'UN'
                THEN 'UN'
            ELSE ''
        END AS [Kit Flag]
  FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] AS DIM
  
  LEFT JOIN [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMEXT] AS EXT
    ON [DIM].[ItemSKU] = [EXT].[ITNBR]  
  
  --LEFT JOIN [MasterData_ItemMaster_AFI].[GENDESC] AS GDC
  --ON [EXT].[GDESCD] = [GDC].[GDCODE]

  LEFT JOIN [Enterprise_Lakehouse].[MasterData_ProductKnowledge].[Item_ENV] AS IPK
    ON [DIM].[ItemSKU] = [IPK].[ienItemNumber]
	  AND [IPK].[ienEnvironmentCode] = 'AFI'

  LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing].[NonPkItems] AS NPK
    ON [DIM].[ItemSKU] = [NPK].[npkItemNumber]


  WHERE [DIM].[ItemSupplierDirectShipOnly] = 'False'




)