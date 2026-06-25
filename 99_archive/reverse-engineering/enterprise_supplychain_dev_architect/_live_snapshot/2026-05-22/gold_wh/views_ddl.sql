-- Live VIEW dump from SupplyChain_Gold_Warehouse
-- Generated 2026-05-22 via OBJECT_DEFINITION
-- 13 views

-- ============================================================
-- ForecastAccuracy_DW.v_DimCalendar
-- ============================================================
-- 06_create_renamed_views_gold.sql
-- 7 Gold views recreated with v_ prefix. 3-part-name refs to Processing schemas updated.
-- Source: etl/gold_views.sql, transformed.

-- ============================================================
-- Gold Views — ForecastAccuracy_DW Serving Layer
-- ============================================================
-- Layer: Gold. Pattern: cross-DB 3-part name from Processing WH + CAST FLOAT + LoadDT.
-- Source: SupplyChain_Gold_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- ForecastAccuracy_DW.v_DimCalendar ----
CREATE   VIEW ForecastAccuracy_DW.v_DimCalendar AS
SELECT
    -- Keys (existing + new)
    CAL.SKDate                          AS DateSK,
    CAL.MapicsDate                      AS MapicsDate,
    CAL.Date                            AS [Date],
    CAL.Datetime                        AS Datetime,
    CAL.Calendar                        AS Calendar,

    -- Calendar Day
    CAL.CalendarDateName                AS CalendarDateName,
    CAL.CalDateIndicatorNum             AS CalDateIndicatorNum,
    CAL.CalDayOfWeekNum                 AS CalDayOfWeekNum,
    CAL.CalDayOfWeekName                AS CalDayOfWeekName,
    CAL.CalDayOfMonthNum                AS CalDayOfMonthNum,
    CAL.CalDayOfYearNum                 AS CalDayOfYearNum,

    -- Calendar Week
    CAL.CalWeekNum                      AS CalWeekNum,
    CAL.CalWeekIndicatorNum             AS CalWeekIndicatorNum,
    CAL.CalWeekYearNum                  AS CalWeekYearNum,
    CAL.CalWeekYearName                 AS CalWeekYearName,
    CAL.CalWeekFirst                    AS CalWeekFirst,
    CAL.CalWeekLast                     AS CalWeekLast,
    CAL.CalWeekOfMonthNum               AS CalWeekOfMonthNum,

    -- Calendar Month
    CAL.CalMonthNum                     AS CalMonthNum,
    CAL.CalMonthIndicatorNum            AS CalMonthIndicatorNum,
    CAL.CalMonthYearNum                 AS CalMonthYearNum,
    CAL.CalMonthName                    AS CalMonthName,
    CAL.CalMonthYearName                AS CalMonthYearName,
    CAL.CalMonthFirst                   AS CalMonthFirst,
    CAL.CalMonthLast                    AS CalMonthLast,

    -- Calendar Quarter
    CAL.CalQuarterNum                   AS CalQuarterNum,
    CAL.CalQuarterName                  AS CalQuarterName,
    CAL.CalQuarterIndicatorNum          AS CalQuarterIndicatorNum,
    CAL.CalQuarterYearNum               AS CalQuarterYearNum,
    CAL.CalQuarterYearName              AS CalQuarterYearName,

    -- Calendar Semester + Year
    CAL.CalSemesterNum                  AS CalSemesterNum,
    CAL.CalSemesterYearNum              AS CalSemesterYearNum,
    CAL.CalYearNum                      AS CalYearNum,
    CAL.CalYearName                     AS CalYearName,
    CAL.CalYearIndicatorNum             AS CalYearIndicatorNum,

    -- Fiscal Day
    CAL.FiscalDate                      AS FiscalDate,
    CAL.FiscalDateName                  AS FiscalDateName,
    CAL.FSCDateIndicatorNum             AS FSCDateIndicatorNum,
    CAL.FSCDayOfWeekNum                 AS FSCDayOfWeekNum,
    CAL.FSCDayOfWeekName                AS FSCDayOfWeekName,
    CAL.FSCDayOfMonthNum                AS FSCDayOfMonthNum,
    CAL.FSCDayOfYearNum                 AS FSCDayOfYearNum,

    -- Fiscal Week
    CAL.FSCWeekNum                      AS FSCWeekNum,
    CAL.FSCWeekIndicatorNum             AS FSCWeekIndicatorNum,
    CAL.FSCWeekYearNum                  AS FSCWeekYearNum,
    CAL.FSCWeekYearName                 AS FSCWeekYearName,
    CAL.FSCWeekFirst                    AS FSCWeekFirst,
    CAL.FSCWeekLast                     AS FSCWeekLast,
    CAL.FSCWeekOfMonthNum               AS FSCWeekOfMonthNum,

    -- Fiscal Month (existing + new)
    CAL.FSCMonthNum                     AS FSCMonthNum,
    CAL.FSCMonthIndicatorNum            AS FSCMonthIndicatorNum,
    CAL.FSCMonthYearNum                 AS FSCMonthYearNum,
    CAL.FSCMonthName                    AS FSCMonthName,
    CAL.FSCMonthYearName                AS FSCMonthYearName,
    CAL.FSCMonthFirst                   AS FSCMonthFirst,
    CAL.FSCMonthLast                    AS FSCMonthLast,

    -- Fiscal Quarter
    CAL.FSCQuarterNum                   AS FSCQuarterNum,
    CAL.FSCQuarterName                  AS FSCQuarterName,
    CAL.FSCQuarterIndicatorNum          AS FSCQuarterIndicatorNum,
    CAL.FSCQuarterYearNum               AS FSCQuarterYearNum,
    CAL.FSCQuarterYearName              AS FSCQuarterYearName,
    CAL.FSCQuarterFirst                 AS FSCQuarterFirst,
    CAL.FSCQuarterLast                  AS FSCQuarterLast,

    -- Fiscal Semester + Year
    CAL.FSCSemesterNum                  AS FSCSemesterNum,
    CAL.FSCSemesterYearNum              AS FSCSemesterYearNum,
    CAL.FSCYearNum                      AS FSCYearNum,
    CAL.FSCYearName                     AS FSCYearName,
    CAL.FSCYearIndicatorNum             AS FSCYearIndicatorNum,
    CAL.FSCYearFirst                    AS FSCYearFirst,
    CAL.FSCYearLast                     AS FSCYearLast,

    -- Holiday + Working Day
    CAL.HolidayIndicatorCode            AS HolidayIndicatorCode,
    CAL.HolidayName                     AS HolidayName,
    CAL.WorkingDayCode                  AS WorkingDayCode,
    CAL.WeekdayWeekendCode              AS WeekdayWeekendCode,

    -- Audit
    CAST(GETUTCDATE() AS DATETIME2(6))  AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Calendar AS CAL
WHERE CAL.SKDate IS NOT NULL;
GO

-- ============================================================
-- ForecastAccuracy_DW.v_DimCustomerGrouping
-- ============================================================
-- ---- ForecastAccuracy_DW.v_DimCustomerGrouping ----
CREATE VIEW ForecastAccuracy_DW.v_DimCustomerGrouping AS
SELECT DISTINCT CustomerGroupCode, Customer,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.CustomerGrouping
WHERE CustomerGroupCode IS NOT NULL
GO

-- ============================================================
-- ForecastAccuracy_DW.v_DimForecastHorizon
-- ============================================================
-- ---- ForecastAccuracy_DW.v_DimForecastHorizon ----

CREATE   VIEW ForecastAccuracy_DW.v_DimForecastHorizon AS
SELECT HorizonCode, [Rank], CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon
GO

-- ============================================================
-- ForecastAccuracy_DW.v_DimProduct
-- ============================================================
CREATE   VIEW ForecastAccuracy_DW.v_DimProduct AS
-- ===========================================================================
-- v_DimProduct — Backward-compatible view for v9 semantic model TMDL
-- Generated 2026-05-20 — fix Delta protocol violation after EDW Exit swap
--
-- Source: SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ItemMaster (174 cols)
-- Target: 89 cols expected by sc_forecast_control_tower semantic model TMDL
--
-- Categories:
--   §A — 17 cols  matched EXACTLY (passthrough)
--   §B — 42 cols  RENAMED (v9 suffix removed in EL → alias back)
--   §C — 30 cols  TRULY MISSING in EL (NULL stub — visual will show blank)
--   §D — 118 cols  BONUS (extra EL cols not in TMDL — exposed for future use)
--
-- VERIFIED 2026-05-20: scan all TMDL files showed 0 DAX measures / 0 relationships
--   reference the missing cols → NULL stub safe.
-- ===========================================================================
SELECT
-- §A. Direct match (17 cols)
    RTRIM([ItemSKU]) AS [ItemSKU],
    [Item],
    [SeriesName],
    [ItemClassCode],
    [ItemClassName],
    [ItemCode],
    [ItemStyleCode],
    [RetailCategoryCode],
    [RetailCategoryName],
    [AssociationCode],
    [SalesClassCode],
    [AFISalesCategoryCode],
    [AFISalesDivisionCode],
    [DiscountClassCode],
    [CommissionClassCode],
    [FreightClassCode],
    [ImportDomesticCode],

-- §B. Renamed aliases (42 cols) — v9 name kept for TMDL compat
    [ItemDescription] AS [ItemDescriptionName],
    [QtyInBox] AS [QtyInBoxNum],
    [UOM] AS [UOMCode],
    [SeriesColor] AS [SeriesColorName],
    [SeriesDescription] AS [SeriesDescriptionName],
    [SHSeriesDescription] AS [ShSeriesDescriptionName],
    [ItemClassName] AS [ItemClassFullName],
    [ItemGrouping] AS [ItemGroupingName],
    [ItemStyleGroup] AS [ItemStyleGroupName],
    [ItemStyle] AS [ItemStyleName],
    [ProductLine] AS [ProductLineName],
    [MerchandisingCategory] AS [MerchandisingCategoryName],
    [PricePoint] AS [PricePointName],
    [SalesClassDescription] AS [SalesClassDescriptionName],
    [SalesClass] AS [SalesClassName],
    [AFISalesCategory] AS [AFISalesCategoryName],
    [AFISalesDivision] AS [AFISalesDivisionName],
    [AFIFinanceDivision] AS [AFIFinanceDivisionName],
    [DiscountClassDescription] AS [DiscountClassDescriptionName],
    [DiscountClass] AS [DiscountClassName],
    [CommissionClassDescription] AS [CommissionClassDescriptionName],
    [CommissionClass] AS [CommissionClassName],
    [FreightClassDescription] AS [FreightClassDescriptionName],
    [FreightClass] AS [FreightClassName],
    [CollectiveClass] AS [CollectiveClassCode],
    [CollectiveClass] AS [CollectiveClassName],
    [ResponsibleOffice] AS [ResponsibleOfficeCode],
    [CountryofOrigin] AS [CountryOfOriginName],
    [AFIItemStatus] AS [AFIItemStatusCode],
    [ManufacturingStatus] AS [ManufacturingStatusCode],
    [MarketingItemStatus] AS [MarketingItemStatusCode],
    [ManufacturingStatusChangeDate] AS [ManufacturingStatusChange],
    [CommodityItem] AS [CommodityItemNum],
    [BenchcraftProductFlag] AS [IsBenchcraftProduct],
    [NewMillenniumProductFlag] AS [IsNewMillenniumProduct],
    [ShanghaiStore] AS [IsShanghaiStore],
    [DefaultGroup] AS [DefaultGroupNum],
    [MarketIntroducedAt] AS [MarketIntroducedAtName],
    [PrimaryVendor] AS [PrimaryVendorCode],
    [PrimaryVendor] AS [PrimaryVendorName],
    [InitialInvoicePeriod] AS [InitialInvoicePeriodCode],
    [ItemForecastPlannerID] AS [ItemForecastPlanner],

-- §C. NULL stubs (30 cols) — v9-only cols not in EL schema
    CAST(NULL AS VARCHAR(50)) AS [SKProduct],
    CAST(NULL AS VARCHAR(50)) AS [SCPItem],
    CAST(NULL AS VARCHAR(100)) AS [ColorName],
    CAST(NULL AS VARCHAR(50)) AS [SeriesCode],
    CAST(NULL AS VARCHAR(50)) AS [ExtSeriesCode],
    CAST(NULL AS VARCHAR(50)) AS [ItemExtSeriesCode],
    CAST(NULL AS VARCHAR(200)) AS [ItemDescSeriesName],
    CAST(NULL AS VARCHAR(200)) AS [ShItemDescSeriesName],
    CAST(NULL AS VARCHAR(200)) AS [ItemDescSeriesColorName],
    CAST(NULL AS VARCHAR(100)) AS [ChildStyleName],
    CAST(NULL AS VARCHAR(100)) AS [ParentStyleName],
    CAST(NULL AS VARCHAR(50)) AS [CexCode],
    CAST(NULL AS VARCHAR(20)) AS [CurrentSCPManufacturingStatusCode],
    CAST(NULL AS VARCHAR(100)) AS [MarketingStatusName],
    CAST(NULL AS VARCHAR(20)) AS [CurrentStatusCode],
    CAST(NULL AS BIT) AS [IsMainPiece],
    CAST(NULL AS VARCHAR(20)) AS [SellableItemCode],
    CAST(NULL AS BIT) AS [IsF123Product],
    CAST(NULL AS BIT) AS [IsHsCoreProduct],
    CAST(NULL AS BIT) AS [IsHsProprietaryProduct],
    CAST(NULL AS BIT) AS [IsHsExclusive],
    CAST(NULL AS BIT) AS [IsBerklineProduct],
    CAST(NULL AS BIT) AS [IsBardiniProduct],
    CAST(NULL AS DATE) AS [MarketBegin],
    CAST(NULL AS DATE) AS [MarketEnd],
    CAST(NULL AS DECIMAL(18,4)) AS [AmtFobPrice],
    CAST(NULL AS VARCHAR(20)) AS [GoodBetterBestCode],
    CAST(NULL AS INT) AS [GbbSortNum],
    CAST(NULL AS DECIMAL(18,4)) AS [QtyInitialInvoice],
    CAST(NULL AS VARCHAR(50)) AS [MainPieceCode],

-- §D. Bonus EL cols (118 cols) — extra columns from EL not exposed in v9 TMDL
    [AFIFinanceDivisionCode],
    [BardiniProductFlag],
    [BerklineProductFlag],
    [CEXCode],
    [CartonDepthInches],
    [CartonDepthMeters],
    [CartonHeightInches],
    [CartonHeightMeters],
    [CartonWidthInches],
    [CartonWidthMeters],
    [ChildStyleDescription],
    [Colors],
    [CommonCarrierFlag],
    [ConsumerChoiceFlag],
    [Cubes],
    [CurrentUnitCost],
    [DiningSeriesFlag],
    [DiscontinuedDate],
    [DiscontinuedFlag],
    [DiscontinuedYearPeriod],
    [Division],
    [DivisionRanking],
    [ERetailChannelSku],
    [ERetailSeriesName],
    [ERetailSeriesNumber],
    [EligibleForProtectionPlan],
    [ExclusiveComment],
    [ExpressShipFlag],
    [ExtSeriesNumber],
    [F123ProductFlag],
    [FOBArcPrice],
    [FluffAFI],
    [FrameNumber],
    [FriendlyDimensions],
    [GBBSortId],
    [GoodBetterBestForPricePoint],
    [GroupPriceIncr],
    [GroupPricePointType],
    [HSCoreProductFlag],
    [HSExclusiveFlag],
    [HSProprietaryProductFlag],
    [InitialInvoiceQty],
    [IsProtectionPlan],
    [ItemAmazonBrandOwner],
    [ItemBedSizeType],
    [ItemBedStyleType],
    [ItemClass],
    [ItemConsumerDescription],
    [ItemDescriptionSeries],
    [ItemDescriptionSeriesItemColor],
    [ItemEcomMerchantNotes],
    [ItemGeneralColor],
    [ItemHomeStoreProductLine],
    [ItemImage],
    [ItemIsRTA],
    [ItemKey],
    [ItemMerchGridOverridePhoto],
    [ItemName],
    [ItemPricePointRating],
    [ItemSupplierDirectShipOnly],
    [ItemTableShapeType],
    [ItemThirdPartyItem],
    [ItemType],
    [KeyItem],
    [Knockout],
    [Lifestyle],
    [LoadDT],
    [MainPieceItem],
    [MarketBeginDate],
    [MarketEndDate],
    [MarketingStatusDescription],
    [MasterGroupCode],
    [Material],
    [MfgWarranty],
    [NewItemFlag],
    [ParentStyleDescription],
    [PowerMotionSeriesFlag],
    [PreviousStatusCode],
    [PrimaryChannelSku],
    [PrimarySeriesName],
    [PrimarySeriesNumber],
    [ProductDepthInches],
    [ProductDepthMeters],
    [ProductHeightInches],
    [ProductHeightMeters],
    [ProductWidthInches],
    [ProductWidthMeters],
    [ReclinerSeriesFlag],
    [ResponsibleOfficeName],
    [RetailBrandName],
    [RetailCategoryChargeType],
    [RetailCategoryDescription],
    [RetailCategoryGroup],
    [RetailDepartmentName],
    [RetailTypeDescription],
    [RowID],
    [SHItemDescriptionSeries],
    [Scene7ImageSet],
    [Seats],
    [SellableItemFlag],
    [SeriesDateArchived],
    [SeriesDiscontinuedFlag],
    [SeriesFeatures],
    [SeriesGrouping],
    [SeriesImage],
    [SeriesMainImage],
    [SeriesNumber],
    [SeriesPrimary],
    [SeriesThirdParty],
    [Showroom],
    [SofaTableSeriesFlag],
    [StandAloneFlag],
    [StatusCodeChangeDate],
    [SuppWeightNetWeightLbs],
    [TrendArrow],
    [UPC],
    [UnitWeightLbs],
    [WedgeSeriesFlag]
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ItemMaster;

GO

-- ============================================================
-- ForecastAccuracy_DW.v_DimWarehouse
-- ============================================================
-- ---- ForecastAccuracy_DW.v_DimWarehouse ----
CREATE VIEW ForecastAccuracy_DW.v_DimWarehouse AS
SELECT * FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Warehouse
GO

-- ============================================================
-- ForecastAccuracy_DW.v_FactForecastActual
-- ============================================================
-- ---- ForecastAccuracy_DW.v_FactForecastActual ----
CREATE VIEW ForecastAccuracy_DW.v_FactForecastActual AS
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Actual demand' AS VARCHAR(20)) AS HorizonCode, StatusCode, VersionName, CAST(QtyDemand AS FLOAT) AS Qty,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    HorizonCode, StatusCode, VersionCode, CAST(QtyForecast AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
UNION ALL SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
    CAST('Naive forecast' AS VARCHAR(20)), StatusCode, VersionName, CAST(QtyDemand AS FLOAT),
    CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly
GO

-- ============================================================
-- ForecastAccuracy_DW.v_FactForecastKpi
-- ============================================================
-- ---- ForecastAccuracy_DW.v_FactForecastKpi ----
CREATE   VIEW ForecastAccuracy_DW.v_FactForecastKpi AS
WITH
fc AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        TRIM(HorizonCode) AS h, CAST(Snapshot AS DATE) AS ds,
        CAST(SUM(QtyForecast) AS FLOAT) AS qf
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
    WHERE HorizonCode IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE),
        TRIM(HorizonCode), CAST(Snapshot AS DATE)
),
act AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qa
    FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE)
),
nv AS (
    SELECT UPPER(TRIM(ItemSKU)) AS i, UPPER(TRIM(WarehouseCode)) AS w,
        CAST(FSCMonthFirst AS DATE) AS mf, CAST(FSCMonthLast AS DATE) AS ml,
        CAST(SUM(QtyDemand) AS FLOAT) AS qn
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly
    GROUP BY UPPER(TRIM(ItemSKU)), UPPER(TRIM(WarehouseCode)),
        CAST(FSCMonthFirst AS DATE), CAST(FSCMonthLast AS DATE)
),
dk AS (
    SELECT i, w, mf, ml FROM fc
    UNION SELECT i, w, mf, ml FROM act
    UNION SELECT i, w, mf, ml FROM nv
),
sp AS (
    SELECT K.i, K.w, K.mf, K.ml, H.HorizonCode AS h
    FROM dk K
    CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon H
)
SELECT
    sp.i AS ItemSKU,
    sp.w AS WarehouseCode,
    sp.mf AS FSCMonthFirst,
    sp.ml AS FSCMonthLast,
    sp.h AS HorizonCode,
    fc.ds AS Snapshot,

    -- Quantities (existing 3)
    CAST(fc.qf AS FLOAT)            AS QtyForecast,
    CAST(act.qa AS FLOAT)           AS QtyActual,
    CAST(nv.qn AS FLOAT)            AS QtyNaiveForecast,

    -- Forecast error (existing 2)
    CAST(COALESCE(fc.qf,0) - COALESCE(act.qa,0) AS FLOAT)
                                    AS QtyFcstError,
    CAST(ABS(COALESCE(fc.qf,0) - COALESCE(act.qa,0)) AS FLOAT)
                                    AS QtyAbsFcstError,

    -- ── NEW: Naive forecast error (2 cols) ──
    CAST(COALESCE(nv.qn,0) - COALESCE(act.qa,0) AS FLOAT)
                                    AS QtyNaiveFcstError,
    CAST(ABS(COALESCE(nv.qn,0) - COALESCE(act.qa,0)) AS FLOAT)
                                    AS QtyAbsNaiveFcstError,

    -- ── NEW: Squared error components for RMSE (2 cols) ──
    CAST(POWER(COALESCE(fc.qf,0) - COALESCE(act.qa,0), 2) AS FLOAT)
                                    AS QtySquaredFcstError,
    CAST(POWER(COALESCE(nv.qn,0) - COALESCE(act.qa,0), 2) AS FLOAT)
                                    AS QtySquaredNaiveFcstError,

    -- ── NEW: Validity flags (2 cols) ──
    CAST(CASE WHEN act.qa IS NOT NULL AND fc.qf IS NOT NULL THEN 1 ELSE 0 END AS INT)
                                    AS ValidObsFlag,
    CAST(CASE WHEN act.qa IS NOT NULL AND act.qa <> 0       THEN 1 ELSE 0 END AS INT)
                                    AS ValidActualNonzeroFlag,

    -- ── NEW: Absolute percentage error (MAPE component) (1 col) ──
    CAST(CASE
        WHEN act.qa IS NOT NULL AND act.qa <> 0
            THEN ABS((COALESCE(fc.qf,0) - act.qa) / act.qa)
        ELSE NULL
    END AS FLOAT)                   AS AbsPctError,

    -- Audit
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT

FROM sp
LEFT JOIN fc  ON sp.i=fc.i  AND sp.w=fc.w  AND sp.mf=fc.mf  AND sp.ml=fc.ml AND sp.h=fc.h
LEFT JOIN act ON sp.i=act.i AND sp.w=act.w AND sp.mf=act.mf AND sp.ml=act.ml
LEFT JOIN nv  ON sp.i=nv.i  AND sp.w=nv.w  AND sp.mf=nv.mf  AND sp.ml=nv.ml;
GO

-- ============================================================
-- InventoryHealth_DW.v_CogsRollingHelper
-- ============================================================
-- ---- InventoryHealth_DW.v_CogsRollingHelper ----
-- Hidden helper. Monthly COGS + 52M/12M rolling.
-- H4 FIX (2026-05-17): ORDER BY FiscalMonthYear (chronological YYYYMM), NOT FiscalMonth (1-12 cycle).
-- M3 FIX (2026-05-17): renamed Cogs52W → Cogs52M (monthly grain).
--   Robert sign-off pending: keep 52M (current) or rewrite weekly grain.
CREATE   VIEW InventoryHealth_DW.v_CogsRollingHelper AS
WITH _CostCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.CostCurrent
    SELECT ItemSku, CostId, StandardCost, ItemRevision
    FROM (
        SELECT
            TRIM(ITNBR)                          AS ItemSku,
            TRIM(STID)                           AS CostId,
            CAST(UCDEF AS DECIMAL(18,4))         AS StandardCost,
            CAST(ITRV  AS VARCHAR(20))           AS ItemRevision,
            ROW_NUMBER() OVER (PARTITION BY TRIM(STID), TRIM(ITNBR) ORDER BY ITRV DESC) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
          AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
monthly AS (
    SELECT
        s.ItemSku,
        s.WarehouseCode,
        d.FSCMonthYearNum                                                  AS FiscalMonthYear,
        SUM(s.QuantityShipped * ISNULL(c.StandardCost, 0))                 AS PeriodCogs,
        SUM(s.QuantityShipped)                                             AS PeriodShippedQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SalesShipment] s
    JOIN [SupplyChain_Gold_Warehouse].[ForecastAccuracy_DW].[DimCalendar] d
         ON d.[Date] = s.InvoiceDate
    LEFT JOIN _CostCurrent c
         ON c.ItemSku = s.ItemSku
    GROUP BY s.ItemSku, s.WarehouseCode, d.FSCMonthYearNum
)
SELECT
    CAST(ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(FiscalMonthYear   AS INT)           AS FiscalMonthYear,
    CAST(PeriodCogs        AS DECIMAL(18,4)) AS PeriodCogs,
    CAST(PeriodShippedQty  AS DECIMAL(18,4)) AS PeriodShippedQty,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear  -- H4 FIX: chronological YYYYMM, not 1-12 cycle
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4))                      AS Cogs12M,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear  -- H4 FIX
        ROWS BETWEEN 51 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4))                      AS Cogs52M   -- M3 FIX: renamed from Cogs52W
FROM monthly
GO

-- ============================================================
-- InventoryHealth_DW.v_DimItem
-- ============================================================
-- ---- InventoryHealth_DW.v_DimItem ----
-- Derived from _ItemMasterExt + computed LifecycleStatus.
-- Schema matches deliverable v1 gold.DimItem (downstream DAX measures depend on these cols).
CREATE   VIEW InventoryHealth_DW.v_DimItem AS
WITH _ItemMasterExt AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ItemMasterExt
    SELECT
        CAST(TRIM(d.ItemSKU)                AS VARCHAR(50))   AS ItemSku,
        CAST(d.ItemDescription              AS VARCHAR(200))  AS ItemDescription,
        CAST(TRIM(d.ItemClassCode)          AS VARCHAR(50))   AS ItemClassCode,
        CAST(d.ItemClassName                AS VARCHAR(100))  AS ItemClassName,
        CAST(d.RetailCategoryName           AS VARCHAR(100))  AS CategoryName,
        CAST(d.RetailCategoryCode           AS VARCHAR(50))   AS CategoryCode,
        CAST(d.CollectiveClass              AS VARCHAR(50))   AS CollectiveClass,
        CAST(d.SeriesNumber                 AS VARCHAR(50))   AS SeriesNumber,
        CAST(d.SeriesName                   AS VARCHAR(100))  AS SeriesName,
        CAST(d.SeriesDescription            AS VARCHAR(200))  AS SeriesDescription,
        CAST(TRIM(d.AFIItemStatus)          AS VARCHAR(10))   AS AfiItemStatus,
        CAST(TRIM(d.PrimaryVendor)          AS VARCHAR(50))   AS PrimaryVendorNumber,
        CAST(v.VendorName                   AS VARCHAR(200))  AS PrimaryVendorName,
        CAST(d.Cubes                        AS DECIMAL(18,4)) AS Cubes,
        CAST(d.FOBArcPrice                  AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(CASE
            WHEN LEFT(TRIM(d.ItemClassCode),1) = 'Z' AND RIGHT(TRIM(d.ItemClassCode),1) = 'K'
            THEN 1 ELSE 0 END AS BIT)                          AS IsFinishedGoodsItem,
        CAST(d.DiscontinuedFlag             AS BIT)            AS DiscontinuedFlag,
        CAST(d.NewItemFlag                  AS BIT)            AS NewItemFlag,
        CAST(d.StatusCodeChangeDate         AS DATE)           AS StatusCodeChangeDate,
        CAST(ISNULL(u.UnavailableFlag, 0)   AS BIT)            AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
    LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
           ON TRIM(v.VendorNumber) = TRIM(d.PrimaryVendor)
    LEFT JOIN (
        SELECT TRIM(ITNBR) AS ItemSku,
               MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
        WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
        GROUP BY TRIM(ITNBR)
    ) u ON u.ItemSku = TRIM(d.ItemSKU)
    WHERE d.ItemSKU IS NOT NULL AND TRIM(d.ItemSKU) <> ''
)
SELECT
    CAST(im.ItemSku                AS VARCHAR(50))    AS ItemSku,
    CAST(im.ItemDescription        AS VARCHAR(200))   AS ItemDescription,
    CAST(im.ItemClassCode          AS VARCHAR(50))    AS ItemClassCode,
    CAST(im.ItemClassName          AS VARCHAR(100))   AS ItemClassName,
    CAST(im.CategoryName           AS VARCHAR(100))   AS CategoryName,
    CAST(im.CategoryCode           AS VARCHAR(50))    AS CategoryCode,
    CAST(im.CollectiveClass        AS VARCHAR(50))    AS CollectiveClass,
    CAST(im.SeriesNumber           AS VARCHAR(50))    AS SeriesNumber,
    CAST(im.SeriesName             AS VARCHAR(100))   AS SeriesName,
    CAST(im.AfiItemStatus          AS VARCHAR(10))    AS AfiItemStatus,
    CAST(CASE
        WHEN im.DiscontinuedFlag = 1      THEN 'Discontinued'
        WHEN im.AfiItemStatus = 'N'       THEN 'New'
        WHEN im.AfiItemStatus = 'A'       THEN 'Active'
        WHEN im.AfiItemStatus IN ('D','R') THEN 'Inactive'
        ELSE 'Other'
    END AS VARCHAR(20))                              AS LifecycleStatus,
    CAST(im.PrimaryVendorNumber    AS VARCHAR(50))    AS PrimaryVendorNumber,
    CAST(im.PrimaryVendorName      AS VARCHAR(200))   AS PrimaryVendorName,
    CAST(im.Cubes                  AS DECIMAL(18,4))  AS Cubes,
    CAST(im.FobArcPrice            AS DECIMAL(18,4))  AS FobArcPrice,
    CAST(im.IsFinishedGoodsItem    AS BIT)            AS IsFinishedGoodsItem,
    CAST(im.DiscontinuedFlag       AS BIT)            AS DiscontinuedFlag,
    CAST(im.NewItemFlag            AS BIT)            AS NewItemFlag,
    CAST(im.StatusCodeChangeDate   AS DATE)           AS StatusCodeChangeDate,
    CAST(im.UnavailableFlag        AS BIT)            AS UnavailableFlag
FROM _ItemMasterExt im
GO

-- ============================================================
-- InventoryHealth_DW.v_DimVendor
-- ============================================================
-- ---- InventoryHealth_DW.v_DimVendor ----
CREATE VIEW InventoryHealth_DW.v_DimVendor AS
SELECT
    CAST(v.VendorNumber  AS VARCHAR(50))   AS VendorNumber,
    CAST(v.VendorName    AS VARCHAR(200))  AS VendorName
FROM [SupplyChain_Processing_Warehouse].[ReferenceMaster_Enh].[Vendor] v
WHERE v.VendorNumber IS NOT NULL
GO

-- ============================================================
-- InventoryHealth_DW.v_DimWarehouse
-- ============================================================
-- ---- InventoryHealth_DW.v_DimWarehouse ----
-- Derived from _WarehouseExt.
CREATE   VIEW InventoryHealth_DW.v_DimWarehouse AS
WITH _WarehouseExt AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.WarehouseExt
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
        CAST(NULL                                  AS DECIMAL(18,4)) AS TotalAvailableWarehouseCube
    FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster] w
    WHERE w.wmaWarehouse IS NOT NULL AND TRIM(w.wmaWarehouse) <> ''
)
SELECT
    CAST(w.WarehouseCode                  AS VARCHAR(50))   AS WarehouseCode,
    CAST(w.WarehouseName                  AS VARCHAR(50))   AS WarehouseName,
    CAST(w.WarehouseType                  AS VARCHAR(100))  AS WarehouseType,
    CAST(w.WarehouseOrderGroup            AS VARCHAR(50))   AS WarehouseOrderGroup,
    CAST(w.WarehouseSourceId              AS VARCHAR(50))   AS WarehouseSourceId,
    CAST(w.SellableWarehouseFlag          AS BIT)           AS SellableWarehouseFlag,
    CAST(w.ControlledFlag                 AS BIT)           AS ControlledFlag,
    CAST(w.WhereMadeCode                  AS VARCHAR(50))   AS WhereMadeCode,
    CAST(w.ManufacturingSite              AS VARCHAR(50))   AS ManufacturingSite,
    CAST(w.IntransitWarehouseCode         AS VARCHAR(50))   AS IntransitWarehouseCode,
    CAST(w.IsFinishedGoodsWarehouse       AS BIT)           AS IsFinishedGoodsWarehouse,
    CAST(w.IsManufacturingWarehouse       AS BIT)           AS IsManufacturingWarehouse,
    CAST(w.TotalAvailableWarehouseCube    AS DECIMAL(18,4)) AS TotalAvailableWarehouseCube
FROM _WarehouseExt w
GO

-- ============================================================
-- InventoryHealth_DW.v_FactInventoryHealthSnapshot
-- ============================================================
-- ---- InventoryHealth_DW.v_FactInventoryHealthSnapshot ----
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, SnapshotType)
-- SnapshotType ∈ ('Current', 'Weekly').
-- v10 conversion: deliverable's 2-pass procedure (CTAS Pass 1 + UPDATE Pass 2) collapsed
-- into a SINGLE view with CTEs handling rolling COGS + AvgInv12M inline (Meta.usp_GenericLoad
-- does CTAS only — no UPDATE). Logic identical to deliverable's gold.usp_Build_FactInventoryHealthSnapshot.
-- M4 FIX (2026-05-17): SLOB + ObsoleteValue require LastInvoiceDate IS NOT NULL guard.
CREATE   VIEW InventoryHealth_DW.v_FactInventoryHealthSnapshot AS
WITH _WarehouseExt AS (
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
        CAST(NULL                                  AS DECIMAL(18,4)) AS TotalAvailableWarehouseCube
    FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AshleyWarehouseMaster] w
    WHERE w.wmaWarehouse IS NOT NULL AND TRIM(w.wmaWarehouse) <> ''
),
_HoldingTransfer AS (
    SELECT TransferNumber, ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube, HeaderStatus, CancelFlag, ShipDateKey, DueDateKey
    FROM (
        SELECT
            TRIM(d.DTFRNO) AS TransferNumber, TRIM(d.DITNBR) AS ItemSku, TRIM(h.HFHOUS) AS WarehouseCode,
            CAST(d.DTFRQT AS DECIMAL(18,4)) AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4)) AS ShippedQty,
            CAST(d.DCUBES AS DECIMAL(18,4)) AS TransferCube,
            TRIM(h.HSTATS) AS HeaderStatus, TRIM(h.HCANCL) AS CancelFlag,
            CAST(h.HSHDTE AS INT) AS ShipDateKey, CAST(h.HDLDTE AS INT) AS DueDateKey,
            ROW_NUMBER() OVER (PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR) ORDER BY h.HDLDTE DESC) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS) AND TRIM(h.HCANCL) = 'N'
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
_InventoryCurrent AS (
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
      AND LEFT(TRIM(b.ITCLS),1) = 'Z' AND RIGHT(TRIM(b.ITCLS),1) = 'K'
      AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
),
_ManufacturingOrder AS (
    SELECT
        CAST(TRIM(ORDNO)  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END AS DECIMAL(18,4))  AS MOOnOrderQty,
        CAST(ODUDT        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
),
_ItemMasterExt AS (
    SELECT
        CAST(TRIM(d.ItemSKU)                AS VARCHAR(50))   AS ItemSku,
        CAST(d.ItemDescription              AS VARCHAR(200))  AS ItemDescription,
        CAST(TRIM(d.ItemClassCode)          AS VARCHAR(50))   AS ItemClassCode,
        CAST(d.ItemClassName                AS VARCHAR(100))  AS ItemClassName,
        CAST(d.RetailCategoryName           AS VARCHAR(100))  AS CategoryName,
        CAST(d.RetailCategoryCode           AS VARCHAR(50))   AS CategoryCode,
        CAST(d.CollectiveClass              AS VARCHAR(50))   AS CollectiveClass,
        CAST(d.SeriesNumber                 AS VARCHAR(50))   AS SeriesNumber,
        CAST(d.SeriesName                   AS VARCHAR(100))  AS SeriesName,
        CAST(d.SeriesDescription            AS VARCHAR(200))  AS SeriesDescription,
        CAST(TRIM(d.AFIItemStatus)          AS VARCHAR(10))   AS AfiItemStatus,
        CAST(TRIM(d.PrimaryVendor)          AS VARCHAR(50))   AS PrimaryVendorNumber,
        CAST(v.VendorName                   AS VARCHAR(200))  AS PrimaryVendorName,
        CAST(d.Cubes                        AS DECIMAL(18,4)) AS Cubes,
        CAST(d.FOBArcPrice                  AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(d.DiscontinuedFlag             AS BIT)           AS DiscontinuedFlag,
        CAST(d.NewItemFlag                  AS BIT)           AS NewItemFlag,
        CAST(d.StatusCodeChangeDate         AS DATE)          AS StatusCodeChangeDate,
        CAST(ISNULL(u.UnavailableFlag, 0)   AS BIT)           AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
    LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
           ON TRIM(v.VendorNumber) = TRIM(d.PrimaryVendor)
    LEFT JOIN (
        SELECT TRIM(ITNBR) AS ItemSku,
               MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
        WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
        GROUP BY TRIM(ITNBR)
    ) u ON u.ItemSku = TRIM(d.ItemSKU)
    WHERE d.ItemSKU IS NOT NULL AND TRIM(d.ItemSKU) <> ''
),
_CostCurrent AS (
    SELECT ItemSku, CostId, StandardCost, ItemRevision
    FROM (
        SELECT
            TRIM(ITNBR) AS ItemSku, TRIM(STID) AS CostId,
            CAST(UCDEF AS DECIMAL(18,4)) AS StandardCost,
            CAST(ITRV AS VARCHAR(20)) AS ItemRevision,
            ROW_NUMBER() OVER (PARTITION BY TRIM(STID), TRIM(ITNBR) ORDER BY ITRV DESC) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
          AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
_PurchaseOrder AS (
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes
    FROM (
        SELECT
            TRIM(podordernum) AS PoNumber,
            CAST(poditemsequence AS INT) AS PoLine,
            TRIM(podvendornum) AS VendorNumber,
            TRIM(poditemnum) AS ItemSku,
            TRIM(podwarehouse) AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))   AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4)) AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4)) AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4)) AS InTransitQtySource,
            CAST(podduedate AS DATE) AS DueDate,
            ROW_NUMBER() OVER (PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence ORDER BY podduedate DESC) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
          AND TRIM(podwarehouse) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
          AND TRIM(h.pomvendornum) = r.VendorNumber
    WHERE r.rn = 1
),
base AS (
    -- Current daily rows (rolling 7d)
    SELECT
        CAST('Current'                          AS VARCHAR(10))  AS SnapshotType,
        ic.SnapshotDate                                          AS SnapshotDate,
        ic.ItemSku, ic.WarehouseCode,
        ic.OnHandQty,
        CAST('ItemMaster_AFI' AS VARCHAR(64))                    AS SourceSystem,
        CAST('ITEMBL'         AS VARCHAR(128))                   AS SourceTable
    FROM _InventoryCurrent ic
    WHERE ic.SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))

    UNION ALL

    -- Weekly history rows
    SELECT
        CAST('Weekly'                                AS VARCHAR(10)),
        iw.SnapshotDate,
        iw.ItemSku, iw.WarehouseCode,
        iw.OnHandQty,
        CAST('SupplyChain_Enh_1'                     AS VARCHAR(64)),
        CAST('DemandInventorySnapshotWeekly'         AS VARCHAR(128))
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeekly] iw
),
latest_current_date AS (
    SELECT MAX(SnapshotDate) AS MaxDate
    FROM _InventoryCurrent
),
-- Snapshot-aware PO/MO/Hold aggregates
po_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(POOnOrderQty) AS POOnOrderQty,
        SUM(POInTransitQty) AS POInTransitQty
    FROM _PurchaseOrder
    GROUP BY ItemSku, WarehouseCode
),
po_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(POOnOrderQty) AS POOnOrderQty,
        SUM(POInTransitQty) AS POInTransitQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
mo_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM _ManufacturingOrder
    GROUP BY ItemSku, WarehouseCode
),
mo_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(MOOnOrderQty) AS MOOnOrderQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_snap AS (
    SELECT SnapshotDate, ItemSku, WarehouseCode,
        SUM(TransferQty) AS OnHoldQty,
        SUM(TransferCube) AS OnHoldCube
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[HoldingTransferSnapshotDaily]
    GROUP BY SnapshotDate, ItemSku, WarehouseCode
),
hold_curr AS (
    SELECT ItemSku, WarehouseCode,
        SUM(TransferQty) AS OnHoldQty,
        SUM(TransferCube) AS OnHoldCube
    FROM _HoldingTransfer
    GROUP BY ItemSku, WarehouseCode
),
-- Transfer-in InTransit (paired warehouse from ITEMBL)
ti_curr AS (
    SELECT
        TRIM(b.ITNBR)         AS ItemSku,
        TRIM(w.WarehouseCode) AS WarehouseCode,
        SUM(CAST(b.MOHTQ AS DECIMAL(18,4)))   AS TransferInInTransitQty
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    JOIN _WarehouseExt w
         ON TRIM(w.IntransitWarehouseCode) = TRIM(b.HOUSE)
    WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
      AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
    GROUP BY TRIM(b.ITNBR), TRIM(w.WarehouseCode)
),
-- Pre-derive InventoryValueAtCost for AvgInv12M computation
ivc_monthly AS (
    SELECT DISTINCT
        b.ItemSku, b.WarehouseCode, d.FSCMonthYearNum AS FiscalMonthYear,
        ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS InventoryValueAtCost
    FROM base b
    JOIN [SupplyChain_Gold_Warehouse].[ForecastAccuracy_DW].[DimCalendar] d
         ON d.[Date] = b.SnapshotDate
    LEFT JOIN _CostCurrent cc
         ON cc.ItemSku = b.ItemSku
    WHERE d.[Date] = (
        SELECT MAX(d2.[Date])
        FROM [SupplyChain_Gold_Warehouse].[ForecastAccuracy_DW].[DimCalendar] d2
        WHERE d2.FSCMonthYearNum = d.FSCMonthYearNum
    )  -- month-end approximation
),
avg_ivc12 AS (
    SELECT
        ItemSku, WarehouseCode, FiscalMonthYear,
        AVG(InventoryValueAtCost) OVER (
            PARTITION BY ItemSku, WarehouseCode
            ORDER BY FiscalMonthYear
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) AS AvgInvValue12M
    FROM ivc_monthly
)
SELECT
    -- Grain
    CAST(b.ItemSku           AS VARCHAR(50))  AS ItemSku,
    CAST(b.WarehouseCode     AS VARCHAR(50))  AS WarehouseCode,
    CAST(b.SnapshotDate      AS DATE)         AS SnapshotDate,
    CAST(b.SnapshotType      AS VARCHAR(10))  AS SnapshotType,
    CAST(d.FSCWeekLast       AS DATE)         AS WeekEndingDate,
    CAST(d.DateSK            AS INT)          AS DateKey,    -- FIX 2026-05-19: DimCalendar (Gold) uses DateSK; Calendar (Silver) uses SKDate
    CAST(d.FSCMonthNum       AS INT)          AS FiscalMonth,
    CAST(d.FSCMonthYearNum   AS INT)          AS FiscalMonthYear,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              AND b.SnapshotDate = (SELECT MaxDate FROM latest_current_date)
              THEN 1 ELSE 0 END AS BIT)        AS IsLatestSnapshot,
    CAST(b.SourceSystem      AS VARCHAR(64))   AS SourceSystem,
    CAST(b.SourceTable       AS VARCHAR(128))  AS SourceTable,
    CAST(1                   AS BIGINT)        AS RuleVersionKey,

    -- Base supply qty
    CAST(ISNULL(b.OnHandQty, 0)                          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ISNULL(ti.TransferInInTransitQty, 0)            AS DECIMAL(18,4)) AS TransferInInTransitQty,

    -- Snapshot-aware PO / MO / Hold pull
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(pc.POInTransitQty, 0)
              ELSE ISNULL(ps.POInTransitQty, 0) END     AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(pc.POOnOrderQty, 0)
              ELSE ISNULL(ps.POOnOrderQty, 0) END       AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN b.SnapshotType = 'Current'
              THEN ISNULL(mc.MOOnOrderQty, 0)
              ELSE ISNULL(ms.MOOnOrderQty, 0) END       AS DECIMAL(18,4)) AS MOOnOrderQty,

    -- Derived totals
    CAST(ISNULL(ti.TransferInInTransitQty,0) +
         CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POInTransitQty,0)
              ELSE ISNULL(ps.POInTransitQty,0) END
         AS DECIMAL(18,4))                              AS InTransitQty,
    CAST(CASE WHEN b.SnapshotType='Current'
              THEN ISNULL(pc.POOnOrderQty,0) + ISNULL(mc.MOOnOrderQty,0)
              ELSE ISNULL(ps.POOnOrderQty,0) + ISNULL(ms.MOOnOrderQty,0) END
         AS DECIMAL(18,4))                              AS OnOrderQty,

    -- Demand & coverage
    CAST(awd.AwdQty         AS DECIMAL(18,4))           AS AwdQty,
    CAST(awd.AwdSource      AS VARCHAR(20))             AS AwdSource,
    CAST(CASE WHEN awd.AwdQty > 0
              THEN b.OnHandQty / awd.AwdQty END
         AS DECIMAL(18,4))                              AS WeeksOfSupply,
    CAST(ss.SafetyStockTarget AS DECIMAL(18,4))         AS SafetyStockTargetQty,
    CAST(CASE WHEN ss.SafetyStockTarget > 0
              THEN b.OnHandQty / ss.SafetyStockTarget END
         AS DECIMAL(18,4))                              AS SafetyStockMultiple,

    -- Inventory classification (BRD v1)
    CAST(CASE
        WHEN dim.AfiItemStatus IN ('D','R')
         AND (ISNULL(b.OnHandQty,0)
            + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
            + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
            THEN 'Inactive'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 0.5 * ss.SafetyStockTarget THEN 'Below Target'
        WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 1.5 * ss.SafetyStockTarget THEN 'Sweet Spot'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 17  * awd.AwdQty THEN 'Over Target'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 52  * awd.AwdQty THEN 'Excess'
        WHEN awd.AwdQty > 0 AND b.OnHandQty <= 104 * awd.AwdQty THEN 'Aggressive Excess'
        ELSE 'TB Inventory'
    END AS VARCHAR(30))                                 AS InventoryClassification,

    -- Financial
    CAST(cc.StandardCost  AS DECIMAL(18,4))             AS StandardCost,
    CAST(dim.FobArcPrice  AS DECIMAL(18,4))             AS FobArcPrice,
    CAST(dim.Cubes        AS DECIMAL(18,4))             AS Cubes,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0) AS DECIMAL(18,4)) AS InventoryValueAtCost,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.FobArcPrice,0) AS DECIMAL(18,4)) AS InventoryValueAtRevenue,
    CAST(ISNULL(b.OnHandQty,0) * ISNULL(dim.Cubes,0)       AS DECIMAL(18,4)) AS UsedStorageCube,

    -- Rolling COGS (Pass 2 inlined via JOIN to v_CogsRollingHelper)
    CAST(coh.PeriodCogs AS DECIMAL(18,4))               AS PeriodCogs,
    CAST(coh.Cogs52M    AS DECIMAL(18,4))               AS Cogs52M,
    CAST(coh.Cogs12M    AS DECIMAL(18,4))               AS Cogs12M,
    CAST(aiv.AvgInvValue12M AS DECIMAL(18,4))           AS AverageInventoryValueAtCost,

    -- Status flags
    CAST(lh.LastInvoiceDate AS DATE)                    AS LastInvoiceDate,
    CAST(dim.LifecycleStatus AS VARCHAR(20))            AS LifecycleStatus,
    CAST(CASE WHEN dim.AfiItemStatus IN ('D','R')
              AND (ISNULL(b.OnHandQty,0)
                + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
                + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS InactiveFlag,
    -- M4 FIX (2026-05-17): require LastInvoiceDate IS NOT NULL to avoid false-positive SLOB on new items.
    CAST(CASE WHEN dim.AfiItemStatus <> 'N'
              AND lh.LastInvoiceDate IS NOT NULL
              AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
              THEN 1 ELSE 0 END
         AS BIT)                                        AS SlobFlag,
    CAST(CASE WHEN ISNULL(mf.HasMovementLast17W, 0) = 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS NoMovementFlag,
    CAST(dim.UnavailableFlag AS BIT)                    AS UnavailableFlag,

    -- Hold (snapshot-aware)
    CAST(CASE WHEN b.SnapshotType='Current'
              THEN ISNULL(hc.OnHoldQty, 0)
              ELSE ISNULL(hs.OnHoldQty, 0) END
         AS DECIMAL(18,4))                              AS OnHoldQty,
    CAST(CASE WHEN (CASE WHEN b.SnapshotType='Current' THEN ISNULL(hc.OnHoldQty,0) ELSE ISNULL(hs.OnHoldQty,0) END) > 0
              THEN 1 ELSE 0 END
         AS BIT)                                        AS OnHoldFlag,

    -- Obsolete (SLOB-flagged inventory value at cost)
    -- M4 FIX: same NULL handling as SlobFlag
    CAST(CASE WHEN dim.AfiItemStatus <> 'N'
              AND lh.LastInvoiceDate IS NOT NULL
              AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
              THEN ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0)
              ELSE 0 END
         AS DECIMAL(18,4))                              AS ObsoleteValue
FROM base b
LEFT JOIN [SupplyChain_Gold_Warehouse].[ForecastAccuracy_DW].[DimCalendar] d
       ON d.[Date] = b.SnapshotDate
-- DimItem reused from forecast's DimProduct + augmented inline with InventoryHistory ItemMasterExt fields
LEFT JOIN _ItemMasterExt dim_ext
       ON dim_ext.ItemSku = b.ItemSku
LEFT JOIN (
    -- Mirror deliverable's DimItem layout: select needed cols from ItemMasterExt + lifecycle case
    SELECT
        ItemSku, AfiItemStatus, FobArcPrice, Cubes, UnavailableFlag,
        CASE
            WHEN DiscontinuedFlag = 1     THEN 'Discontinued'
            WHEN AfiItemStatus = 'N'      THEN 'New'
            WHEN AfiItemStatus = 'A'      THEN 'Active'
            WHEN AfiItemStatus IN ('D','R') THEN 'Inactive'
            ELSE 'Other'
        END AS LifecycleStatus
    FROM _ItemMasterExt
) dim ON dim.ItemSku = b.ItemSku
LEFT JOIN _CostCurrent cc
       ON cc.ItemSku = b.ItemSku
LEFT JOIN ti_curr ti                  ON ti.ItemSku=b.ItemSku AND ti.WarehouseCode=b.WarehouseCode
LEFT JOIN po_curr pc                  ON pc.ItemSku=b.ItemSku AND pc.WarehouseCode=b.WarehouseCode
LEFT JOIN po_snap ps                  ON ps.ItemSku=b.ItemSku AND ps.WarehouseCode=b.WarehouseCode AND ps.SnapshotDate=b.SnapshotDate
LEFT JOIN mo_curr mc                  ON mc.ItemSku=b.ItemSku AND mc.WarehouseCode=b.WarehouseCode
LEFT JOIN mo_snap ms                  ON ms.ItemSku=b.ItemSku AND ms.WarehouseCode=b.WarehouseCode AND ms.SnapshotDate=b.SnapshotDate
LEFT JOIN hold_curr hc                ON hc.ItemSku=b.ItemSku AND hc.WarehouseCode=b.WarehouseCode
LEFT JOIN hold_snap hs                ON hs.ItemSku=b.ItemSku AND hs.WarehouseCode=b.WarehouseCode AND hs.SnapshotDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
       ON awd.ItemSku=b.ItemSku AND awd.WarehouseCode=b.WarehouseCode AND awd.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceHelper] lh
       ON lh.ItemSku=b.ItemSku AND lh.WarehouseCode=b.WarehouseCode AND lh.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[MovementFlagHelper] mf
       ON mf.ItemSku=b.ItemSku AND mf.WarehouseCode=b.WarehouseCode AND mf.AsOfDate=b.SnapshotDate
LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss
       ON ss.ItemSku=b.ItemSku AND ss.WarehouseCode=b.WarehouseCode AND ss.AsOfDate=b.SnapshotDate
-- Rolling COGS (Pass 2 inlined): join CogsRollingHelper on FiscalMonthYear of SnapshotDate
LEFT JOIN [SupplyChain_Gold_Warehouse].[InventoryHealth_DW].[CogsRollingHelper] coh
       ON coh.ItemSku=b.ItemSku AND coh.WarehouseCode=b.WarehouseCode
      AND coh.FiscalMonthYear=d.FSCMonthYearNum
LEFT JOIN avg_ivc12 aiv
       ON aiv.ItemSku=b.ItemSku AND aiv.WarehouseCode=b.WarehouseCode
      AND aiv.FiscalMonthYear=d.FSCMonthYearNum
GO

-- ============================================================
-- InventoryHealth_DW.v_FactInventoryRiskForward
-- ============================================================
-- ---- InventoryHealth_DW.v_FactInventoryRiskForward ----
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate)
-- Source: _SupplyPlan (latest snapshot per WeekEnding) + AtpWeekEnding (Week2) + AllocatedDemand
-- H5 FIX (2026-05-17): WeekFourFlag = exact week-4 ending only (Saturday + 28 days). Robert sign-off pending.
CREATE   VIEW InventoryHealth_DW.v_FactInventoryRiskForward AS
WITH _SupplyPlan AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.SupplyPlan
    SELECT
        CAST(TRIM(spdItem)                              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(spdWarehouse)                         AS VARCHAR(50))   AS WarehouseCode,
        CAST(dtea                                       AS DATE)          AS SnapshotDate,
        CAST(spdWeekEnding                              AS DATE)          AS WeekEndingDate,
        CAST(spdBeginingBalance                         AS DECIMAL(18,4)) AS BeginningBalanceQty,
        CAST(spdFirmDemands                             AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(spdNetForecast                             AS DECIMAL(18,4)) AS NetForecastQty,
        CAST(spdFirmPurchaseOrders                      AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
        CAST(spdPlannedPurchaseOrders                   AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
        CAST(spdOnOrderTransferIn                       AS DECIMAL(18,4)) AS OnOrderTransferInQty,
        CAST(spdShippableInventory                      AS DECIMAL(18,4)) AS ShippableInventoryQty,
        CAST(spdSafetyStock                             AS DECIMAL(18,4)) AS SafetyStockTargetQty,
        CAST(spdMonthsOfSupply                          AS DECIMAL(18,4)) AS MonthsOfSupply,
        CAST(CASE WHEN spdShippableInventory < 0
                  THEN ABS(CAST(spdShippableInventory AS DECIMAL(18,4)))
                  ELSE 0 END                            AS DECIMAL(18,4)) AS SINegQty
    FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
    WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
      AND TRIM(spdItem) <> '' AND TRIM(spdWarehouse) <> ''
),
_AtpWeekEnding AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.AtpWeekEnding
    SELECT
        u.ItemSku, u.WarehouseCode, u.WeekNumber,
        CAST(DATEADD(week, u.WeekNumber - 1, b.BaseWeekEndingDate) AS DATE) AS WeekEndingDate,
        u.AtpQty
    FROM (
        SELECT
            TRIM(APITNB) AS ItemSku, TRIM(APHOUS) AS WarehouseCode,
            CAST(REPLACE(WeekCol, 'APAT', '') AS INT) AS WeekNumber,
            CAST(AtpQty AS DECIMAL(18,4)) AS AtpQty
        FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
        UNPIVOT (AtpQty FOR WeekCol IN (
            APAT01,APAT02,APAT03,APAT04,APAT05,APAT06,APAT07,APAT08,APAT09,APAT10,
            APAT11,APAT12,APAT13,APAT14,APAT15,APAT16,APAT17,APAT18,APAT19,APAT20,
            APAT21,APAT22,APAT23,APAT24,APAT25,APAT26,APAT27,APAT28,APAT29,APAT30,
            APAT31,APAT32,APAT33,APAT34,APAT35,APAT36,APAT37,APAT38,APAT39,APAT40,
            APAT41,APAT42,APAT43
        )) un
    ) u
    JOIN (
        SELECT TRIM(APITNB) AS ItemSku, TRIM(APHOUS) AS WarehouseCode,
               TRY_CAST(CAST(CAST(APWK01 AS BIGINT) AS VARCHAR(8)) AS DATE) AS BaseWeekEndingDate
        FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
        WHERE APITNB IS NOT NULL AND APHOUS IS NOT NULL
          AND TRIM(APITNB) <> '' AND TRIM(APHOUS) <> ''
    ) b ON b.ItemSku = u.ItemSku AND b.WarehouseCode = u.WarehouseCode
    WHERE b.BaseWeekEndingDate IS NOT NULL
),
_AllocatedDemandCandidate AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.AllocatedDemandCandidate
    SELECT
        CAST(TRIM(d.ItemSKU)             AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(d.Warehouse)           AS VARCHAR(50))   AS WarehouseCode,
        CAST(d.QuantityBackOrdered       AS DECIMAL(18,4)) AS AllocatedDemandQty
    FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
    WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
      AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
      AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
      AND TRIM(d.ItemSKU) <> '' AND TRIM(d.Warehouse) <> ''
),
_ItemMasterExt AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ItemMasterExt
    SELECT
        CAST(TRIM(d.ItemSKU)                AS VARCHAR(50))   AS ItemSku,
        CAST(d.ItemDescription              AS VARCHAR(200))  AS ItemDescription,
        CAST(TRIM(d.ItemClassCode)          AS VARCHAR(50))   AS ItemClassCode,
        CAST(d.ItemClassName                AS VARCHAR(100))  AS ItemClassName,
        CAST(d.RetailCategoryName           AS VARCHAR(100))  AS CategoryName,
        CAST(d.RetailCategoryCode           AS VARCHAR(50))   AS CategoryCode,
        CAST(d.CollectiveClass              AS VARCHAR(50))   AS CollectiveClass,
        CAST(d.SeriesNumber                 AS VARCHAR(50))   AS SeriesNumber,
        CAST(d.SeriesName                   AS VARCHAR(100))  AS SeriesName,
        CAST(d.SeriesDescription            AS VARCHAR(200))  AS SeriesDescription,
        CAST(TRIM(d.AFIItemStatus)          AS VARCHAR(10))   AS AfiItemStatus,
        CAST(TRIM(d.PrimaryVendor)          AS VARCHAR(50))   AS PrimaryVendorNumber,
        CAST(v.VendorName                   AS VARCHAR(200))  AS PrimaryVendorName,
        CAST(d.Cubes                        AS DECIMAL(18,4)) AS Cubes,
        CAST(d.FOBArcPrice                  AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(CASE
            WHEN LEFT(TRIM(d.ItemClassCode),1) = 'Z' AND RIGHT(TRIM(d.ItemClassCode),1) = 'K'
            THEN 1 ELSE 0 END AS BIT)                          AS IsFinishedGoodsItem,
        CAST(d.DiscontinuedFlag             AS BIT)            AS DiscontinuedFlag,
        CAST(d.NewItemFlag                  AS BIT)            AS NewItemFlag,
        CAST(d.StatusCodeChangeDate         AS DATE)           AS StatusCodeChangeDate,
        CAST(ISNULL(u.UnavailableFlag, 0)   AS BIT)            AS UnavailableFlag
    FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] d
    LEFT JOIN [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
           ON TRIM(v.VendorNumber) = TRIM(d.PrimaryVendor)
    LEFT JOIN (
        SELECT TRIM(ITNBR) AS ItemSku,
               MAX(CASE WHEN TRIM(MFPUS) = 'U' THEN 1 ELSE 0 END) AS UnavailableFlag
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITBEXT]
        WHERE ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
        GROUP BY TRIM(ITNBR)
    ) u ON u.ItemSku = TRIM(d.ItemSKU)
    WHERE d.ItemSKU IS NOT NULL AND TRIM(d.ItemSKU) <> ''
),
latest_plan AS (
    SELECT
        ItemSku, WarehouseCode, WeekEndingDate,
        BeginningBalanceQty, FirmDemandQty, NetForecastQty,
        FirmPurchaseOrderQty, PlannedPurchaseOrderQty,
        OnOrderTransferInQty, ShippableInventoryQty,
        SafetyStockTargetQty, MonthsOfSupply, SINegQty,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, WeekEndingDate
            ORDER BY SnapshotDate DESC
        ) AS rn
    FROM _SupplyPlan
),
atp_w2 AS (
    SELECT ItemSku, WarehouseCode, AtpQty
    FROM _AtpWeekEnding
    WHERE WeekNumber = 2
),
alloc AS (
    SELECT
        ItemSku, WarehouseCode,
        SUM(AllocatedDemandQty) AS AllocatedDemandQty
    FROM _AllocatedDemandCandidate
    GROUP BY ItemSku, WarehouseCode
)
SELECT
    CAST(lp.ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(lp.WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(lp.WeekEndingDate     AS DATE)          AS WeekEndingDate,
    CAST(d.DateSK              AS INT)           AS DateKey,    -- FIX 2026-05-19: DimCalendar (Gold) uses DateSK
    CAST(lp.BeginningBalanceQty       AS DECIMAL(18,4)) AS BeginningBalanceQty,
    CAST(lp.FirmDemandQty             AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(lp.NetForecastQty            AS DECIMAL(18,4)) AS NetForecastQty,
    CAST(lp.FirmPurchaseOrderQty      AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
    CAST(lp.PlannedPurchaseOrderQty   AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
    CAST(lp.OnOrderTransferInQty      AS DECIMAL(18,4)) AS OnOrderTransferInQty,
    CAST(lp.ShippableInventoryQty     AS DECIMAL(18,4)) AS ShippableInventoryQty,
    CAST(lp.SafetyStockTargetQty      AS DECIMAL(18,4)) AS SafetyStockTargetQty,
    CAST(lp.MonthsOfSupply            AS DECIMAL(18,4)) AS MonthsOfSupply,
    -- 14-day demand/inbound derived
    CAST(lp.FirmDemandQty * (14.0/7.0)                                 AS DECIMAL(18,4)) AS ExpectedDemand14DQty,
    CAST((lp.FirmPurchaseOrderQty + lp.OnOrderTransferInQty) * (14.0/7.0) AS DECIMAL(18,4)) AS Inbound14DQty,
    CAST(ISNULL(al.AllocatedDemandQty, 0)        AS DECIMAL(18,4))      AS AllocatedDemandQty,
    CAST(ISNULL(at.AtpQty, 0)                    AS DECIMAL(18,4))      AS ATPQty,
    CAST(CASE WHEN ISNULL(at.AtpQty, 0) > 0 THEN 1 ELSE 0 END AS BIT)   AS ATPInStockFlag,
    CAST(CASE WHEN lp.ShippableInventoryQty > 0 THEN 1 ELSE 0 END AS BIT) AS ShippableInStockFlag,
    CAST(lp.SINegQty                             AS DECIMAL(18,4))      AS SINegQty,
    CAST(lp.SINegQty * ISNULL(dim.FobArcPrice, 0) AS DECIMAL(18,4))     AS RevenueAtRiskValue,
    -- H5 FIX (2026-05-17): exact week-4 ending only (Saturday + 28 days).
    -- BRD §6.3 "At Week Four Ending" = single week. Robert sign-off pending.
    CAST(CASE WHEN lp.WeekEndingDate = (
                  DATEADD(day,
                          ((7 - DATEPART(weekday, SYSUTCDATETIME()) + 7) % 7) + 28,
                          CAST(SYSUTCDATETIME() AS DATE))
              )
              THEN 1 ELSE 0 END AS BIT)                                 AS WeekFourFlag,
    CAST(dim.FobArcPrice                         AS DECIMAL(18,4))      AS FobArcPrice,
    CAST(1                                       AS BIGINT)             AS RuleVersionKey
FROM latest_plan lp
LEFT JOIN [SupplyChain_Gold_Warehouse].[ForecastAccuracy_DW].[DimCalendar] d
       ON d.[Date] = lp.WeekEndingDate
LEFT JOIN _ItemMasterExt dim
       ON dim.ItemSku = lp.ItemSku
LEFT JOIN atp_w2 at  ON at.ItemSku=lp.ItemSku AND at.WarehouseCode=lp.WarehouseCode
LEFT JOIN alloc al   ON al.ItemSku=lp.ItemSku AND al.WarehouseCode=lp.WarehouseCode
WHERE lp.rn = 1
GO

