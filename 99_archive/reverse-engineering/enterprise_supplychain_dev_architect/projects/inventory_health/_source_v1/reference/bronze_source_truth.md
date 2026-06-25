# Bronze Source Truth — Real Column Reference

Probed 25 target tables across `Enterprise_Lakehouse` + `SupplyChain_Lakehouse`.

## Summary

| # | Database | Schema | Table | Status | Rows | Cols | Purpose |
|---|---|---|---|---|---|---|---|
| 1 | `Enterprise_Lakehouse` | `MasterData_DW` | `DimItemMaster` | ✅ exists | 382,302 | 173 | Item dim + AfiItemStatus + FOB + Cubes |
| 2 | `Enterprise_Lakehouse` | `MasterData_DW` | `DimDate` | ✅ exists | 21,551 | 72 | Date dim + fiscal week/month |
| 3 | `Enterprise_Lakehouse` | `Wholesale_Codis_AFI` | `AshleyWarehouseMaster` | ✅ exists | 54 | 29 | Warehouse dim + IntransitWarehouse mapping |
| 4 | `Enterprise_Lakehouse` | `Purchasing_AFI` | `VendorMaster` | ✅ exists | 86,598 | 51 | Vendor name lookup |
| 5 | `Enterprise_Lakehouse` | `ItemMaster_AFI` | `ITEMBL` | ✅ exists | 3,411,561 | 124 | Current on-hand (MOHTQ), item class |
| 6 | `Enterprise_Lakehouse` | `ItemMaster_AFI` | `ITMRVA` | ✅ exists | 2,897,198 | 122 | Standard cost UCDEF (STID='000') |
| 7 | `Enterprise_Lakehouse` | `ItemMaster_AFI` | `ITBEXT` | ✅ exists | 3,389,222 | 50 | MFPUS unavailable status (only usable col) |
| 8 | `Enterprise_Lakehouse` | `SupplyChain_Enh_1` | `DemandInventorySnapshotWeekly` | ✅ exists | 557,141,256 | 31 | Weekly inventory snapshot (557M) |
| 9 | `Enterprise_Lakehouse` | `SupplyChain_Enh_1` | `DemandForecastSnapshotWeekly` | ✅ exists | 306,173,656 | 23 | Weekly forecast snapshot (306M, channel split) |
| 10 | `Enterprise_Lakehouse` | `Wholesale_Purchasing_AFI` | `ATPSUM` | ✅ exists | 296,744 | 119 | ATP wide (APAT01-27, APWK01-27) |
| 11 | `Enterprise_Lakehouse` | `Wholesale_DemandPlanning_AFI` | `SupplyForecast` | ✅ exists | 921,060 | 7 | Current forecast (FCST_RSLT_QTY) |
| 12 | `Enterprise_Lakehouse` | `Wholesale_DemandPlanning_AFI` | `SupplyPlanDetail` | ✅ exists | 3,877,267 | 27 | Supply plan current (spdShippableInventory) |
| 13 | `Enterprise_Lakehouse` | `Wholesale_DemandPlanning_AFI` | `DemandInventory` | ✅ exists | 3,829,284 | 31 | Current safety stock alternative (3.66M) |
| 14 | `Enterprise_Lakehouse` | `SalesHistory_AFI` | `InvoiceDetail` | ✅ exists | 128,309,247 | 80 | Sales shipment (127.7M) |
| 15 | `Enterprise_Lakehouse` | `Manufacturing_ProductionPlanning_AFI` | `MOMAST` | ✅ exists | 251,596 | 71 | Manufacturing order (FITEM, FITWH, OSTAT) |
| 16 | `Enterprise_Lakehouse` | `Manufacturing_Inventory_AFI` | `TFRDTL` | ✅ exists | 675,462 | 19 | Transfer detail (holding transfer) |
| 17 | `Enterprise_Lakehouse` | `Manufacturing_Inventory_AFI` | `TFRHDR` | ✅ exists | 26,135 | 20 | Transfer header (HFHOUS/HTHOUS/HCANCL) |
| 18 | `Enterprise_Lakehouse` | `Manufacturing_Inventory_AFI` | `IMHIST` | ✅ exists | 11,664,291 | 105 | Movement history (TCODE, TRNDT) |
| 19 | `Enterprise_Lakehouse` | `CustomerOrders_AFI` | `OpenOrderDetail` | ✅ exists | 918,213 | 66 | Customer open orders (ItemAllocationFlag) |
| 20 | `Enterprise_Lakehouse` | `CustomerOrders_AFI` | `OpenOrderHeader` | ✅ exists | 219,900 | 15 | Customer order header |
| 21 | `Enterprise_Lakehouse` | `Wholesale_ProductSourcing_AFI` | `PoDetail` | ✅ exists | 0 | 53 | PO detail Enterprise (was 0 rows; reload pending) |
| 22 | `Enterprise_Lakehouse` | `Wholesale_ProductSourcing_AFI` | `Container` | ✅ exists | 299,485 | 39 | Container tracking |
| 23 | `SupplyChain_Lakehouse` | `dbo` | `podetail_v2` | ✅ exists | 21,923,551 | 53 | PO detail replacement (21.9M) |
| 24 | `SupplyChain_Lakehouse` | `dbo` | `pomaster` | ✅ exists | 5,681,305 | 75 | PO header replacement (5.67M) |
| 25 | `SupplyChain_Lakehouse` | `dbo` | `logility_demandfulfillment` | ✅ exists | 38,356,303 | 53 | Logility historical (38.36M, 9128 dup) |

---

## Per-table column detail

### `Enterprise_Lakehouse.MasterData_DW.DimItemMaster`
- Purpose: Item dim + AfiItemStatus + FOB + Cubes
- KPI usage: All Item-grain KPIs
- Row count: 382,302
- Columns (173):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `RowID` | bigint | N |
| 2 | `ItemSKU` | varchar | N |
| 3 | `ItemKey` | varchar | N |
| 4 | `Item` | varchar | Y |
| 5 | `ItemCode` | varchar | Y |
| 6 | `SeriesNumber` | varchar | Y |
| 7 | `ExtSeriesNumber` | varchar | Y |
| 8 | `FrameNumber` | varchar | Y |
| 9 | `QtyInBox` | decimal | Y |
| 10 | `UOM` | varchar | Y |
| 11 | `ProductHeightMeters` | decimal | Y |
| 12 | `ProductWidthMeters` | decimal | Y |
| 13 | `ProductDepthMeters` | decimal | Y |
| 14 | `CartonHeightMeters` | decimal | Y |
| 15 | `CartonWidthMeters` | decimal | Y |
| 16 | `CartonDepthMeters` | decimal | Y |
| 17 | `ProductHeightInches` | decimal | Y |
| 18 | `ProductWidthInches` | decimal | Y |
| 19 | `ProductDepthInches` | decimal | Y |
| 20 | `CartonHeightInches` | decimal | Y |
| 21 | `CartonWidthInches` | decimal | Y |
| 22 | `CartonDepthInches` | decimal | Y |
| 23 | `Cubes` | decimal | Y |
| 24 | `Seats` | decimal | Y |
| 25 | `ItemDescription` | varchar | Y |
| 26 | `SeriesName` | varchar | Y |
| 27 | `SeriesColor` | varchar | Y |
| 28 | `Colors` | varchar | Y |
| 29 | `ItemDescriptionSeries` | varchar | Y |
| 30 | `SHItemDescriptionSeries` | varchar | Y |
| 31 | `SHSeriesDescription` | varchar | Y |
| 32 | `ItemDescriptionSeriesItemColor` | varchar | Y |
| 33 | `ChildStyleDescription` | varchar | Y |
| 34 | `ParentStyleDescription` | varchar | Y |
| 35 | `SeriesDescription` | varchar | Y |
| 36 | `ItemName` | varchar | Y |
| 37 | `ItemConsumerDescription` | varchar | Y |
| 38 | `RetailTypeDescription` | varchar | Y |
| 39 | `MainPieceItem` | varchar | Y |
| 40 | `ItemClass` | varchar | Y |
| 41 | `ItemClassCode` | varchar | Y |
| 42 | `ItemClassName` | varchar | Y |
| 43 | `ProductLine` | varchar | Y |
| 44 | `RetailCategoryCode` | varchar | Y |
| 45 | `RetailCategoryDescription` | varchar | Y |
| 46 | `RetailCategoryName` | varchar | Y |
| 47 | `RetailDepartmentName` | varchar | Y |
| 48 | `RetailCategoryGroup` | varchar | Y |
| 49 | `RetailCategoryChargeType` | varchar | Y |
| 50 | `AFIFinanceDivision` | varchar | Y |
| 51 | `AFIFinanceDivisionCode` | varchar | Y |
| 52 | `AFISalesCategoryCode` | varchar | Y |
| 53 | `AFISalesCategory` | varchar | Y |
| 54 | `ItemStyleCode` | varchar | Y |
| 55 | `ItemStyleGroup` | varchar | Y |
| 56 | `ItemStyle` | varchar | Y |
| 57 | `Division` | varchar | Y |
| 58 | `AFISalesDivisionCode` | varchar | Y |
| 59 | `AFISalesDivision` | varchar | Y |
| 60 | `KeyItem` | bit | Y |
| 61 | `ItemType` | varchar | Y |
| 62 | `SalesClassCode` | varchar | Y |
| 63 | `SalesClassDescription` | varchar | Y |
| 64 | `SalesClass` | varchar | Y |
| 65 | `DiscountClassCode` | varchar | Y |
| 66 | `DiscountClassDescription` | varchar | Y |
| 67 | `DiscountClass` | varchar | Y |
| 68 | `CommissionClassCode` | varchar | Y |
| 69 | `CommissionClassDescription` | varchar | Y |
| 70 | `CommissionClass` | varchar | Y |
| 71 | `FreightClassCode` | varchar | Y |
| 72 | `FreightClassDescription` | varchar | Y |
| 73 | `FreightClass` | varchar | Y |
| 74 | `AFIItemStatus` | varchar | Y |
| 75 | `SellableItemFlag` | varchar | Y |
| 76 | `ManufacturingStatus` | varchar | Y |
| 77 | `ResponsibleOffice` | varchar | Y |
| 78 | `ResponsibleOfficeName` | varchar | Y |
| 79 | `ImportDomesticCode` | varchar | Y |
| 80 | `CountryofOrigin` | varchar | Y |
| 81 | `PrimaryVendor` | varchar | Y |
| 82 | `ManufacturingStatusChangeDate` | date | Y |
| 83 | `ItemForecastPlannerID` | varchar | Y |
| 84 | `NewItemFlag` | bit | Y |
| 85 | `DiscontinuedFlag` | bit | Y |
| 86 | `DiscontinuedYearPeriod` | varchar | Y |
| 87 | `CommonCarrierFlag` | varchar | Y |
| 88 | `ExpressShipFlag` | varchar | Y |
| 89 | `DiscontinuedDate` | date | Y |
| 90 | `SeriesDateArchived` | date | Y |
| 91 | `SeriesDiscontinuedFlag` | bit | Y |
| 92 | `PreviousStatusCode` | varchar | Y |
| 93 | `StatusCodeChangeDate` | date | Y |
| 94 | `CurrentUnitCost` | decimal | Y |
| 95 | `CEXCode` | varchar | Y |
| 96 | `MarketIntroducedAt` | varchar | Y |
| 97 | `MerchandisingCategory` | smallint | Y |
| 98 | `PricePoint` | int | Y |
| 99 | `ItemGrouping` | varchar | Y |
| 100 | `SeriesGrouping` | smallint | Y |
| 101 | `MasterGroupCode` | varchar | Y |
| 102 | `AssociationCode` | varchar | Y |
| 103 | `MarketingItemStatus` | varchar | Y |
| 104 | `MarketingStatusDescription` | varchar | Y |
| 105 | `Lifestyle` | varchar | Y |
| 106 | `CommodityItem` | bit | Y |
| 107 | `F123ProductFlag` | bit | Y |
| 108 | `HSCoreProductFlag` | bit | Y |
| 109 | `HSProprietaryProductFlag` | bit | Y |
| 110 | `HSExclusiveFlag` | bit | Y |
| 111 | `BerklineProductFlag` | bit | Y |
| 112 | `BenchcraftProductFlag` | bit | Y |
| 113 | `NewMillenniumProductFlag` | bit | Y |
| 114 | `BardiniProductFlag` | bit | Y |
| 115 | `ShanghaiStore` | bit | Y |
| 116 | `DefaultGroup` | bit | Y |
| 117 | `GoodBetterBestForPricePoint` | varchar | Y |
| 118 | `GBBSortId` | int | Y |
| 119 | `InitialInvoicePeriod` | varchar | Y |
| 120 | `InitialInvoiceQty` | decimal | Y |
| 121 | `MarketBeginDate` | date | Y |
| 122 | `MarketEndDate` | date | Y |
| 123 | `Showroom` | varchar | Y |
| 124 | `ItemImage` | varchar | Y |
| 125 | `FOBArcPrice` | decimal | Y |
| 126 | `DivisionRanking` | int | Y |
| 127 | `TrendArrow` | varchar | Y |
| 128 | `ItemMerchGridOverridePhoto` | varchar | Y |
| 129 | `GroupPriceIncr` | decimal | Y |
| 130 | `GroupPricePointType` | varchar | Y |
| 131 | `ExclusiveComment` | varchar | Y |
| 132 | `SeriesImage` | varchar | Y |
| 133 | `SofaTableSeriesFlag` | varchar | Y |
| 134 | `ReclinerSeriesFlag` | varchar | Y |
| 135 | `PowerMotionSeriesFlag` | varchar | Y |
| 136 | `WedgeSeriesFlag` | varchar | Y |
| 137 | `DiningSeriesFlag` | varchar | Y |
| 138 | `ItemThirdPartyItem` | varchar | Y |
| 139 | `SeriesThirdParty` | varchar | Y |
| 140 | `ItemHomeStoreProductLine` | varchar | Y |
| 141 | `ItemEcomMerchantNotes` | varchar | Y |
| 142 | `ItemAmazonBrandOwner` | varchar | Y |
| 143 | `ItemSupplierDirectShipOnly` | varchar | Y |
| 144 | `ConsumerChoiceFlag` | varchar | Y |
| 145 | `EligibleForProtectionPlan` | varchar | Y |
| 146 | `IsProtectionPlan` | varchar | Y |
| 147 | `CollectiveClass` | varchar | Y |
| 148 | `FriendlyDimensions` | varchar | Y |
| 149 | `Knockout` | varchar | Y |
| 150 | `Scene7ImageSet` | varchar | Y |
| 151 | `FluffAFI` | varchar | Y |
| 152 | `SeriesPrimary` | varchar | Y |
| 153 | `SeriesMainImage` | varchar | Y |
| 154 | `StandAloneFlag` | varchar | Y |
| 155 | `SuppWeightNetWeightLbs` | varchar | Y |
| 156 | `UnitWeightLbs` | varchar | Y |
| 157 | `UPC` | varchar | Y |
| 158 | `RetailBrandName` | varchar | Y |
| 159 | `MfgWarranty` | varchar | Y |
| 160 | `Material` | varchar | Y |
| 161 | `SeriesFeatures` | varchar | Y |
| 162 | `ItemIsRTA` | varchar | Y |
| 163 | `PrimaryChannelSku` | varchar | Y |
| 164 | `PrimarySeriesName` | varchar | Y |
| 165 | `PrimarySeriesNumber` | varchar | Y |
| 166 | `ERetailChannelSku` | varchar | Y |
| 167 | `ERetailSeriesName` | varchar | Y |
| 168 | `ERetailSeriesNumber` | varchar | Y |
| 169 | `ItemTableShapeType` | varchar | Y |
| 170 | `ItemBedSizeType` | varchar | Y |
| 171 | `ItemBedStyleType` | varchar | Y |
| 172 | `ItemGeneralColor` | varchar | Y |
| 173 | `ItemPricePointRating` | varchar | Y |

### `Enterprise_Lakehouse.MasterData_DW.DimDate`
- Purpose: Date dim + fiscal week/month
- KPI usage: All time-grain KPIs
- Row count: 21,551
- Columns (72):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `DateKey` | int | N |
| 2 | `MapicsDate` | int | Y |
| 3 | `DateID` | date | N |
| 4 | `DateTimeID` | date | N |
| 5 | `CalendarDate` | date | N |
| 6 | `CalendarDateName` | varchar | Y |
| 7 | `CalendarDateIndicator` | int | Y |
| 8 | `CalendarWeek` | int | Y |
| 9 | `CalendarWeekIndicator` | int | Y |
| 10 | `CalendarWeekYear` | int | Y |
| 11 | `CalendarWeekYearName` | varchar | Y |
| 12 | `CalendarDayOfWeek` | int | Y |
| 13 | `CalendarDayOfWeekName` | varchar | Y |
| 14 | `CalendarWeekFirstDate` | date | Y |
| 15 | `CalendarWeekLastDate` | date | Y |
| 16 | `CalendarMonth` | int | Y |
| 17 | `CalendarMonthIndicator` | int | Y |
| 18 | `CalendarMonthYear` | int | Y |
| 19 | `CalendarMonthName` | varchar | Y |
| 20 | `CalendarMonthYearName` | varchar | Y |
| 21 | `CalendarDayOfMonth` | int | Y |
| 22 | `CalendarWeekOfMonth` | int | Y |
| 23 | `CalendarMonthFirstDate` | date | Y |
| 24 | `CalendarMonthLastDate` | date | Y |
| 25 | `CalendarQuarter` | int | Y |
| 26 | `CalendarQuarterName` | varchar | Y |
| 27 | `CalendarQuarterIndicator` | int | Y |
| 28 | `CalendarQuarterYear` | smallint | Y |
| 29 | `CalendarQuarterYearName` | varchar | Y |
| 30 | `CalendarSemester` | int | Y |
| 31 | `CalendarSemesterYear` | smallint | Y |
| 32 | `CalendarYear` | smallint | Y |
| 33 | `CalendarYearName` | varchar | Y |
| 34 | `CalendarYearIndicator` | int | Y |
| 35 | `CalendarDayOfYear` | smallint | Y |
| 36 | `FiscalDate` | date | Y |
| 37 | `FiscalDateName` | varchar | Y |
| 38 | `FiscalDateIndicator` | int | Y |
| 39 | `FiscalWeek` | int | Y |
| 40 | `FiscalWeekIndicator` | int | Y |
| 41 | `FiscalDayOfWeek` | int | Y |
| 42 | `FiscalDayOfWeekName` | varchar | Y |
| 43 | `FiscalWeekYear` | int | Y |
| 44 | `FiscalWeekYearName` | varchar | Y |
| 45 | `FiscalWeekFirstDate` | date | Y |
| 46 | `FiscalWeekLastDate` | date | Y |
| 47 | `FiscalMonth` | int | Y |
| 48 | `FiscalMonthIndicator` | int | Y |
| 49 | `FiscalMonthYear` | int | Y |
| 50 | `FiscalMonthName` | varchar | Y |
| 51 | `FiscalMonthYearName` | varchar | Y |
| 52 | `FiscalDayOfMonth` | int | Y |
| 53 | `FiscalWeekOfMonth` | int | Y |
| 54 | `FiscalMonthFirstDate` | date | Y |
| 55 | `FiscalMonthLastDate` | date | Y |
| 56 | `FiscalQuarter` | int | Y |
| 57 | `FiscalQuarterName` | varchar | Y |
| 58 | `FiscalQuarterIndicator` | int | Y |
| 59 | `FiscalQuarterYear` | smallint | Y |
| 60 | `FiscalQuarterYearName` | varchar | Y |
| 61 | `FiscalSemester` | int | Y |
| 62 | `FiscalSemesterYear` | smallint | Y |
| 63 | `FiscalYear` | smallint | Y |
| 64 | `FiscalYearName` | varchar | Y |
| 65 | `FiscalYearIndicator` | int | Y |
| 66 | `FiscalDayOfYear` | smallint | Y |
| 67 | `FiscalYearFirstDate` | date | Y |
| 68 | `FiscalYearLastDate` | date | Y |
| 69 | `HolidayIndicator` | varchar | Y |
| 70 | `HolidayName` | varchar | Y |
| 71 | `WorkingDayIndicator` | varchar | Y |
| 72 | `WeekdayWeekend` | varchar | Y |

### `Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster`
- Purpose: Warehouse dim + IntransitWarehouse mapping
- KPI usage: All WH-grain KPIs
- Row count: 54
- Columns (29):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `wmaWarehouse` | varchar | Y |
| 2 | `wmaLocationId` | decimal | Y |
| 3 | `wmaIntransitWarehouse` | varchar | Y |
| 4 | `wmaSiteId` | varchar | Y |
| 5 | `wmaMROSiteId` | varchar | Y |
| 6 | `wmaWarehouseType` | varchar | Y |
| 7 | `wmaWarehouseOrderGroup` | varchar | Y |
| 8 | `wmaWarehouseSourceId` | varchar | Y |
| 9 | `wmaRouteType` | varchar | Y |
| 10 | `wmaDefaultPortId` | int | Y |
| 11 | `wmaControlled` | bit | Y |
| 12 | `wmaPrinterName` | varchar | Y |
| 13 | `wmaZebraPrinter` | varchar | Y |
| 14 | `wmaSendBolsToManu` | varchar | Y |
| 15 | `wmaOrderReleaseMin` | int | Y |
| 16 | `wmaOrderReleaseMinType` | varchar | Y |
| 17 | `wmaDefaultShipId` | int | Y |
| 18 | `wmaSortOrder` | int | Y |
| 19 | `wmaAsOverhead` | int | Y |
| 20 | `wmaAsFreight` | int | Y |
| 21 | `wmaContainerDirectWhse` | varchar | Y |
| 22 | `acrec` | varchar | Y |
| 23 | `usra` | varchar | Y |
| 24 | `dtea` | datetime2 | Y |
| 25 | `usrc` | varchar | Y |
| 26 | `dtec` | datetime2 | Y |
| 27 | `wmaWhereMade` | varchar | Y |
| 28 | `wmaManufacturingSite` | varchar | Y |
| 29 | `wmaSellableWarehouse` | bit | Y |

### `Enterprise_Lakehouse.Purchasing_AFI.VendorMaster`
- Purpose: Vendor name lookup
- KPI usage: Vendor dim
- Row count: 86,598
- Columns (51):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `VendorNumber` | varchar | Y |
| 2 | `VendorName` | varchar | Y |
| 3 | `NameAbbreviaton` | varchar | Y |
| 4 | `Address1` | varchar | Y |
| 5 | `Address2` | varchar | Y |
| 6 | `City` | varchar | Y |
| 7 | `State` | varchar | Y |
| 8 | `ZipCode` | varchar | Y |
| 9 | `Country` | varchar | Y |
| 10 | `PhoneNumber` | varchar | Y |
| 11 | `FaxNumber` | varchar | Y |
| 12 | `AmountToDate` | decimal | Y |
| 13 | `AmountYTD` | decimal | Y |
| 14 | `AmountLastYear` | decimal | Y |
| 15 | `LastPaymentDate` | decimal | Y |
| 16 | `DiscountsYTD` | decimal | Y |
| 17 | `DiscountsLastYear` | decimal | Y |
| 18 | `DiscountsLostYTD` | decimal | Y |
| 19 | `DiscountsLostLastyear` | decimal | Y |
| 20 | `DateLastMaintained` | decimal | Y |
| 21 | `TaxID` | varchar | Y |
| 22 | `NEC_AmountYTD` | decimal | Y |
| 23 | `NEC_AmountLastYear` | decimal | Y |
| 24 | `TermsCode` | varchar | Y |
| 25 | `TermsDescription` | varchar | Y |
| 26 | `MultiLinePOFlag` | varchar | Y |
| 27 | `Contact` | varchar | Y |
| 28 | `ClosedAcknowledgementFlag` | varchar | Y |
| 29 | `MultiShiptoFlag` | varchar | Y |
| 30 | `ContractNumber` | varchar | Y |
| 31 | `LastVendorRating` | decimal | Y |
| 32 | `AverageVendorRating` | decimal | Y |
| 33 | `BlanketAllowed` | varchar | Y |
| 34 | `POAcceptanceFlag` | varchar | Y |
| 35 | `AssigneeNumber` | varchar | Y |
| 36 | `POSuspendedForVendor` | varchar | Y |
| 37 | `FreeOnBoardCode` | varchar | Y |
| 38 | `FreeOnBoardDescription` | varchar | Y |
| 39 | `CurrencyCode` | varchar | Y |
| 40 | `TaxSuffix` | varchar | Y |
| 41 | `SalesTaxID1` | varchar | Y |
| 42 | `SalesTaxID2` | varchar | Y |
| 43 | `EnterpriseCode` | varchar | Y |
| 44 | `ShipViaCode` | varchar | Y |
| 45 | `ShipViaDescription` | varchar | Y |
| 46 | `OurCustomerNumber` | varchar | Y |
| 47 | `PaymentMethodCode` | varchar | Y |
| 48 | `UserFieldA` | varchar | Y |
| 49 | `UserFieldC` | varchar | Y |
| 50 | `UserFieldT25` | varchar | Y |
| 51 | `EmailAddress` | varchar | Y |

### `Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL`
- Purpose: Current on-hand (MOHTQ), item class
- KPI usage: OnHand, Transfer InTransit, Inv Value
- Row count: 3,411,561
- Columns (124):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `CREC` | varchar | N |
| 2 | `ITNBR` | varchar | N |
| 3 | `HOUSE` | varchar | N |
| 4 | `ITCLS` | varchar | N |
| 5 | `MALQT` | decimal | N |
| 6 | `QTSMO` | decimal | N |
| 7 | `ISSMO` | decimal | N |
| 8 | `RECMO` | decimal | N |
| 9 | `ADJMO` | decimal | N |
| 10 | `BEGIN` | decimal | N |
| 11 | `LTCOD` | varchar | N |
| 12 | `LTMAN` | decimal | N |
| 13 | `LTADM` | decimal | N |
| 14 | `LTPUR` | decimal | N |
| 15 | `LTVEN` | decimal | N |
| 16 | `LTSAF` | decimal | N |
| 17 | `LTREV` | decimal | N |
| 18 | `LTADP` | decimal | N |
| 19 | `MOHTQ` | decimal | N |
| 20 | `AVCST` | decimal | N |
| 21 | `LCOST` | decimal | N |
| 22 | `STDUC` | decimal | N |
| 23 | `ORDPT` | decimal | N |
| 24 | `FXORQ` | decimal | N |
| 25 | `SAFTY` | decimal | N |
| 26 | `MPRPQ` | decimal | N |
| 27 | `MPUPQ` | decimal | N |
| 28 | `USEYR` | decimal | N |
| 29 | `LACDT` | decimal | N |
| 30 | `LDQOH` | decimal | N |
| 31 | `CCFLG` | varchar | N |
| 32 | `CCOMP` | decimal | N |
| 33 | `CCODE` | decimal | N |
| 34 | `CCTRN` | decimal | N |
| 35 | `LPHDT` | decimal | N |
| 36 | `NXCDT` | decimal | N |
| 37 | `VNDNR` | varchar | N |
| 38 | `PURUM` | varchar | N |
| 39 | `UMCNV` | decimal | N |
| 40 | `WHSLC` | varchar | N |
| 41 | `AVCDV` | varchar | N |
| 42 | `ISSYR` | decimal | N |
| 43 | `USEMO` | decimal | N |
| 44 | `QTSYR` | decimal | N |
| 45 | `AMSMO` | decimal | N |
| 46 | `AMSYR` | decimal | N |
| 47 | `CAMMO` | decimal | N |
| 48 | `CAMYR` | decimal | N |
| 49 | `CSTMO` | decimal | N |
| 50 | `CSTYR` | decimal | N |
| 51 | `EAANU` | decimal | N |
| 52 | `AVMEB` | decimal | N |
| 53 | `AVSAL` | decimal | N |
| 54 | `DOFLS` | decimal | N |
| 55 | `DOFLU` | decimal | N |
| 56 | `RPFLG` | decimal | N |
| 57 | `CURPL` | decimal | N |
| 58 | `PLREQ` | decimal | N |
| 59 | `PHYOH` | decimal | N |
| 60 | `FLSTK` | varchar | N |
| 61 | `MDATE` | decimal | N |
| 62 | `RECPL` | decimal | N |
| 63 | `PALOC` | decimal | N |
| 64 | `CRPLL` | decimal | N |
| 65 | `FALQT` | decimal | N |
| 66 | `CRPLB` | decimal | N |
| 67 | `CRPLA` | decimal | N |
| 68 | `RCPLB` | decimal | N |
| 69 | `RCPLA` | decimal | N |
| 70 | `FCYCT` | varchar | N |
| 71 | `MPALC` | decimal | N |
| 72 | `CMTLT` | decimal | N |
| 73 | `CMFLT` | decimal | N |
| 74 | `LTMAV` | decimal | N |
| 75 | `LTPAV` | decimal | N |
| 76 | `LTVAM` | decimal | N |
| 77 | `SCPMO` | decimal | N |
| 78 | `SCPYR` | decimal | N |
| 79 | `SCCMO` | decimal | N |
| 80 | `SCCYR` | decimal | N |
| 81 | `SCPDT` | decimal | N |
| 82 | `MPSFA` | decimal | N |
| 83 | `SALBF` | decimal | N |
| 84 | `SALAF` | decimal | N |
| 85 | `LPOWU` | varchar | N |
| 86 | `IBCTL` | decimal | N |
| 87 | `SHPLP` | decimal | N |
| 88 | `RECLP` | decimal | N |
| 89 | `ITFLG` | decimal | N |
| 90 | `ALCTL` | decimal | N |
| 91 | `SCHCD` | decimal | N |
| 92 | `EXTCD` | varchar | N |
| 93 | `CFWCD` | decimal | N |
| 94 | `PRLIN` | varchar | N |
| 95 | `SUMCD` | varchar | N |
| 96 | `SCHGP` | varchar | N |
| 97 | `SMHCD` | varchar | N |
| 98 | `SMHDT` | decimal | N |
| 99 | `CONDS` | varchar | N |
| 100 | `CONQT` | decimal | N |
| 101 | `MODCD` | varchar | N |
| 102 | `FGICD` | decimal | N |
| 103 | `CNTLP` | varchar | N |
| 104 | `ACALW` | varchar | N |
| 105 | `BOMLW` | varchar | N |
| 106 | `PLANIB` | decimal | N |
| 107 | `FRQTIB` | decimal | N |
| 108 | `ININ` | varchar | N |
| 109 | `ITACIB` | varchar | N |
| 110 | `LOTZIB` | varchar | N |
| 111 | `BFFL` | decimal | N |
| 112 | `UUSAIB` | varchar | N |
| 113 | `UUSBIB` | varchar | N |
| 114 | `UUCAIB` | varchar | N |
| 115 | `UUCBIB` | varchar | N |
| 116 | `UUCCIB` | varchar | N |
| 117 | `UUQ1IB` | decimal | N |
| 118 | `UUA1IB` | decimal | N |
| 119 | `UUD1IB` | decimal | N |
| 120 | `UU40IB` | varchar | N |
| 121 | `UUIAIB` | varchar | N |
| 122 | `STCF` | varchar | N |
| 123 | `CCCL` | varchar | N |
| 124 | `COTP` | decimal | N |

### `Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA`
- Purpose: Standard cost UCDEF (STID='000')
- KPI usage: Std Cost, COGS, Inv Value@Cost
- Row count: 2,897,198
- Columns (122):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `STID` | varchar | Y |
| 2 | `ITNBR` | varchar | Y |
| 3 | `ITRV` | varchar | Y |
| 4 | `CFST` | varchar | Y |
| 5 | `EDAT` | decimal | Y |
| 6 | `EATO` | decimal | Y |
| 7 | `RECID` | varchar | Y |
| 8 | `INVFG` | decimal | Y |
| 9 | `NOPWU` | decimal | Y |
| 10 | `RACNO` | decimal | Y |
| 11 | `FOTAB` | decimal | Y |
| 12 | `ITDSC` | varchar | Y |
| 13 | `ENGNO` | varchar | Y |
| 14 | `RTGID` | varchar | Y |
| 15 | `UCDEF` | decimal | Y |
| 16 | `UNMSR` | varchar | Y |
| 17 | `ITTYP` | varchar | Y |
| 18 | `ITCLS` | varchar | Y |
| 19 | `VALUC` | varchar | Y |
| 20 | `VNDNR` | varchar | Y |
| 21 | `WHSLC` | varchar | Y |
| 22 | `DPTNO` | varchar | Y |
| 23 | `WEGHT` | decimal | Y |
| 24 | `STDSU` | decimal | Y |
| 25 | `CARRY` | decimal | Y |
| 26 | `SNFLG` | varchar | Y |
| 27 | `SAFLG` | decimal | Y |
| 28 | `PACKC` | varchar | Y |
| 29 | `RECAF` | decimal | Y |
| 30 | `QTYWK` | decimal | Y |
| 31 | `LVNDN` | varchar | Y |
| 32 | `LPLAN` | decimal | Y |
| 33 | `QCTYP` | decimal | Y |
| 34 | `QCDAY` | decimal | Y |
| 35 | `INTYP` | decimal | Y |
| 36 | `BLCF` | decimal | Y |
| 37 | `ALLOC` | decimal | Y |
| 38 | `ITD20` | varchar | Y |
| 39 | `ITD10` | varchar | Y |
| 40 | `MDTAG` | varchar | Y |
| 41 | `PTAXI` | varchar | Y |
| 42 | `STAXI` | varchar | Y |
| 43 | `IPRAF` | decimal | Y |
| 44 | `ITAC` | varchar | Y |
| 45 | `UUSA` | varchar | Y |
| 46 | `UUSB` | varchar | Y |
| 47 | `UUSC` | varchar | Y |
| 48 | `UUCA` | varchar | Y |
| 49 | `UUCB` | varchar | Y |
| 50 | `UUCC` | varchar | Y |
| 51 | `UUQ1` | decimal | Y |
| 52 | `UUA1` | decimal | Y |
| 53 | `UUD1` | decimal | Y |
| 54 | `UU25` | varchar | Y |
| 55 | `UU40` | varchar | Y |
| 56 | `UVHC` | varchar | Y |
| 57 | `UVMC` | varchar | Y |
| 58 | `UVOC` | varchar | Y |
| 59 | `ADMIN` | varchar | Y |
| 60 | `TXCLS` | varchar | Y |
| 61 | `B2IYST` | varchar | Y |
| 62 | `B2KMVA` | decimal | Y |
| 63 | `B2APPC` | decimal | Y |
| 64 | `B2LBNB` | decimal | Y |
| 65 | `B2IPST` | varchar | Y |
| 66 | `B2IQST` | varchar | Y |
| 67 | `B2AAS2` | decimal | Y |
| 68 | `B2AAS3` | decimal | Y |
| 69 | `B2WSUS` | varchar | Y |
| 70 | `B2MROI` | varchar | Y |
| 71 | `B2ASTP` | varchar | Y |
| 72 | `B2OEMN` | varchar | Y |
| 73 | `B2Z9W3` | varchar | Y |
| 74 | `B2Z9W4` | varchar | Y |
| 75 | `B2Z9W5` | varchar | Y |
| 76 | `B2Z9W6` | decimal | Y |
| 77 | `B2Z9W7` | decimal | Y |
| 78 | `B2C8CD` | varchar | Y |
| 79 | `B2F0CD` | varchar | Y |
| 80 | `B2CQCD` | varchar | Y |
| 81 | `B2HJCD` | varchar | Y |
| 82 | `B2AAPT` | varchar | Y |
| 83 | `B2AAB2` | varchar | Y |
| 84 | `B2COCD` | varchar | Y |
| 85 | `B2ADM1` | varchar | Y |
| 86 | `B2ADSB` | varchar | Y |
| 87 | `B2Z95S` | decimal | Y |
| 88 | `B2Z95T` | decimal | Y |
| 89 | `B2Z93R` | varchar | Y |
| 90 | `BZANVA` | decimal | Y |
| 91 | `BZGNCD` | varchar | Y |
| 92 | `BZBLDT` | decimal | Y |
| 93 | `BZCQCD` | varchar | Y |
| 94 | `CRUS` | varchar | Y |
| 95 | `CRPG` | varchar | Y |
| 96 | `CRDT` | decimal | Y |
| 97 | `CRTM` | decimal | Y |
| 98 | `CHUS` | varchar | Y |
| 99 | `CHPG` | varchar | Y |
| 100 | `CHDE` | decimal | Y |
| 101 | `CHTE` | decimal | Y |
| 102 | `UUIA` | varchar | Y |
| 103 | `SHAP` | varchar | Y |
| 104 | `HITE` | decimal | Y |
| 105 | `LONG` | decimal | Y |
| 106 | `IDIA` | decimal | Y |
| 107 | `ODIA` | decimal | Y |
| 108 | `DUOM` | varchar | Y |
| 109 | `WIDE` | decimal | Y |
| 110 | `APCC` | varchar | Y |
| 111 | `IDMA` | varchar | Y |
| 112 | `IDMO` | varchar | Y |
| 113 | `OEMP` | varchar | Y |
| 114 | `DINS` | varchar | Y |
| 115 | `EMRO` | varchar | Y |
| 116 | `MCTL` | varchar | Y |
| 117 | `REPD` | varchar | Y |
| 118 | `SSRF` | varchar | Y |
| 119 | `SDRF` | varchar | Y |
| 120 | `SDUR` | varchar | Y |
| 121 | `CNFI` | varchar | Y |
| 122 | `CNFG` | varchar | Y |

### `Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT`
- Purpose: MFPUS unavailable status (only usable col)
- KPI usage: UnavailableFlag
- Row count: 3,389,222
- Columns (50):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `ITNBR` | varchar | Y |
| 2 | `HOUSE` | varchar | Y |
| 3 | `MFPUS` | varchar | Y |
| 4 | `CRHLD` | decimal | Y |
| 5 | `DLHLD` | decimal | Y |
| 6 | `TOHLD` | decimal | Y |
| 7 | `ATPQT` | decimal | Y |
| 8 | `WKYAVG` | decimal | Y |
| 9 | `ADJAVG` | decimal | Y |
| 10 | `LEADTM` | decimal | Y |
| 11 | `SHPMTH` | varchar | Y |
| 12 | `SOURCE` | varchar | Y |
| 13 | `MFSDT` | decimal | Y |
| 14 | `PRWTYP` | decimal | Y |
| 15 | `TIHIUNLD` | varchar | Y |
| 16 | `UNITSWIDE` | decimal | Y |
| 17 | `UNITSDEEP` | decimal | Y |
| 18 | `UNITLAYERS` | decimal | Y |
| 19 | `SCOOPWIDTH` | decimal | Y |
| 20 | `ITMCLSID` | varchar | Y |
| 21 | `OFFSITELIG` | varchar | Y |
| 22 | `RCVEQPCLS` | varchar | Y |
| 23 | `OVRFLWBLDG` | varchar | Y |
| 24 | `PICKPUT` | varchar | Y |
| 25 | `PICBLDGCAP` | decimal | Y |
| 26 | `ITBUSRA` | varchar | Y |
| 27 | `ITBDTEA` | decimal | Y |
| 28 | `ITBTMEA` | decimal | Y |
| 29 | `ITBUSRC` | varchar | Y |
| 30 | `ITBDTEC` | decimal | Y |
| 31 | `ITBTMEC` | decimal | Y |
| 32 | `SCOOPQTY` | decimal | Y |
| 33 | `SKIDSIZE` | decimal | Y |
| 34 | `ITBPGMA` | varchar | Y |
| 35 | `ITBPGMC` | varchar | Y |
| 36 | `ITBUC1A` | varchar | Y |
| 37 | `ITBUC1B` | varchar | Y |
| 38 | `ITBUC1C` | varchar | Y |
| 39 | `ITBUC3A` | varchar | Y |
| 40 | `ITBUC3B` | varchar | Y |
| 41 | `ITBUC3C` | varchar | Y |
| 42 | `ITBUC5A` | varchar | Y |
| 43 | `ITBUC5B` | varchar | Y |
| 44 | `ITBUT20` | varchar | Y |
| 45 | `ITBUDA` | decimal | Y |
| 46 | `ITBUNA` | decimal | Y |
| 47 | `ITBUNB` | decimal | Y |
| 48 | `ITBUNC` | decimal | Y |
| 49 | `ITBUQA` | decimal | Y |
| 50 | `ITBUAA` | decimal | Y |

### `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotWeekly`
- Purpose: Weekly inventory snapshot (557M)
- KPI usage: OnHand weekly trend, Safety Stock
- Row count: 557,141,256
- Columns (31):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `dinItem` | varchar | N |
| 2 | `dinWarehouse` | varchar | N |
| 3 | `dinFiscalMonth` | decimal | N |
| 4 | `dinInvPlanningVendor` | varchar | N |
| 5 | `dinDemandPlanner` | varchar | N |
| 6 | `dinSafetyStock` | decimal | N |
| 7 | `dinBuildQuantity` | decimal | N |
| 8 | `dinSnapshot` | datetime2 | Y |
| 9 | `dinIOMinSafetyStock` | decimal | Y |
| 10 | `dinIOMaxSafetyStock` | decimal | Y |
| 11 | `dinIOSafetyStock` | decimal | Y |
| 12 | `dinMakeBuyCode` | varchar | Y |
| 13 | `dinPrimaryVendorNumber` | varchar | Y |
| 14 | `dinPrimaryVendorName` | varchar | Y |
| 15 | `dinPrimaryVendorSplit` | varchar | Y |
| 16 | `dinSecondaryVendorNumber` | varchar | Y |
| 17 | `dinSecondaryVendorName` | varchar | Y |
| 18 | `dinSecondaryVendorSplit` | varchar | Y |
| 19 | `dinInvPlanning4thChoice` | varchar | Y |
| 20 | `dinInvPlanning1stChoice` | varchar | Y |
| 21 | `dinSource1` | varchar | Y |
| 22 | `dinOnHandQuantity` | decimal | Y |
| 23 | `dinOrderQuantity` | decimal | Y |
| 24 | `dinAlternanteABCCode1` | varchar | Y |
| 25 | `dinAlternanteABCCode3` | varchar | Y |
| 26 | `dinInventoryPlanningABCCode` | varchar | Y |
| 27 | `usra` | varchar | Y |
| 28 | `dtea` | datetime2 | Y |
| 29 | `usrc` | varchar | Y |
| 30 | `dtec` | datetime2 | Y |
| 31 | `dinReplenishmentLeadTime` | decimal | Y |

### `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotWeekly`
- Purpose: Weekly forecast snapshot (306M, channel split)
- KPI usage: Forecast Demand, AWD
- Row count: 306,173,656
- Columns (23):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `dfcItem` | varchar | N |
| 2 | `dfcWarehouse` | varchar | N |
| 3 | `dfcFiscalMonth` | decimal | N |
| 4 | `dfcMainPiece` | varchar | N |
| 5 | `dfcCollectiveClass` | varchar | N |
| 6 | `dfcResultantForecast` | decimal | Y |
| 7 | `dfcPromotionalLift` | decimal | Y |
| 8 | `dfcForcedForecast` | decimal | N |
| 9 | `dfcValidDemandMonths` | decimal | N |
| 10 | `dfcSnapshot` | datetime2 | Y |
| 11 | `dfcPermComptQty` | decimal | Y |
| 12 | `dfcUsr25Text` | varchar | Y |
| 13 | `dfcUsr32Text` | varchar | Y |
| 14 | `dfcFCSTTypeCode` | varchar | Y |
| 15 | `dfcDerivedFCSTID` | varchar | Y |
| 16 | `dfcDerivedFCSTFctr` | decimal | Y |
| 17 | `dfcOrderFutureQty` | decimal | Y |
| 18 | `dfcMgmtCode` | varchar | Y |
| 19 | `usra` | varchar | Y |
| 20 | `dtea` | datetime2 | Y |
| 21 | `usrc` | varchar | Y |
| 22 | `dtec` | datetime2 | Y |
| 23 | `DfcCustomerGroups` | varchar | Y |

### `Enterprise_Lakehouse.Wholesale_Purchasing_AFI.ATPSUM`
- Purpose: ATP wide (APAT01-27, APWK01-27)
- KPI usage: ATP In-Stock Rate
- Row count: 296,744
- Columns (119):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `APITNB` | varchar | Y |
| 2 | `APHOUS` | varchar | Y |
| 3 | `APWK01` | decimal | Y |
| 4 | `APAT01` | decimal | Y |
| 5 | `APAT02` | decimal | Y |
| 6 | `APAT03` | decimal | Y |
| 7 | `APAT04` | decimal | Y |
| 8 | `APAT05` | decimal | Y |
| 9 | `APAT06` | decimal | Y |
| 10 | `APAT07` | decimal | Y |
| 11 | `APAT08` | decimal | Y |
| 12 | `APAT09` | decimal | Y |
| 13 | `APAT10` | decimal | Y |
| 14 | `APAT11` | decimal | Y |
| 15 | `APAT12` | decimal | Y |
| 16 | `APAT13` | decimal | Y |
| 17 | `APAT14` | decimal | Y |
| 18 | `APAT15` | decimal | Y |
| 19 | `APAT16` | decimal | Y |
| 20 | `APAT17` | decimal | Y |
| 21 | `APAT18` | decimal | Y |
| 22 | `APAT19` | decimal | Y |
| 23 | `APAT20` | decimal | Y |
| 24 | `APAT21` | decimal | Y |
| 25 | `APAT22` | decimal | Y |
| 26 | `APAT23` | decimal | Y |
| 27 | `APAT24` | decimal | Y |
| 28 | `APAT25` | decimal | Y |
| 29 | `APAT26` | decimal | Y |
| 30 | `APAT27` | decimal | Y |
| 31 | `APAT28` | decimal | Y |
| 32 | `APAT29` | decimal | Y |
| 33 | `APAT30` | decimal | Y |
| 34 | `APAT31` | decimal | Y |
| 35 | `APAT32` | decimal | Y |
| 36 | `APAT33` | decimal | Y |
| 37 | `APAT34` | decimal | Y |
| 38 | `APAT35` | decimal | Y |
| 39 | `APAT36` | decimal | Y |
| 40 | `APAT37` | decimal | Y |
| 41 | `APAT38` | decimal | Y |
| 42 | `APAT39` | decimal | Y |
| 43 | `APAT40` | decimal | Y |
| 44 | `APAT41` | decimal | Y |
| 45 | `APAT42` | decimal | Y |
| 46 | `APAT43` | decimal | Y |
| 47 | `APNQ01` | decimal | Y |
| 48 | `APNQ02` | decimal | Y |
| 49 | `APNQ03` | decimal | Y |
| 50 | `APNQ04` | decimal | Y |
| 51 | `APNQ05` | decimal | Y |
| 52 | `APNQ06` | decimal | Y |
| 53 | `APNQ07` | decimal | Y |
| 54 | `APNQ08` | decimal | Y |
| 55 | `APNQ09` | decimal | Y |
| 56 | `APNQ10` | decimal | Y |
| 57 | `APNQ11` | decimal | Y |
| 58 | `APNQ12` | decimal | Y |
| 59 | `APNQ13` | decimal | Y |
| 60 | `APNQ14` | decimal | Y |
| 61 | `APNQ15` | decimal | Y |
| 62 | `APNQ16` | decimal | Y |
| 63 | `APNQ17` | decimal | Y |
| 64 | `APNQ18` | decimal | Y |
| 65 | `APNQ19` | decimal | Y |
| 66 | `APNQ20` | decimal | Y |
| 67 | `APNQ21` | decimal | Y |
| 68 | `APNQ22` | decimal | Y |
| 69 | `APNQ23` | decimal | Y |
| 70 | `APNQ24` | decimal | Y |
| 71 | `APNQ25` | decimal | Y |
| 72 | `APNQ26` | decimal | Y |
| 73 | `APNQ27` | decimal | Y |
| 74 | `APNQ28` | decimal | Y |
| 75 | `APNQ29` | decimal | Y |
| 76 | `APNQ30` | decimal | Y |
| 77 | `APNQ31` | decimal | Y |
| 78 | `APNQ32` | decimal | Y |
| 79 | `APNQ33` | decimal | Y |
| 80 | `APNQ34` | decimal | Y |
| 81 | `APNQ35` | decimal | Y |
| 82 | `APNQ36` | decimal | Y |
| 83 | `APNQ37` | decimal | Y |
| 84 | `APNQ38` | decimal | Y |
| 85 | `APNQ39` | decimal | Y |
| 86 | `APNQ40` | decimal | Y |
| 87 | `APNQ41` | decimal | Y |
| 88 | `APNQ42` | decimal | Y |
| 89 | `APNQ43` | decimal | Y |
| 90 | `APWH01` | decimal | Y |
| 91 | `APWH02` | decimal | Y |
| 92 | `APWH03` | decimal | Y |
| 93 | `APWH04` | decimal | Y |
| 94 | `APWH05` | decimal | Y |
| 95 | `APTR01` | decimal | Y |
| 96 | `APTR02` | decimal | Y |
| 97 | `APTR03` | decimal | Y |
| 98 | `APTR04` | decimal | Y |
| 99 | `APTR05` | decimal | Y |
| 100 | `APWH06` | decimal | Y |
| 101 | `APWH07` | decimal | Y |
| 102 | `APWH08` | decimal | Y |
| 103 | `APWH09` | decimal | Y |
| 104 | `APWH10` | decimal | Y |
| 105 | `APWH11` | decimal | Y |
| 106 | `APWH12` | decimal | Y |
| 107 | `APWH13` | decimal | Y |
| 108 | `APWH14` | decimal | Y |
| 109 | `APWH15` | decimal | Y |
| 110 | `APTR06` | decimal | Y |
| 111 | `APTR07` | decimal | Y |
| 112 | `APTR08` | decimal | Y |
| 113 | `APTR09` | decimal | Y |
| 114 | `APTR10` | decimal | Y |
| 115 | `APTR11` | decimal | Y |
| 116 | `APTR12` | decimal | Y |
| 117 | `APTR13` | decimal | Y |
| 118 | `APTR14` | decimal | Y |
| 119 | `APTR15` | decimal | Y |

### `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyForecast`
- Purpose: Current forecast (FCST_RSLT_QTY)
- KPI usage: ForecastCurrent, AWD
- Row count: 921,060
- Columns (7):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `FCST_1_ID` | varchar | Y |
| 2 | `FCST_2_ID` | varchar | Y |
| 3 | `FCST_YR_PRD` | decimal | N |
| 4 | `FCST_RSLT_QTY` | decimal | N |
| 5 | `PROMO_LIFT_QTY` | decimal | N |
| 6 | `usra` | varchar | Y |
| 7 | `dtea` | datetime2 | Y |

### `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail`
- Purpose: Supply plan current (spdShippableInventory)
- KPI usage: Revenue at Risk, SI In-Stock
- Row count: 3,877,267
- Columns (27):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `spdItem` | varchar | Y |
| 2 | `spdWarehouse` | varchar | Y |
| 3 | `spdWeekEnding` | date | Y |
| 4 | `spdBeginingBalance` | decimal | Y |
| 5 | `spdFirmDemands` | decimal | Y |
| 6 | `spdNetForecast` | decimal | Y |
| 7 | `spdFirmTransferOut` | decimal | Y |
| 8 | `spdFirmProduction` | decimal | Y |
| 9 | `spdFirmPurchaseOrders` | decimal | Y |
| 10 | `spdInTransitTransferIn` | decimal | Y |
| 11 | `spdOnOrderTransferIn` | decimal | Y |
| 12 | `spdPlannedTransferIn` | decimal | Y |
| 13 | `spdPlannedTransferOut` | decimal | Y |
| 14 | `spdPlannedProduction` | decimal | Y |
| 15 | `spdPlannedPurchaseOrders` | decimal | Y |
| 16 | `spdTotalReceipts` | decimal | Y |
| 17 | `spdShippableInventory` | decimal | Y |
| 18 | `spdSafetyStock` | decimal | Y |
| 19 | `spdMonthsOfSupply` | decimal | Y |
| 20 | `spdResultantForecast` | decimal | Y |
| 21 | `spdPromotionalLift` | decimal | Y |
| 22 | `spdDemandFulfillment` | decimal | Y |
| 23 | `spdWeeklyPromotionalLift` | decimal | Y |
| 24 | `usra` | varchar | Y |
| 25 | `dtea` | datetime2 | Y |
| 26 | `usrc` | varchar | Y |
| 27 | `dtec` | datetime2 | Y |

### `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.DemandInventory`
- Purpose: Current safety stock alternative (3.66M)
- KPI usage: Safety Stock alt
- Row count: 3,829,284
- Columns (31):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `dinItem` | varchar | N |
| 2 | `dinWarehouse` | varchar | N |
| 3 | `dinFiscalMonth` | decimal | N |
| 4 | `dinInvPlanningVendor` | varchar | N |
| 5 | `dinDemandPlanner` | varchar | N |
| 6 | `dinSafetyStock` | decimal | N |
| 7 | `dinBuildQuantity` | decimal | N |
| 8 | `dinSnapshot` | datetime2 | Y |
| 9 | `dinOMinSafetyStock` | decimal | Y |
| 10 | `dinOMaxSafetyStock` | decimal | Y |
| 11 | `dinOSafetyStock` | decimal | Y |
| 12 | `dinMakeBuyCode` | varchar | Y |
| 13 | `dinPrimaryVendorNumber` | varchar | Y |
| 14 | `dinPrimaryVendorName` | varchar | Y |
| 15 | `dinPrimaryVendorSplit` | varchar | Y |
| 16 | `dinSecondaryVendorNumber` | varchar | Y |
| 17 | `dinSecondaryVendorName` | varchar | Y |
| 18 | `dinSecondaryVendorSplit` | varchar | Y |
| 19 | `dinInvPlanning4thChoice` | varchar | Y |
| 20 | `dinInvPlanning1stChoice` | varchar | Y |
| 21 | `dinSource1` | varchar | Y |
| 22 | `dinOnHandQuantity` | decimal | Y |
| 23 | `dinOrderQuantity` | decimal | Y |
| 24 | `dinAlternanteABCCode1` | varchar | Y |
| 25 | `dinAlternanteABCCode3` | varchar | Y |
| 26 | `dinInventoryPlanningABCCode` | varchar | Y |
| 27 | `usra` | varchar | Y |
| 28 | `dtea` | datetime2 | Y |
| 29 | `usrc` | varchar | Y |
| 30 | `dtec` | datetime2 | Y |
| 31 | `dinReplenishmentLeadTime` | decimal | Y |

### `Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail`
- Purpose: Sales shipment (127.7M)
- KPI usage: COGS, SLOB, AWD fallback
- Row count: 128,309,247
- Columns (80):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `CustomerNumber` | varchar | N |
| 2 | `InvoiceNumber` | decimal | N |
| 3 | `ItemSKU` | varchar | N |
| 4 | `ItemSequence` | decimal | Y |
| 5 | `QuantityShipped` | decimal | N |
| 6 | `InvoiceAmount` | decimal | N |
| 7 | `OrderNumber` | varchar | N |
| 8 | `ShiptoNumber` | varchar | N |
| 9 | `QuantityOrdered` | decimal | N |
| 10 | `QuantityBackOrdered` | decimal | N |
| 11 | `CreditCode` | varchar | N |
| 12 | `Warehouse` | varchar | N |
| 13 | `BilltoSalesman` | varchar | N |
| 14 | `ShiptoSalesman` | varchar | N |
| 15 | `Discount` | decimal | N |
| 16 | `PriceAdjustment` | decimal | N |
| 17 | `PostingMonth` | varchar | N |
| 18 | `Freight` | decimal | N |
| 19 | `Price` | decimal | N |
| 20 | `ItemClass` | varchar | N |
| 21 | `ExtendedInvoiceNumber` | varchar | Y |
| 22 | `PurchaseOrder` | varchar | N |
| 23 | `RequestDate` | date | Y |
| 24 | `InvoiceDate` | date | Y |
| 25 | `DefaultDeliveryDays` | varchar | Y |
| 26 | `TripNumber` | decimal | Y |
| 27 | `DropNumber` | decimal | Y |
| 28 | `PromisedDelivery` | date | Y |
| 29 | `OrderEntry` | date | Y |
| 30 | `PriorityCode` | decimal | Y |
| 31 | `OrderItemStatus` | varchar | Y |
| 32 | `OrderPriority` | decimal | Y |
| 33 | `OriginalRequestDate` | date | Y |
| 34 | `ActualDelivery` | date | Y |
| 35 | `CustomerSku` | varchar | Y |
| 36 | `LineReleaseNumber` | varchar | Y |
| 37 | `NetSales` | decimal | Y |
| 38 | `StandardPrice` | decimal | Y |
| 39 | `AdvertisingAccrual` | decimal | Y |
| 40 | `DFIDiscount` | decimal | Y |
| 41 | `ContractPrice` | decimal | Y |
| 42 | `CurrencyCode` | varchar | Y |
| 43 | `DeliveryDays` | int | Y |
| 44 | `DeliveryDaysOriginalPromiseDate` | int | Y |
| 45 | `DeliveryDaysRaw` | int | Y |
| 46 | `DeliveryDaysOriginalPromiseDateRaw` | int | Y |
| 47 | `OriginalInvoiceNumber` | decimal | Y |
| 48 | `OriginalInvoiceDate` | date | Y |
| 49 | `OriginalOrderNumber` | varchar | Y |
| 50 | `OriginalOrderDate` | date | Y |
| 51 | `OriginalSequenceNumber` | decimal | Y |
| 52 | `OriginalDeliveryMethod` | varchar | Y |
| 53 | `OrderType` | varchar | Y |
| 54 | `OrderDate` | date | Y |
| 55 | `OriginalPromiseDate` | date | Y |
| 56 | `CurrentRequestDate` | date | Y |
| 57 | `DeliveryDate` | date | Y |
| 58 | `TripCloseDate` | date | Y |
| 59 | `FirstScanDate` | date | Y |
| 60 | `TripCreateDate` | date | Y |
| 61 | `CurrentPromiseDate` | date | Y |
| 62 | `PriceCode` | varchar | Y |
| 63 | `ItemDiscountCode` | varchar | Y |
| 64 | `commissioncode` | varchar | Y |
| 65 | `FreightCode` | varchar | Y |
| 66 | `DiscountSalesClass` | varchar | Y |
| 67 | `ExceptionID` | decimal | Y |
| 68 | `FreightSalesClass` | varchar | Y |
| 69 | `BuyGroupCode` | varchar | Y |
| 70 | `GroupPricingExceptionID` | decimal | Y |
| 71 | `WarehouseOperationPercent` | decimal | Y |
| 72 | `PriceAdderPercent` | decimal | Y |
| 73 | `CalculatedAllowancePercent` | decimal | Y |
| 74 | `PackageDiscountAllocationPercent` | decimal | Y |
| 75 | `PackageDescription` | varchar | Y |
| 76 | `PackageID` | varchar | Y |
| 77 | `PackagePrice` | decimal | Y |
| 78 | `PackageItemPrice` | decimal | Y |
| 79 | `PackageItemDiscount` | decimal | Y |
| 80 | `OrderType3` | varchar | Y |

### `Enterprise_Lakehouse.Manufacturing_ProductionPlanning_AFI.MOMAST`
- Purpose: Manufacturing order (FITEM, FITWH, OSTAT)
- KPI usage: MO On Order
- Row count: 251,596
- Columns (71):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `ORDNO` | varchar | Y |
| 2 | `ORQTY` | decimal | Y |
| 3 | `QTDEV` | decimal | Y |
| 4 | `QTYRC` | decimal | Y |
| 5 | `JOBNO` | varchar | Y |
| 6 | `REFNO` | varchar | Y |
| 7 | `ODUDT` | decimal | Y |
| 8 | `FITEM` | varchar | Y |
| 9 | `FITWH` | varchar | Y |
| 10 | `SEQNM` | decimal | Y |
| 11 | `ENGNO` | varchar | Y |
| 12 | `VRNV` | varchar | Y |
| 13 | `ITRV` | varchar | Y |
| 14 | `IPMO` | varchar | Y |
| 15 | `TLMO` | varchar | Y |
| 16 | `OSTAT` | varchar | Y |
| 17 | `SSTDT` | decimal | Y |
| 18 | `LATDT` | decimal | Y |
| 19 | `ASTDT` | decimal | Y |
| 20 | `OCODT` | decimal | Y |
| 21 | `CSTPC` | decimal | Y |
| 22 | `SETCO` | decimal | Y |
| 23 | `LABCO` | decimal | Y |
| 24 | `OVHCO` | decimal | Y |
| 25 | `ISSCO` | decimal | Y |
| 26 | `MISCO` | decimal | Y |
| 27 | `RECCO` | decimal | Y |
| 28 | `SCPCO` | decimal | Y |
| 29 | `MPROR` | varchar | Y |
| 30 | `MAFLG` | varchar | Y |
| 31 | `MDATE` | decimal | Y |
| 32 | `PLINE` | varchar | Y |
| 33 | `RUNSQ` | decimal | Y |
| 34 | `SCHGP` | varchar | Y |
| 35 | `ALTID` | varchar | Y |
| 36 | `PCSHR` | decimal | Y |
| 37 | `PCYFL` | varchar | Y |
| 38 | `CHGOV` | decimal | Y |
| 39 | `FLWTM` | decimal | Y |
| 40 | `PCMDT` | decimal | Y |
| 41 | `ORAC` | varchar | Y |
| 42 | `ITAC` | varchar | Y |
| 43 | `SLHV` | decimal | Y |
| 44 | `SLCV` | decimal | Y |
| 45 | `RLHV` | decimal | Y |
| 46 | `RLCV` | decimal | Y |
| 47 | `MCHV` | decimal | Y |
| 48 | `MCCV` | decimal | Y |
| 49 | `OHHV` | decimal | Y |
| 50 | `OHCV` | decimal | Y |
| 51 | `ITCL` | varchar | Y |
| 52 | `ROSD` | decimal | Y |
| 53 | `BFFL` | decimal | Y |
| 54 | `STID` | varchar | Y |
| 55 | `RTID` | varchar | Y |
| 56 | `FDESC` | varchar | Y |
| 57 | `PLANN` | decimal | Y |
| 58 | `DPTNO` | varchar | Y |
| 59 | `QTSCP` | decimal | Y |
| 60 | `QTSPL` | decimal | Y |
| 61 | `RATIO` | decimal | Y |
| 62 | `MSDQT` | decimal | Y |
| 63 | `MSNDD` | decimal | Y |
| 64 | `MSNSD` | decimal | Y |
| 65 | `MSOCC` | varchar | Y |
| 66 | `SNMBR` | varchar | Y |
| 67 | `ORRC` | decimal | Y |
| 68 | `ORTP` | varchar | Y |
| 69 | `GAPS` | varchar | Y |
| 70 | `IAPS` | varchar | Y |
| 71 | `CRDT` | decimal | Y |

### `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRDTL`
- Purpose: Transfer detail (holding transfer)
- KPI usage: On-Hold Ratio
- Row count: 675,462
- Columns (19):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `DTFRNO` | varchar | Y |
| 2 | `DITNBR` | varchar | Y |
| 3 | `DITCLS` | varchar | Y |
| 4 | `DGRFRC` | decimal | Y |
| 5 | `DATPQT` | decimal | Y |
| 6 | `DNTFRC` | decimal | Y |
| 7 | `DORFSH` | decimal | Y |
| 8 | `DFRSHR` | decimal | Y |
| 9 | `DTFRQT` | decimal | Y |
| 10 | `DSHPQT` | decimal | Y |
| 11 | `DTSHPQ` | decimal | Y |
| 12 | `DCUBES` | decimal | Y |
| 13 | `DWEGHT` | decimal | Y |
| 14 | `DTRIP#` | decimal | Y |
| 15 | `DEQUIP` | varchar | Y |
| 16 | `DEXPED` | varchar | Y |
| 17 | `DCOMNT` | varchar | Y |
| 18 | `DETADT` | decimal | Y |
| 19 | `DFIRMC` | varchar | Y |

### `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRHDR`
- Purpose: Transfer header (HFHOUS/HTHOUS/HCANCL)
- KPI usage: On-Hold Ratio header
- Row count: 26,135
- Columns (20):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `HACREC` | varchar | Y |
| 2 | `HTFRNO` | varchar | Y |
| 3 | `HFHOUS` | varchar | Y |
| 4 | `HTHOUS` | varchar | Y |
| 5 | `HSHDTE` | decimal | Y |
| 6 | `HLDDTE` | decimal | Y |
| 7 | `HDLDTE` | decimal | Y |
| 8 | `HCANCL` | varchar | Y |
| 9 | `HSTATS` | varchar | Y |
| 10 | `HBPRNT` | varchar | Y |
| 11 | `HBPDTE` | decimal | Y |
| 12 | `HPOST` | varchar | Y |
| 13 | `HORIG` | varchar | Y |
| 14 | `HTRCMT` | varchar | Y |
| 15 | `HARRDT` | decimal | Y |
| 16 | `HTFRTP` | varchar | N |
| 17 | `HDDCFL` | varchar | N |
| 18 | `HORDNO` | varchar | N |
| 19 | `HORDTP` | varchar | Y |
| 20 | `HDDAFL` | varchar | Y |

### `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.IMHIST`
- Purpose: Movement history (TCODE, TRNDT)
- KPI usage: NoMovement Flag, Obsolete
- Row count: 11,664,291
- Columns (105):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `ACREC` | varchar | Y |
| 2 | `BATCH` | decimal | Y |
| 3 | `TRMID` | varchar | Y |
| 4 | `TCODE` | varchar | Y |
| 5 | `ORDNO` | varchar | Y |
| 6 | `ITNBR` | varchar | Y |
| 7 | `HOUSE` | varchar | Y |
| 8 | `UPDDT` | decimal | Y |
| 9 | `UPDTM` | decimal | Y |
| 10 | `TRQTY` | decimal | Y |
| 11 | `TRAMT` | decimal | Y |
| 12 | `TRNDT` | decimal | Y |
| 13 | `PRQOH` | decimal | Y |
| 14 | `PRQOO` | decimal | Y |
| 15 | `PRALC` | decimal | Y |
| 16 | `STPCS` | decimal | Y |
| 17 | `CMPCD` | varchar | Y |
| 18 | `REVCD` | varchar | Y |
| 19 | `PCOST` | decimal | Y |
| 20 | `ENTUM` | varchar | Y |
| 21 | `VNDNR` | varchar | Y |
| 22 | `REFNO` | varchar | Y |
| 23 | `CUSAW` | varchar | Y |
| 24 | `NUQOH` | decimal | Y |
| 25 | `NUQOO` | decimal | Y |
| 26 | `NUALC` | decimal | Y |
| 27 | `BCHTY` | varchar | Y |
| 28 | `DTLOH` | decimal | Y |
| 29 | `INVFG` | decimal | Y |
| 30 | `SAFLG` | decimal | Y |
| 31 | `BLKSQ` | decimal | Y |
| 32 | `REASN` | varchar | Y |
| 33 | `TRWHS` | varchar | Y |
| 34 | `USRSQ` | varchar | Y |
| 35 | `LPHDT` | decimal | Y |
| 36 | `AVCST` | decimal | Y |
| 37 | `LBHNO` | varchar | Y |
| 38 | `LGWNO` | varchar | Y |
| 39 | `LLOCN` | varchar | Y |
| 40 | `NLLOC` | varchar | Y |
| 41 | `QCFLG` | varchar | Y |
| 42 | `NLBHN` | varchar | Y |
| 43 | `FDATE` | decimal | Y |
| 44 | `PLINE` | varchar | Y |
| 45 | `ODUDT` | decimal | Y |
| 46 | `SNMBR` | varchar | Y |
| 47 | `OSTAT` | varchar | Y |
| 48 | `LINCD` | varchar | Y |
| 49 | `TIMCD` | varchar | Y |
| 50 | `CREWN` | varchar | Y |
| 51 | `OPSEQ` | varchar | Y |
| 52 | `RSUPF` | decimal | Y |
| 53 | `SHIFT` | varchar | Y |
| 54 | `PRLA` | decimal | Y |
| 55 | `PRLQ` | decimal | Y |
| 56 | `BADGE` | decimal | Y |
| 57 | `PLANN` | decimal | Y |
| 58 | `LQNTY` | decimal | Y |
| 59 | `LALQY` | decimal | Y |
| 60 | `CONO` | decimal | Y |
| 61 | `ORTP` | varchar | Y |
| 62 | `ITMSQ` | decimal | Y |
| 63 | `RLNB` | decimal | Y |
| 64 | `KTRL` | decimal | Y |
| 65 | `WTSK` | decimal | Y |
| 66 | `COSC` | varchar | Y |
| 67 | `MROI` | varchar | Y |
| 68 | `WONB` | varchar | Y |
| 69 | `MMCM` | varchar | Y |
| 70 | `COFO` | varchar | Y |
| 71 | `EGNO` | varchar | Y |
| 72 | `VCLN` | varchar | Y |
| 73 | `TAGN` | varchar | Y |
| 74 | `UUSAAV` | varchar | Y |
| 75 | `UUCAAV` | varchar | Y |
| 76 | `UUQ1AV` | decimal | Y |
| 77 | `UUA1AV` | decimal | Y |
| 78 | `UUD1AV` | decimal | Y |
| 79 | `UU40AV` | varchar | Y |
| 80 | `UVRNAV` | varchar | Y |
| 81 | `UVATAV` | varchar | Y |
| 82 | `DVID` | varchar | Y |
| 83 | `TAID` | decimal | Y |
| 84 | `CGLN` | decimal | Y |
| 85 | `TRIN` | varchar | Y |
| 86 | `INVM` | varchar | Y |
| 87 | `GRNI` | varchar | Y |
| 88 | `UUIAAV` | varchar | Y |
| 89 | `PSTMAV` | datetime2 | Y |
| 90 | `LSEQAV` | decimal | Y |
| 91 | `ORTRAV` | varchar | Y |
| 92 | `CDSCAV` | varchar | Y |
| 93 | `REQTAV` | decimal | Y |
| 94 | `OPRUAV` | varchar | Y |
| 95 | `QTEQAV` | decimal | Y |
| 96 | `QPREAV` | decimal | Y |
| 97 | `PPSLAV` | decimal | Y |
| 98 | `POVLAV` | decimal | Y |
| 99 | `PISQAV` | decimal | Y |
| 100 | `PUDTAV` | decimal | Y |
| 101 | `UPDDTSQL` | decimal | Y |
| 102 | `UPDDTTM` | datetime2 | Y |
| 103 | `TRNDTSQL` | decimal | Y |
| 104 | `MonthYr` | int | Y |
| 105 | `Division_ID` | int | Y |

### `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail`
- Purpose: Customer open orders (ItemAllocationFlag)
- KPI usage: Allocated Demand
- Row count: 918,213
- Columns (66):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `OrderNumber` | varchar | Y |
| 2 | `ItemSKU` | varchar | Y |
| 3 | `Warehouse` | varchar | Y |
| 4 | `ItemSequence` | decimal | Y |
| 5 | `QuantiyOrdered` | decimal | Y |
| 6 | `QuantityShipped` | decimal | Y |
| 7 | `QuantityBackOrdered` | decimal | Y |
| 8 | `NetSalesAmount` | decimal | Y |
| 9 | `ItemAllocationFlag` | decimal | Y |
| 10 | `PromiseDate` | date | Y |
| 11 | `LoadDate` | date | Y |
| 12 | `ItemDescription` | varchar | Y |
| 13 | `SellingPrice` | decimal | Y |
| 14 | `BasePrice` | decimal | Y |
| 15 | `ItemClass` | varchar | Y |
| 16 | `CustomerNumber` | varchar | Y |
| 17 | `ShiptoNumber` | varchar | Y |
| 18 | `LastLoadDateChange` | datetime2 | Y |
| 19 | `PreviousLoadDate` | datetime2 | Y |
| 20 | `LastPreviousLoadDateChange` | datetime2 | Y |
| 21 | `EarliestLoadDate` | datetime2 | Y |
| 22 | `LatestLoadDate` | datetime2 | Y |
| 23 | `LoadDateChangeCount` | decimal | Y |
| 24 | `ItemWithLatestLoadDate` | varchar | Y |
| 25 | `ItemProcessingStatus` | varchar | Y |
| 26 | `OrderArrivalCode` | varchar | Y |
| 27 | `MarkFor` | varchar | Y |
| 28 | `ItemLanguageDescription` | varchar | Y |
| 29 | `UnitCost` | decimal | Y |
| 30 | `RecordCode` | varchar | Y |
| 31 | `WarehouseLocation` | varchar | Y |
| 32 | `NonInventoryItem` | decimal | Y |
| 33 | `UnitOfMeasure` | varchar | Y |
| 34 | `ExtendedWeightOverride` | decimal | Y |
| 35 | `ExtendedWeight` | decimal | Y |
| 36 | `ContractUnitPrice` | decimal | Y |
| 37 | `PriceOverride` | decimal | Y |
| 38 | `DiscountMarkup` | decimal | Y |
| 39 | `DiscountPercent` | decimal | Y |
| 40 | `QuantityDiscountPercent` | decimal | Y |
| 41 | `SellingPriceOverride` | decimal | Y |
| 42 | `NetSalesAmountOverride` | decimal | Y |
| 43 | `itemTypeCode` | varchar | Y |
| 44 | `UnitWeight` | decimal | Y |
| 45 | `CreditCode` | varchar | Y |
| 46 | `ManufacturiingOrderFlag` | varchar | Y |
| 47 | `SalesAnalysisFlag` | decimal | Y |
| 48 | `MaterialRequestDate` | date | Y |
| 49 | `MaintainedByProgram` | varchar | Y |
| 50 | `PriceConversionMultiplier` | decimal | Y |
| 51 | `PriceCode` | decimal | Y |
| 52 | `PricingUnitOfMeasure` | varchar | Y |
| 53 | `PricingOverride` | decimal | Y |
| 54 | `ConvsionSellingPrice` | decimal | Y |
| 55 | `CustomerRelEnt` | varchar | Y |
| 56 | `RequestDateOverride` | decimal | Y |
| 57 | `MfgDueDateOverride` | decimal | Y |
| 58 | `MfgOrderNumber` | varchar | Y |
| 59 | `ExportAdderCode` | varchar | Y |
| 60 | `LC_ContractPrice` | decimal | Y |
| 61 | `LC_BasePrice` | decimal | Y |
| 62 | `LC_SellingPrice` | decimal | Y |
| 63 | `LC_NetSalesAmount` | decimal | Y |
| 64 | `LC_COnversionSellingPrice` | decimal | Y |
| 65 | `PriceAdjustmentFactor` | decimal | Y |
| 66 | `TaxIndicator` | varchar | Y |

### `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderHeader`
- Purpose: Customer order header
- KPI usage: Allocated Demand header
- Row count: 219,900
- Columns (15):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `ActiveRecord` | varchar | Y |
| 2 | `OrderNumber` | varchar | Y |
| 3 | `CustomerNumber` | varchar | Y |
| 4 | `PurchaseOrder` | varchar | Y |
| 5 | `OrderDate` | date | Y |
| 6 | `PriorityOverride` | varchar | Y |
| 7 | `CreditMemoCode` | varchar | Y |
| 8 | `Warehouse` | varchar | Y |
| 9 | `Slsno` | decimal | Y |
| 10 | `OrderValue` | decimal | Y |
| 11 | `ShiptoNumber` | varchar | Y |
| 12 | `RequestDate` | date | Y |
| 13 | `ShippingLeadTime` | decimal | Y |
| 14 | `ShippingInstructions` | varchar | Y |
| 15 | `PurchaseOrderDate` | date | Y |

### `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail`
- Purpose: PO detail Enterprise (was 0 rows; reload pending)
- KPI usage: PO On Order/In Transit
- Row count: 0
- Columns (53):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `podordernum` | varchar | Y |
| 2 | `podvendornum` | varchar | Y |
| 3 | `poditemnum` | varchar | Y |
| 4 | `podwarehouse` | varchar | Y |
| 5 | `poditemsequence` | int | Y |
| 6 | `podqtyordered` | decimal | Y |
| 7 | `podstockprice` | decimal | Y |
| 8 | `podorderuom` | varchar | Y |
| 9 | `poditemdescription` | varchar | Y |
| 10 | `podwhselocation` | varchar | Y |
| 11 | `podlastmaintained` | varchar | Y |
| 12 | `podextendedprice` | decimal | Y |
| 13 | `poditemclass` | varchar | Y |
| 14 | `podstatuscode` | varchar | Y |
| 15 | `podunitofmeasure` | varchar | Y |
| 16 | `podpurchaseuom` | varchar | Y |
| 17 | `poduomconversion` | decimal | Y |
| 18 | `podduedate` | datetime2 | Y |
| 19 | `podcurrentprice` | decimal | Y |
| 20 | `podstockqty` | decimal | Y |
| 21 | `podoverhead` | decimal | Y |
| 22 | `podcubes` | decimal | Y |
| 23 | `podweight` | decimal | Y |
| 24 | `podnopriceupdate` | bit | Y |
| 25 | `podIntransitQty` | decimal | Y |
| 26 | `usra` | varchar | Y |
| 27 | `dtea` | datetime2 | Y |
| 28 | `usrc` | varchar | Y |
| 29 | `dtec` | datetime2 | Y |
| 30 | `podAccountNum` | varchar | Y |
| 31 | `podEngDrawingNum` | varchar | Y |
| 32 | `podDockQty` | decimal | Y |
| 33 | `podInspectionQty` | decimal | Y |
| 34 | `podScrapQty` | decimal | Y |
| 35 | `podDeviationQty` | decimal | Y |
| 36 | `podUnit` | varchar | Y |
| 37 | `podInvNature` | varchar | Y |
| 38 | `podFreightNature` | varchar | Y |
| 39 | `podProject` | varchar | Y |
| 40 | `podBuyerAcceptDate` | varchar | Y |
| 41 | `podVendorAcceptDate` | varchar | Y |
| 42 | `podMfrName` | varchar | Y |
| 43 | `podMfrAddress` | varchar | Y |
| 44 | `podMfrPartyID` | int | Y |
| 45 | `podMfrLocationID` | int | Y |
| 46 | `podMID` | varchar | Y |
| 47 | `podMfrAddress2` | varchar | Y |
| 48 | `podMfrProvince` | varchar | Y |
| 49 | `podMfrCity` | varchar | Y |
| 50 | `podMfrCountry` | varchar | Y |
| 51 | `podMfrZip` | varchar | Y |
| 52 | `podReturnedQty` | decimal | Y |
| 53 | `podReplacementPart` | bit | Y |

### `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.Container`
- Purpose: Container tracking
- KPI usage: Container Count
- Row count: 299,485
- Columns (39):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `concontainer` | varchar | N |
| 2 | `conID` | int | N |
| 3 | `concreated` | datetime2 | Y |
| 4 | `conviacode` | varchar | N |
| 5 | `concarrierid` | int | N |
| 6 | `conmothervessel` | varchar | N |
| 7 | `conmothervoyage` | int | N |
| 8 | `conreceipttostock` | datetime2 | Y |
| 9 | `conreceiver` | datetime2 | Y |
| 10 | `conoblsent` | datetime2 | Y |
| 11 | `confeedervessel` | varchar | N |
| 12 | `confeedervoyage` | int | N |
| 13 | `conbookingnum` | varchar | N |
| 14 | `conEquipmentReturned` | datetime2 | Y |
| 15 | `conEquipmentStatusCode` | varchar | N |
| 16 | `conPallets` | decimal | N |
| 17 | `conTruckLoad` | bit | N |
| 18 | `conPickUpDate` | datetime2 | Y |
| 19 | `conETA` | datetime2 | Y |
| 20 | `conOnBoard` | datetime2 | Y |
| 21 | `conEquipmentID` | varchar | N |
| 22 | `conSealNumber` | varchar | N |
| 23 | `conASNModificationStatus` | int | N |
| 24 | `conContainerOwnerID` | smallint | N |
| 25 | `usra` | varchar | Y |
| 26 | `dtea` | datetime2 | Y |
| 27 | `usrc` | varchar | Y |
| 28 | `dtec` | datetime2 | Y |
| 29 | `conReportedEmpty` | datetime2 | Y |
| 30 | `conCargoReceived` | datetime2 | Y |
| 31 | `conCheckDigit` | int | Y |
| 32 | `conSCAC` | varchar | N |
| 33 | `conProNumber` | varchar | Y |
| 34 | `conDeliveredDate` | datetime2 | Y |
| 35 | `conCNRUnumber` | varchar | Y |
| 36 | `conRailSCAC` | varchar | Y |
| 37 | `conExpectedDelivery` | datetime2 | Y |
| 38 | `conOutgateForDelivery` | datetime2 | Y |
| 39 | `conLastFreeDay` | datetime2 | Y |

### `SupplyChain_Lakehouse.dbo.podetail_v2`
- Purpose: PO detail replacement (21.9M)
- KPI usage: PO On Order/In Transit
- Row count: 21,923,551
- Columns (53):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `podordernum` | varchar | Y |
| 2 | `podvendornum` | varchar | Y |
| 3 | `poditemnum` | varchar | Y |
| 4 | `podwarehouse` | varchar | Y |
| 5 | `poditemsequence` | int | Y |
| 6 | `podqtyordered` | decimal | Y |
| 7 | `podstockprice` | decimal | Y |
| 8 | `podorderuom` | varchar | Y |
| 9 | `poditemdescription` | varchar | Y |
| 10 | `podwhselocation` | varchar | Y |
| 11 | `podlastmaintained` | varchar | Y |
| 12 | `podextendedprice` | decimal | Y |
| 13 | `poditemclass` | varchar | Y |
| 14 | `podstatuscode` | varchar | Y |
| 15 | `podunitofmeasure` | varchar | Y |
| 16 | `podpurchaseuom` | varchar | Y |
| 17 | `poduomconversion` | decimal | Y |
| 18 | `podduedate` | datetime2 | Y |
| 19 | `podcurrentprice` | decimal | Y |
| 20 | `podstockqty` | decimal | Y |
| 21 | `podoverhead` | decimal | Y |
| 22 | `podcubes` | decimal | Y |
| 23 | `podweight` | decimal | Y |
| 24 | `podnopriceupdate` | bit | Y |
| 25 | `podIntransitQty` | decimal | Y |
| 26 | `usra` | varchar | Y |
| 27 | `dtea` | datetime2 | Y |
| 28 | `usrc` | varchar | Y |
| 29 | `dtec` | datetime2 | Y |
| 30 | `podAccountNum` | varchar | Y |
| 31 | `podEngDrawingNum` | varchar | Y |
| 32 | `podDockQty` | decimal | Y |
| 33 | `podInspectionQty` | decimal | Y |
| 34 | `podScrapQty` | decimal | Y |
| 35 | `podDeviationQty` | decimal | Y |
| 36 | `podUnit` | varchar | Y |
| 37 | `podInvNature` | varchar | Y |
| 38 | `podFreightNature` | varchar | Y |
| 39 | `podProject` | varchar | Y |
| 40 | `podBuyerAcceptDate` | varchar | Y |
| 41 | `podVendorAcceptDate` | varchar | Y |
| 42 | `podMfrName` | varchar | Y |
| 43 | `podMfrAddress` | varchar | Y |
| 44 | `podMfrPartyID` | int | Y |
| 45 | `podMfrLocationID` | int | Y |
| 46 | `podMID` | varchar | Y |
| 47 | `podMfrAddress2` | varchar | Y |
| 48 | `podMfrProvince` | varchar | Y |
| 49 | `podMfrCity` | varchar | Y |
| 50 | `podMfrCountry` | varchar | Y |
| 51 | `podMfrZip` | varchar | Y |
| 52 | `podReturnedQty` | decimal | Y |
| 53 | `podReplacementPart` | bit | Y |

### `SupplyChain_Lakehouse.dbo.pomaster`
- Purpose: PO header replacement (5.67M)
- KPI usage: PO ETA, vendor enrichment
- Row count: 5,681,305
- Columns (75):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `pomordernum` | varchar | Y |
| 2 | `pomvendornum` | varchar | Y |
| 3 | `pomcreated` | datetime2 | Y |
| 4 | `pommaintained` | datetime2 | Y |
| 5 | `pomorderamt` | decimal | Y |
| 6 | `pomstatuscode` | varchar | Y |
| 7 | `pomfobcode` | varchar | Y |
| 8 | `pomtermcode` | varchar | Y |
| 9 | `pomshipid` | int | Y |
| 10 | `pomwarehouse` | varchar | Y |
| 11 | `pometa` | datetime2 | Y |
| 12 | `pometd` | datetime2 | Y |
| 13 | `pomdue` | datetime2 | Y |
| 14 | `pomoriginaletd` | datetime2 | Y |
| 15 | `pometdportid` | varchar | Y |
| 16 | `pometaportid` | int | Y |
| 17 | `pommoneywire` | decimal | Y |
| 18 | `pomtotalbankfee` | decimal | Y |
| 19 | `pomdatepaid` | datetime2 | Y |
| 20 | `pomtotalfreight` | decimal | Y |
| 21 | `pomoceaninsurance` | decimal | Y |
| 22 | `pomtotalmiscchg` | decimal | Y |
| 23 | `pomtotalcubes` | decimal | Y |
| 24 | `pomtotalweight` | decimal | Y |
| 25 | `pomchairschedule` | bit | Y |
| 26 | `pomcredit` | decimal | Y |
| 27 | `pomonboard` | datetime2 | Y |
| 28 | `pomcomplete` | bit | Y |
| 29 | `pomdestinationid` | int | Y |
| 30 | `pomcontainer` | varchar | Y |
| 31 | `pomcontainerseq` | int | Y |
| 32 | `pomposeries` | varchar | Y |
| 33 | `pomProcStatus` | varchar | Y |
| 34 | `pomPieces` | decimal | Y |
| 35 | `pomOBL` | varchar | Y |
| 36 | `pomOBLSent` | datetime2 | Y |
| 37 | `pomShipMethod` | float | Y |
| 38 | `pomOrigCntrSize` | varchar | Y |
| 39 | `pomRevisionNum` | float | Y |
| 40 | `pomBuyerAcceptDate` | datetime2 | Y |
| 41 | `pomVendorAcceptDate` | datetime2 | Y |
| 42 | `pomBuyerProcessing` | bit | Y |
| 43 | `pomVendorProcessing` | bit | Y |
| 44 | `pomAutoPO` | bit | Y |
| 45 | `pomRevisionDate` | datetime2 | Y |
| 46 | `pomSeawayBill` | bit | Y |
| 47 | `pomAdminID` | varchar | Y |
| 48 | `pomPOType` | varchar | Y |
| 49 | `pomBuyerNum` | varchar | Y |
| 50 | `pomHomePageDate` | datetime2 | Y |
| 51 | `pomNewProduct` | bit | Y |
| 52 | `usra` | varchar | Y |
| 53 | `dtea` | datetime2 | Y |
| 54 | `usrc` | varchar | Y |
| 55 | `dtec` | datetime2 | Y |
| 56 | `pomSealNumber` | varchar | Y |
| 57 | `pomPOClass` | varchar | Y |
| 58 | `pomSummaryPO` | varchar | Y |
| 59 | `pomPaymentApproved` | datetime2 | Y |
| 60 | `pomHouseBOL` | varchar | Y |
| 61 | `pomHouseSCAC` | varchar | Y |
| 62 | `pomTripType` | varchar | Y |
| 63 | `pomTripCreated` | decimal | Y |
| 64 | `pomTripNumber` | decimal | Y |
| 65 | `pomCurrencyCode` | varchar | Y |
| 66 | `pomIncoTermsCode` | varchar | Y |
| 67 | `pomVATamount` | decimal | Y |
| 68 | `pomVendorAckDate` | datetime2 | Y |
| 69 | `pomBuyerEntityPaidDate` | datetime2 | Y |
| 70 | `pomBuyerEntity` | varchar | Y |
| 71 | `pomSubmitToTreasury` | datetime2 | Y |
| 72 | `pomBookingNum` | varchar | Y |
| 73 | `pomBookingStatusId` | int | Y |
| 74 | `pomCustReqETD` | datetime2 | Y |
| 75 | `pomHotProductId` | int | Y |

### `SupplyChain_Lakehouse.dbo.logility_demandfulfillment`
- Purpose: Logility historical (38.36M, 9128 dup)
- KPI usage: Inactive/SLOB historical
- Row count: 38,356,303
- Columns (53):

| # | Column | Type | Nullable |
|---|---|---|---|
| 1 | `Item` | varchar | Y |
| 2 | `Whse` | varchar | Y |
| 3 | `WeekEnding` | datetime2 | Y |
| 4 | `FirmDemand` | decimal | Y |
| 5 | `Netfcst` | decimal | Y |
| 6 | `Firmtfrs` | decimal | Y |
| 7 | `PlannedTfrs` | decimal | Y |
| 8 | `FirmProd` | decimal | Y |
| 9 | `PlannedProd` | decimal | Y |
| 10 | `FirmPos` | decimal | Y |
| 11 | `PlannedPos` | decimal | Y |
| 12 | `InTransitTfrs` | decimal | Y |
| 13 | `OnOrderTfrs` | decimal | Y |
| 14 | `Planned Tfrs` | decimal | Y |
| 15 | `Total Receipts` | decimal | Y |
| 16 | `ShippableInvQty` | decimal | Y |
| 17 | `ShippableInvAmt` | decimal | Y |
| 18 | `MosofSupply` | decimal | Y |
| 19 | `SafetyStockQty` | decimal | Y |
| 20 | `SafetyStockAmt` | decimal | Y |
| 21 | `OnHandQty` | decimal | Y |
| 22 | `OnHandAmt` | decimal | Y |
| 23 | `SI-SSAmt` | decimal | Y |
| 24 | `ItemClass` | varchar | Y |
| 25 | `CollClass` | varchar | Y |
| 26 | `Series` | varchar | Y |
| 27 | `Division` | varchar | Y |
| 28 | `ItemStatus` | varchar | Y |
| 29 | `FutureStatus` | varchar | Y |
| 30 | `StatusChngDate` | datetime2 | Y |
| 31 | `Price` | decimal | Y |
| 32 | `HoldBuy` | varchar | Y |
| 33 | `UnSW` | varchar | Y |
| 34 | `HRInd` | varchar | Y |
| 35 | `ABC` | varchar | Y |
| 36 | `KeyItem` | varchar | Y |
| 37 | `DerivedFcstFactor` | varchar | Y |
| 38 | `SourceKey` | varchar | Y |
| 39 | `MakeBuyCode` | varchar | Y |
| 40 | `Vendor` | varchar | Y |
| 41 | `FcstPlanner` | varchar | Y |
| 42 | `DRPPlanner` | varchar | Y |
| 43 | `OrderMulitple` | varchar | Y |
| 44 | `ProductionMin` | varchar | Y |
| 45 | `KitComptUsage` | varchar | Y |
| 46 | `CurrencyCode` | varchar | Y |
| 47 | `FolderPath` | varchar | Y |
| 48 | `Filename` | varchar | Y |
| 49 | `FileDate` | datetime2 | Y |
| 50 | `FolderName` | varchar | Y |
| 51 | `Country` | varchar | Y |
| 52 | `Company` | varchar | Y |
| 53 | `ExpressShipFlag` | varchar | Y |
