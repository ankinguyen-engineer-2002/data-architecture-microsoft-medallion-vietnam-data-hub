# ─── Cell 0 ───
TARGET_TABLE = "ref_product"
SOURCE_TABLE = "SupplyChain_DW/DimCurrentProductDetails"

COLUMN_SQL = """
SELECT
    -- Keys & Identifiers
    CAST(CurrentProductDetailsKey AS INT)                 AS sk_product,
    TRIM(ItemSKU)                                        AS id_item_sku,
    TRIM(Item)                                           AS id_item,
    TRIM(SCPItem)                                        AS id_scp_item,

    -- Item Descriptions
    TRIM(ItemDescription)                                AS name_item_description,
    TRIM(Colors)                                         AS name_color,
    CAST(QtyInBox AS INT)                                AS num_qty_in_box,
    TRIM(UOM)                                            AS code_uom,

    -- Series
    TRIM(SeriesNumber)                                   AS code_series,
    TRIM(ExtSeriesNumber)                                AS code_ext_series,
    TRIM(ItemExtSeriesNumber)                             AS code_item_ext_series,
    TRIM(SeriesName)                                     AS name_series,
    TRIM(SeriesColor)                                    AS name_series_color,
    TRIM(SeriesDescription)                              AS name_series_description,

    -- Concatenated Descriptions
    TRIM(`Item-Description-Series`)                      AS name_item_desc_series,
    TRIM(`SH-Item-Description-Series`)                   AS name_sh_item_desc_series,
    TRIM(`SH-Series-Description`)                        AS name_sh_series_description,
    TRIM(`Item-Description-Series-ItemColor`)            AS name_item_desc_series_color,

    -- Classification - Item
    TRIM(ItemClassCode)                                  AS code_item_class,
    TRIM(ItemClassName)                                  AS name_item_class,
    TRIM(ItemClass)                                      AS name_item_class_full,
    TRIM(ItemCode)                                       AS code_item,
    TRIM(ItemGrouping)                                   AS name_item_grouping,
    TRIM(ItemStyleCode)                                  AS code_item_style,
    TRIM(ItemStyleGroup)                                 AS name_item_style_group,
    TRIM(ItemStyle)                                      AS name_item_style,

    -- Classification - Product Line & Category
    TRIM(ProductLine)                                    AS name_product_line,
    TRIM(RetailCategoryCode)                             AS code_retail_category,
    TRIM(RetailCategoryDescription)                      AS name_retail_category,
    TRIM(MerchandisingCategory)                          AS name_merchandising_category,
    TRIM(ChildStyleDescription)                          AS name_child_style,
    TRIM(ParentStyleDescription)                         AS name_parent_style,
    TRIM(PricePoint)                                     AS name_price_point,
    TRIM(AssociationCode)                                AS code_association,

    -- Classification - Sales
    TRIM(SalesClassCode)                                 AS code_sales_class,
    TRIM(SalesClassDescription)                          AS name_sales_class_description,
    TRIM(SalesClass)                                     AS name_sales_class,
    TRIM(AFISalesCategoryCode)                           AS code_afi_sales_category,
    TRIM(AFISalesCategory)                               AS name_afi_sales_category,
    TRIM(AFISalesDivisionCode)                           AS code_afi_sales_division,
    TRIM(AFISalesDivision)                               AS name_afi_sales_division,
    TRIM(AFIFinanceDivision)                             AS name_afi_finance_division,

    -- Classification - Discount
    TRIM(DiscountClassCode)                              AS code_discount_class,
    TRIM(DiscountClassDescription)                       AS name_discount_class_description,
    TRIM(DiscountClass)                                  AS name_discount_class,

    -- Classification - Commission
    TRIM(CommissionClassCode)                            AS code_commission_class,
    TRIM(CommissionClassDescription)                     AS name_commission_class_description,
    TRIM(CommissionClass)                                AS name_commission_class,

    -- Classification - Freight
    TRIM(FreightClassCode)                               AS code_freight_class,
    TRIM(FreightClassDescription)                        AS name_freight_class_description,
    TRIM(FreightClass)                                   AS name_freight_class,

    -- Classification - Collective
    TRIM(CollectiveClassCode)                            AS code_collective_class,
    TRIM(CollectiveClass)                                AS name_collective_class,

    -- Office & Origin
    TRIM(ResponsibleOffice)                              AS code_responsible_office,
    TRIM(`Import/DomesticCode`)                          AS code_import_domestic,
    TRIM(CountryofOrigin)                                AS name_country_of_origin,
    TRIM(CEXCode)                                        AS code_cex,

    -- Status
    TRIM(AFIItemStatus)                                  AS code_afi_item_status,
    TRIM(ManufacturingStatus)                            AS code_manufacturing_status,
    TRIM(CurrentSCPManufacturingStatus)                  AS code_current_scp_manufacturing_status,
    TRIM(MarketingItemStatus)                            AS code_marketing_item_status,
    TRIM(MarketingStatusDescription)                     AS name_marketing_status,
    TRIM(CurrentStatus)                                  AS code_current_status,
    CAST(ManufacturingStatusChangeDate AS DATE)          AS dt_manufacturing_status_change,

    -- Flags
    CASE WHEN LOWER(TRIM(MainPieceItem)) = 'true' THEN true ELSE false END   AS is_main_piece,
    CAST(CommodityItem AS INT)                           AS num_commodity_item,
    TRIM(SellableItemFlag)                               AS code_sellable_item,
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

    -- Market
    TRIM(MarketIntroducedAt)                             AS name_market_introduced_at,
    CAST(MarketBeginDate AS DATE)                        AS dt_market_begin,
    CAST(MarketEndDate AS DATE)                          AS dt_market_end,

    -- Pricing
    CAST(FOBPrice AS DECIMAL(14,3))                      AS amt_fob_price,
    TRIM(GoodBetterBestForPricePoint)                    AS code_good_better_best,
    CAST(GBBSortId AS INT)                               AS num_gbb_sort,

    -- Vendor
    TRIM(PrimaryVendor)                                  AS code_primary_vendor,
    TRIM(PrimaryVendorName)                              AS name_primary_vendor,

    -- Invoice & Forecast
    TRIM(InitialInvoicePeriod)                           AS code_initial_invoice_period,
    CAST(InitialInvoiceQty AS INT)                       AS qty_initial_invoice,
    TRIM(ItemForecastPlannerID)                          AS id_item_forecast_planner,

    -- Package / Main Piece
    TRIM(MainPiece)                                      AS code_main_piece

FROM raw_source
WHERE ItemSKU IS NOT NULL
    AND ItemSKU <> "N/A"
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

