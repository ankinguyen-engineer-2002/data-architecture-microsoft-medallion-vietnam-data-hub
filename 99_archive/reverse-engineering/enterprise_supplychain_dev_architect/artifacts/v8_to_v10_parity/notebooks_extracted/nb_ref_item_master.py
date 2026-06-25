# ─── Cell 0 ───
TARGET_TABLE = "ref_item_master"
SOURCE_TABLE = "MasterData_DW/DimItemMaster"

COLUMN_SQL = """
SELECT
    -- Keys
    CAST(RowID AS INT)                                   AS sk_item,
    TRIM(ItemSKU)                                        AS id_item_sku,
    TRIM(ItemKey)                                        AS id_item_key,
    TRIM(Item)                                           AS id_item,
    TRIM(ItemCode)                                       AS code_item,
    TRIM(FrameNumber)                                    AS code_frame,

    -- Series
    TRIM(SeriesNumber)                                   AS code_series,
    TRIM(ExtSeriesNumber)                                AS code_ext_series,

    -- Dimensions - Metric
    CAST(ProductHeightMeters AS DECIMAL(10,2))           AS val_product_height_meters,
    CAST(ProductWidthMeters AS DECIMAL(10,2))            AS val_product_width_meters,
    CAST(ProductDepthMeters AS DECIMAL(10,2))            AS val_product_depth_meters,
    CAST(CartonHeightMeters AS DECIMAL(10,2))            AS val_carton_height_meters,
    CAST(CartonWidthMeters AS DECIMAL(10,2))             AS val_carton_width_meters,
    CAST(CartonDepthMeters AS DECIMAL(10,2))             AS val_carton_depth_meters,

    -- Dimensions - Imperial
    CAST(ProductHeightInches AS DECIMAL(10,2))           AS val_product_height_inches,
    CAST(ProductWidthInches AS DECIMAL(10,2))            AS val_product_width_inches,
    CAST(ProductDepthInches AS DECIMAL(10,2))            AS val_product_depth_inches,
    CAST(CartonHeightInches AS DECIMAL(10,2))            AS val_carton_height_inches,
    CAST(CartonWidthInches AS DECIMAL(10,2))             AS val_carton_width_inches,
    CAST(CartonDepthInches AS DECIMAL(10,2))             AS val_carton_depth_inches,
    CAST(Cubes AS DECIMAL(10,2))                         AS val_cubes,
    CAST(Seats AS DECIMAL(10,2))                         AS num_seats,

    -- Weight
    CAST(SuppWeightNetWeightLbs AS DECIMAL(10,2))        AS val_net_weight_lbs,
    CAST(UnitWeightLbs AS DECIMAL(10,2))                 AS val_unit_weight_lbs,

    -- Item Info
    CAST(QtyInBox AS INT)                                AS num_qty_in_box,
    TRIM(UOM)                                            AS code_uom,
    TRIM(UPC)                                            AS code_upc,

    -- Descriptions
    TRIM(ItemDescription)                                AS name_item_description,
    TRIM(SeriesName)                                     AS name_series,
    TRIM(SeriesColor)                                    AS name_series_color,
    TRIM(Colors)                                         AS name_color,
    TRIM(ItemDescriptionSeries)                          AS name_item_description_series,
    TRIM(SHItemDescriptionSeries)                        AS name_sh_item_description_series,
    TRIM(SHSeriesDescription)                            AS name_sh_series_description,
    TRIM(ItemDescriptionSeriesItemColor)                  AS name_item_desc_series_color,
    TRIM(ItemName)                                       AS name_item,
    TRIM(ItemConsumerDescription)                        AS name_item_consumer_description,
    TRIM(SeriesDescription)                              AS name_series_description,
    TRIM(FriendlyDimensions)                             AS name_friendly_dimensions,

    -- Style & Category
    TRIM(ChildStyleDescription)                          AS name_child_style,
    TRIM(ParentStyleDescription)                         AS name_parent_style,
    TRIM(RetailTypeDescription)                          AS name_retail_type,
    TRIM(Lifestyle)                                      AS name_lifestyle,
    TRIM(MerchandisingCategory)                          AS name_merchandising_category,
    TRIM(PricePoint)                                     AS name_price_point,
    TRIM(ItemGrouping)                                   AS name_item_grouping,
    TRIM(SeriesGrouping)                                 AS name_series_grouping,
    TRIM(AssociationCode)                                AS code_association,

    -- Classification - Item
    TRIM(ItemClassCode)                                  AS code_item_class,
    TRIM(ItemClassName)                                  AS name_item_class,
    TRIM(ItemClass)                                      AS name_item_class_full,
    TRIM(ItemStyleCode)                                  AS code_item_style,
    TRIM(ItemStyleGroup)                                 AS name_item_style_group,
    TRIM(ItemStyle)                                      AS name_item_style,
    TRIM(ItemType)                                       AS code_item_type,
    TRIM(CollectiveClass)                                AS name_collective_class,

    -- Classification - Product Line & Retail
    TRIM(ProductLine)                                    AS name_product_line,
    TRIM(RetailCategoryCode)                             AS code_retail_category,
    TRIM(RetailCategoryDescription)                      AS name_retail_category,
    TRIM(RetailCategoryName)                             AS name_retail_category_full,
    TRIM(RetailDepartmentName)                           AS name_retail_department,
    TRIM(RetailCategoryGroup)                            AS name_retail_category_group,
    TRIM(RetailCategoryChargeType)                       AS code_retail_charge_type,
    TRIM(RetailBrandName)                                AS name_retail_brand,

    -- Classification - Sales
    TRIM(SalesClassCode)                                 AS code_sales_class,
    TRIM(SalesClassDescription)                          AS name_sales_class_description,
    TRIM(SalesClass)                                     AS name_sales_class,
    TRIM(AFISalesCategoryCode)                           AS code_afi_sales_category,
    TRIM(AFISalesCategory)                               AS name_afi_sales_category,
    TRIM(AFISalesDivisionCode)                           AS code_afi_sales_division,
    TRIM(AFISalesDivision)                               AS name_afi_sales_division,
    TRIM(AFIFinanceDivision)                             AS name_afi_finance_division,
    TRIM(AFIFinanceDivisionCode)                         AS code_afi_finance_division,
    TRIM(Division)                                       AS name_division,

    -- Classification - Discount/Commission/Freight
    TRIM(DiscountClassCode)                              AS code_discount_class,
    TRIM(DiscountClassDescription)                       AS name_discount_class_description,
    TRIM(DiscountClass)                                  AS name_discount_class,
    TRIM(CommissionClassCode)                            AS code_commission_class,
    TRIM(CommissionClassDescription)                     AS name_commission_class_description,
    TRIM(CommissionClass)                                AS name_commission_class,
    TRIM(FreightClassCode)                               AS code_freight_class,
    TRIM(FreightClassDescription)                        AS name_freight_class_description,
    TRIM(FreightClass)                                   AS name_freight_class,

    -- Office & Origin
    TRIM(ResponsibleOffice)                              AS code_responsible_office,
    TRIM(ResponsibleOfficeName)                          AS name_responsible_office,
    TRIM(ImportDomesticCode)                             AS code_import_domestic,
    TRIM(CountryofOrigin)                                AS name_country_of_origin,
    TRIM(CEXCode)                                        AS code_cex,
    TRIM(PrimaryVendor)                                  AS code_primary_vendor,
    TRIM(MasterGroupCode)                                AS code_master_group,

    -- Status
    TRIM(AFIItemStatus)                                  AS code_afi_item_status,
    TRIM(SellableItemFlag)                               AS code_sellable_item,
    TRIM(ManufacturingStatus)                            AS code_manufacturing_status,
    CAST(ManufacturingStatusChangeDate AS DATE)           AS dt_manufacturing_status_change,
    TRIM(MarketingItemStatus)                            AS code_marketing_item_status,
    TRIM(MarketingStatusDescription)                     AS name_marketing_status,
    TRIM(PreviousStatusCode)                             AS code_previous_status,
    CAST(StatusCodeChangeDate AS DATE)                   AS dt_status_code_change,

    -- Flags - Boolean
    CASE WHEN TRIM(MainPieceItem) = 'True' THEN true ELSE false END AS is_main_piece,
    CASE WHEN TRIM(StandAloneFlag) = 'True' THEN true ELSE false END AS is_standalone,
    CAST(KeyItem AS INT)                                 AS num_key_item,
    CAST(CommodityItem AS INT)                           AS num_commodity_item,
    CAST(F123ProductFlag AS INT)                         AS is_f123_product,
    CAST(HSCoreProductFlag AS INT)                       AS is_hs_core_product,
    CAST(HSProprietaryProductFlag AS INT)                AS is_hs_proprietary_product,
    CAST(HSExclusiveFlag AS INT)                         AS is_hs_exclusive,
    CAST(BerklineProductFlag AS INT)                     AS is_berkline_product,
    CAST(BenchcraftProductFlag AS INT)                   AS is_benchcraft_product,
    CAST(NewMillenniumProductFlag AS INT)                AS is_new_millennium_product,
    CAST(BardiniProductFlag AS INT)                      AS is_bardini_product,
    CAST(ShanghaiStore AS INT)                           AS is_shanghai_store,
    CAST(DefaultGroup AS INT)                            AS num_default_group,
    CAST(NewItemFlag AS INT)                             AS is_new_item,
    CAST(DiscontinuedFlag AS INT)                        AS is_discontinued,
    TRIM(DiscontinuedYearPeriod)                         AS code_discontinued_period,
    TRIM(CommonCarrierFlag)                              AS code_common_carrier,
    TRIM(ExpressShipFlag)                                AS code_express_ship,
    CAST(DiscontinuedDate AS DATE)                       AS dt_discontinued,
    CAST(SeriesDateArchived AS DATE)                     AS dt_series_archived,
    CAST(SeriesDiscontinuedFlag AS INT)                  AS is_series_discontinued,
    TRIM(ConsumerChoiceFlag)                             AS code_consumer_choice,
    TRIM(EligibleForProtectionPlan)                      AS code_eligible_protection_plan,
    TRIM(IsProtectionPlan)                               AS code_is_protection_plan,
    TRIM(ItemIsRTA)                                      AS code_item_is_rta,

    -- Pricing
    CAST(FOBArcPrice AS DECIMAL(14,2))                   AS amt_fob_arc_price,
    CAST(CurrentUnitCost AS DECIMAL(14,8))               AS amt_current_unit_cost,
    TRIM(GoodBetterBestForPricePoint)                    AS code_good_better_best,
    CAST(GBBSortId AS INT)                               AS num_gbb_sort,
    TRIM(ItemPricePointRating)                           AS name_price_point_rating,
    CAST(DivisionRanking AS STRING)                      AS code_division_ranking,
    TRIM(GroupPriceIncr)                                  AS val_group_price_incr,
    TRIM(GroupPricePointType)                             AS code_group_price_point_type,

    -- Market
    TRIM(MarketIntroducedAt)                             AS name_market_introduced_at,
    CAST(MarketBeginDate AS DATE)                        AS dt_market_begin,
    CAST(MarketEndDate AS DATE)                          AS dt_market_end,
    TRIM(Showroom)                                       AS name_showroom,

    -- Invoice & Forecast
    TRIM(InitialInvoicePeriod)                           AS code_initial_invoice_period,
    CAST(InitialInvoiceQty AS INT)                       AS qty_initial_invoice,
    TRIM(ItemForecastPlannerID)                          AS id_item_forecast_planner,

    -- Multi-channel
    TRIM(PrimaryChannelSku)                              AS id_primary_channel_sku,
    TRIM(PrimarySeriesName)                              AS name_primary_series,
    TRIM(PrimarySeriesNumber)                            AS code_primary_series,
    TRIM(ERetailChannelSku)                              AS id_eretail_channel_sku,
    TRIM(ERetailSeriesName)                              AS name_eretail_series,
    TRIM(ERetailSeriesNumber)                            AS code_eretail_series,

    -- Product Attributes
    TRIM(ItemTableShapeType)                             AS name_table_shape,
    TRIM(ItemBedSizeType)                                AS name_bed_size,
    TRIM(ItemBedStyleType)                               AS name_bed_style,
    TRIM(ItemGeneralColor)                               AS name_general_color,

    -- Series Flags
    TRIM(SofaTableSeriesFlag)                            AS code_sofa_table_series,
    TRIM(ReclinerSeriesFlag)                             AS code_recliner_series,
    TRIM(PowerMotionSeriesFlag)                          AS code_power_motion_series,
    TRIM(WedgeSeriesFlag)                                AS code_wedge_series,
    TRIM(DiningSeriesFlag)                               AS code_dining_series,
    TRIM(ItemThirdPartyItem)                             AS code_item_third_party,
    TRIM(SeriesThirdParty)                               AS code_series_third_party,

    -- Homestore & eComm
    TRIM(ItemHomeStoreProductLine)                       AS name_homestore_product_line,
    TRIM(ItemEcomMerchantNotes)                          AS name_ecom_merchant_notes,
    TRIM(ItemAmazonBrandOwner)                           AS name_amazon_brand_owner,
    TRIM(ItemSupplierDirectShipOnly)                     AS code_supplier_direct_ship_only,

    -- Images & Visual
    TRIM(ItemImage)                                      AS code_item_image,
    TRIM(TrendArrow)                                     AS code_trend_arrow,
    TRIM(ItemMerchGridOverridePhoto)                     AS code_merch_grid_override_photo,
    TRIM(ExclusiveComment)                               AS name_exclusive_comment,
    TRIM(SeriesImage)                                    AS code_series_image,
    TRIM(SeriesPrimary)                                  AS code_series_primary,
    TRIM(SeriesMainImage)                                AS code_series_main_image,
    TRIM(Knockout)                                       AS code_knockout,
    TRIM(Scene7ImageSet)                                 AS code_scene7_image_set,
    TRIM(FluffAFI)                                       AS code_fluff_afi,

    -- Warranty & Material
    TRIM(MfgWarranty)                                    AS code_mfg_warranty,
    TRIM(Material)                                       AS name_material,
    TRIM(SeriesFeatures)                                 AS name_series_features

FROM raw_source
WHERE ItemSKU IS NOT NULL
"""

# ─── Cell 1 ───
notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,
        "COLUMN_SQL":   COLUMN_SQL
    }
)

