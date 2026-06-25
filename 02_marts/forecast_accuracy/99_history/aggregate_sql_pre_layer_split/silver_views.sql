-- ============================================================
-- Silver Views — Domain Business Logic
-- ============================================================
-- Layer: Silver. Pattern: JOIN + UPPER(TRIM(code)) + business derivations + aggregation.
-- Source: SupplyChain_Processing_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- ForecastHistory_Enh.v_ForecastDemandMonthly ----
-- 2026-05-19 SWAP: was legacy EDW supplement (SC_LH ver2 to DF2, dropped post-EDW-Exit)
-- 2026-06-23 CANONICAL: now reads Staging.DemandForecastSnapshotDaily (Enterprise ETL target; source wrapper Staging_Wrk.v_DemandForecastSnapshotDaily)
--                   — replaces direct EL.SupplyChain_Enh.DemandForecastSnapshotDaily (dirty with row-dup x16 from Q1 2025)
-- Logic unchanged: ForecastCycle JOIN, Lag-N HorizonCode, GROUP BY summed forecast.
-- See staging_ddl.sql for Staging.DemandForecastSnapshotDaily definition.
CREATE VIEW ForecastHistory_Enh.v_ForecastDemandMonthly AS
WITH Raw AS (
    SELECT
        f.dfcItem                                            AS ItemSKU,
        f.dfcWarehouse                                       AS WarehouseCode,
        UPPER(f.DfcCustomerGroups)                           AS CustomerGroupCode,
        DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS INT), CAST(f.dfcFiscalMonth%100 AS INT), 1) AS FiscalMonth,
        CAST(f.dfcSnapshot AS DATE)                          AS Snapshot,
        f.dfcResultantForecast                               AS QtyResultantForecast,
        f.dfcPromotionalLift                                 AS QtyPromotionalLift
    FROM Staging.DemandForecastSnapshotDaily AS f
    INNER JOIN ReferenceMaster_Enh.ForecastCycle AS c ON CAST(f.dfcSnapshot AS DATE)=c.ForecastSnapshot
),
Calc AS (
    SELECT FC.ItemSKU, FC.WarehouseCode, FC.CustomerGroupCode,
        CAL.FSCMonthFirst, CAL.FSCMonthLast, FC.Snapshot,
        CASE WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=0 THEN 'Lag-0'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=1 THEN 'Lag-1'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=2 THEN 'Lag-2'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=3 THEN 'Lag-3'
             WHEN (YEAR(FC.FiscalMonth)*12+MONTH(FC.FiscalMonth))-(YEAR(FC.Snapshot)*12+MONTH(FC.Snapshot))=4 THEN 'Lag-4'
             ELSE '>Lag-4' END AS HorizonCode,
        CAST(SUM(FC.QtyResultantForecast+FC.QtyPromotionalLift) AS FLOAT) AS QtyForecast,
        CAST(CONCAT('V ',FORMAT(FC.Snapshot,'yyyy.MM')) AS VARCHAR(20)) AS VersionCode, 'Forecast' AS StatusCode
    FROM Raw AS FC
    INNER JOIN ReferenceMaster_Enh.Calendar AS CAL ON CAL.Date=FC.FiscalMonth
    WHERE FC.FiscalMonth>=DATEADD(MONTH,-36,DATETRUNC(YEAR,DATEADD(MONTH,-6,CAST(GETDATE() AS DATE))))
      AND FC.FiscalMonth<=DATEADD(MONTH,12,DATETRUNC(YEAR,DATEADD(MONTH,6,CAST(GETDATE() AS DATE))))
    GROUP BY FC.ItemSKU, FC.WarehouseCode, FC.CustomerGroupCode, CAL.FSCMonthFirst, CAL.FSCMonthLast, FC.Snapshot, FC.FiscalMonth
)
SELECT CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSKU, CAST(TRIM(WarehouseCode) AS VARCHAR(10)) AS WarehouseCode,
    CAST(TRIM(CustomerGroupCode) AS VARCHAR(50)) AS CustomerGroupCode,
    CAST(FSCMonthFirst AS DATE) AS FSCMonthFirst, CAST(FSCMonthLast AS DATE) AS FSCMonthLast,
    CAST(Snapshot AS DATE) AS Snapshot, CAST(TRIM(HorizonCode) AS VARCHAR(10)) AS HorizonCode,
    CAST(QtyForecast AS FLOAT) AS QtyForecast, CAST(TRIM(VersionCode) AS VARCHAR(20)) AS VersionCode,
    CAST(TRIM(StatusCode) AS VARCHAR(20)) AS StatusCode
FROM Calc

GO

-- ---- ForecastHistory_Enh.v_NaiveForecastMonthly ----
CREATE VIEW ForecastHistory_Enh.v_NaiveForecastMonthly AS
WITH
mw AS (SELECT FSCMonthFirst, COUNT(DISTINCT FSCWeekFirst) AS NumWeeks FROM ReferenceMaster_Enh.Calendar GROUP BY FSCMonthFirst),
am AS (SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast, SUM(QtyDemand) AS QtyActual FROM SalesHistory_Enh.ActualDemandMonthly GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast),
al AS (SELECT A.*, MW.NumWeeks,
    LAG(A.QtyActual) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS QtyActualPrior,
    LAG(MW.NumWeeks) OVER (PARTITION BY A.ItemSKU, A.WarehouseCode, A.CustomerGroupCode ORDER BY A.FSCMonthFirst) AS NumWeeksPrior
    FROM am A INNER JOIN mw MW ON MW.FSCMonthFirst=A.FSCMonthFirst),
cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT L.ItemSKU, L.WarehouseCode, L.CustomerGroupCode, L.FSCMonthFirst, L.FSCMonthLast,
    CAST(L.QtyActualPrior/L.NumWeeksPrior*L.NumWeeks AS INT) AS QtyDemand,
    'Naive Forecast' AS StatusCode, 'Naive Forecast' AS VersionName
FROM al L INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=L.FSCMonthFirst CROSS JOIN cf
WHERE L.QtyActualPrior IS NOT NULL AND L.NumWeeksPrior>0 AND L.WarehouseCode NOT IN ('C','CNW','C35','55')
    AND CAL.FSCMonthYearNum>=(cf.FSCYearNum-3)*100 AND CAL.FSCMonthYearNum<=(cf.FSCYearNum+1)*100+1299

GO

-- ---- OpenOrderHistory_Enh.v_OpenOrderLineLevel ----
CREATE VIEW OpenOrderHistory_Enh.v_OpenOrderLineLevel AS
SELECT T1.OrderID, T1.ItemSequenceNum, T1.Customer, T1.ShipToCode,
    UPPER(RTRIM(CASE WHEN T1.ShipToCode IS NULL OR TRIM(T1.ShipToCode)='' THEN TRIM(T1.Customer) ELSE CONCAT(TRIM(T1.Customer),'-',TRIM(T1.ShipToCode)) END)) AS AccountShipTo,
    T1.ItemSKU, T1.WarehouseCode,
    CAST(T1.QtyOrdered-T1.QtyShipped AS INT) AS QtyOpenOrder,
    CAST(T1.QtyBackordered AS INT) AS QtyBackorder,
    CAST((T1.AmtExtendedSelling/CASE WHEN T1.QtyBackordered>0 THEN T1.QtyBackordered WHEN T1.QtyOrdered>0 THEN T1.QtyOrdered ELSE 1 END - COALESCE(T2.AmtFreight,0))
        *CASE WHEN T1.QtyBackordered>0 THEN T1.QtyBackordered WHEN T1.QtyOrdered>0 THEN T1.QtyOrdered ELSE 1 END AS DECIMAL(13,2)) AS AmtOpenOrder,
    CAST(CASE WHEN T1.QtyBackordered>0 THEN (T1.AmtExtendedSelling/T1.QtyBackordered-COALESCE(T2.AmtFreight,0))*T1.QtyBackordered ELSE 0 END AS DECIMAL(13,2)) AS AmtBackorder,
    T3.OrderDate AS OrderTaken, T2.PromiseDate AS OriginalPromise, T1.RequestedDate AS CurrentPromise,
    T4.FreezeDate AS OriginalRequest, T4.RequestedShipDate AS CurrentRequest, T1.ManufacturedDate AS CurrentLoad,
    T4.OrderArrangementCode AS OrderArrivalCode, T1.AllocationFlagCode, T1.LoadDateChanges AS LoadDateChangesNum,
    T3.LeadTimeDays AS LeadTimeDaysNum, T3.ShippingInstructionsName,
    CASE WHEN T1.ItemDescriptionShortName=T1.ItemDescriptionName THEN '' ELSE T1.ItemDescriptionShortName END AS CustomerSKUName,
    COALESCE(T2.AmtFreight,0) AS AmtOrderFreight,
    CASE WHEN DATEADD(DAY,7,T4.RequestedShipDate)<CAST(GETDATE() AS DATE) THEN 'Past Due' ELSE 'Future Ord' END AS PastDueFlagCode
FROM Staging_Wrk.v_Codatan AS T1
LEFT JOIN Staging_Wrk.v_Extorit AS T2 ON T1.OrderID=T2.OrderID AND T1.ItemSequenceNum=T2.ItemSequenceNum
INNER JOIN Staging_Wrk.v_Comast AS T3 ON T1.OrderID=T3.OrderID
INNER JOIN Staging_Wrk.v_Extord AS T4 ON T1.OrderID=T4.OrderID
WHERE (T1.QtyBackordered<>0 OR T1.QtyOrdered<>0) AND T1.AmtSellingPrice<>0 AND T3.RecordTypeCode<>'X' AND T1.QtyOrdered>=0

GO

-- ---- OpenOrderHistory_Enh.v_OpenOrderMonthly ----

CREATE VIEW OpenOrderHistory_Enh.v_OpenOrderMonthly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode) AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder) AS QtyOpenOrder, SUM(OO.QtyBackorder) AS QtyBackorder,
    SUM(OO.AmtOpenOrder) AS AmtOpenOrder, SUM(OO.AmtBackorder) AS AmtBackorder,
    COUNT(*) AS OrderLines, COUNT(DISTINCT OO.OrderID) AS DistinctOrders,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.QtyOpenOrder ELSE 0 END) AS QtyPastDue,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.AmtOpenOrder ELSE 0 END) AS AmtPastDue
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=OO.CurrentRequest
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode), CAL.FSCMonthFirst, CAL.FSCMonthLast

GO

-- ---- ReferenceMaster_Enh.v_Calendar ----
CREATE   VIEW ReferenceMaster_Enh.v_Calendar AS
SELECT
    -- Keys (existing)
    CAST(DateKey AS INT)                          AS SKDate,
    CAST(MapicsDate AS INT)                       AS MapicsDate,
    CAST(DateID AS DATE)                          AS Date,
    CAST(DateTimeID AS DATE)                      AS Datetime,
    CAST(CalendarDate AS DATE)                    AS Calendar,

    -- Calendar Day (existing + 1 NEW)
    TRIM(CalendarDateName)                        AS CalendarDateName,
    CAST(CalendarDateIndicator AS INT)            AS CalDateIndicatorNum,        -- NEW
    CAST(CalendarDayOfWeek AS INT)                AS CalDayOfWeekNum,
    TRIM(CalendarDayOfWeekName)                   AS CalDayOfWeekName,
    CAST(CalendarDayOfMonth AS INT)               AS CalDayOfMonthNum,
    CAST(CalendarDayOfYear AS INT)                AS CalDayOfYearNum,

    -- Calendar Week (existing + 2 NEW)
    CAST(CalendarWeek AS INT)                     AS CalWeekNum,
    CAST(CalendarWeekIndicator AS INT)            AS CalWeekIndicatorNum,        -- NEW
    CAST(CalendarWeekYear AS INT)                 AS CalWeekYearNum,
    TRIM(CalendarWeekYearName)                    AS CalWeekYearName,
    CAST(CalendarWeekFirstDate AS DATE)           AS CalWeekFirst,
    CAST(CalendarWeekLastDate AS DATE)            AS CalWeekLast,
    CAST(CalendarWeekOfMonth AS INT)              AS CalWeekOfMonthNum,          -- NEW

    -- Calendar Month (existing + 1 NEW)
    CAST(CalendarMonth AS INT)                    AS CalMonthNum,
    CAST(CalendarMonthIndicator AS INT)           AS CalMonthIndicatorNum,       -- NEW
    CAST(CalendarMonthYear AS INT)                AS CalMonthYearNum,
    TRIM(CalendarMonthName)                       AS CalMonthName,
    TRIM(CalendarMonthYearName)                   AS CalMonthYearName,
    CAST(CalendarMonthFirstDate AS DATE)          AS CalMonthFirst,
    CAST(CalendarMonthLastDate AS DATE)           AS CalMonthLast,

    -- Calendar Quarter (existing + 3 NEW)
    CAST(CalendarQuarter AS INT)                  AS CalQuarterNum,
    TRIM(CalendarQuarterName)                     AS CalQuarterName,
    CAST(CalendarQuarterIndicator AS INT)         AS CalQuarterIndicatorNum,     -- NEW
    CAST(CalendarQuarterYear AS INT)              AS CalQuarterYearNum,          -- NEW
    TRIM(CalendarQuarterYearName)                 AS CalQuarterYearName,         -- NEW

    -- Calendar Semester + Year (3 NEW)
    CAST(CalendarSemester AS INT)                 AS CalSemesterNum,             -- NEW
    CAST(CalendarSemesterYear AS INT)             AS CalSemesterYearNum,         -- NEW
    CAST(CalendarYear AS INT)                     AS CalYearNum,
    TRIM(CalendarYearName)                        AS CalYearName,
    CAST(CalendarYearIndicator AS INT)            AS CalYearIndicatorNum,        -- NEW

    -- Fiscal Day (7 NEW)
    CAST(FiscalDate AS DATE)                      AS FiscalDate,                 -- NEW
    TRIM(FiscalDateName)                          AS FiscalDateName,             -- NEW
    CAST(FiscalDateIndicator AS INT)              AS FSCDateIndicatorNum,        -- NEW
    CAST(FiscalDayOfWeek AS INT)                  AS FSCDayOfWeekNum,            -- NEW
    TRIM(FiscalDayOfWeekName)                     AS FSCDayOfWeekName,           -- NEW
    CAST(FiscalDayOfMonth AS INT)                 AS FSCDayOfMonthNum,           -- NEW
    CAST(FiscalDayOfYear AS INT)                  AS FSCDayOfYearNum,            -- NEW

    -- Fiscal Week (existing + 3 NEW)
    CAST(FiscalWeek AS INT)                       AS FSCWeekNum,
    CAST(FiscalWeekIndicator AS INT)              AS FSCWeekIndicatorNum,        -- NEW
    CAST(FiscalWeekYear AS INT)                   AS FSCWeekYearNum,
    TRIM(FiscalWeekYearName)                      AS FSCWeekYearName,            -- NEW
    CAST(FiscalWeekFirstDate AS DATE)             AS FSCWeekFirst,
    CAST(FiscalWeekLastDate AS DATE)              AS FSCWeekLast,
    CAST(FiscalWeekOfMonth AS INT)                AS FSCWeekOfMonthNum,          -- NEW

    -- Fiscal Month (existing + 1 NEW)
    CAST(FiscalMonth AS INT)                      AS FSCMonthNum,
    CAST(FiscalMonthIndicator AS INT)             AS FSCMonthIndicatorNum,       -- NEW
    CAST(FiscalMonthYear AS INT)                  AS FSCMonthYearNum,
    TRIM(FiscalMonthName)                         AS FSCMonthName,
    TRIM(FiscalMonthYearName)                     AS FSCMonthYearName,
    CAST(FiscalMonthFirstDate AS DATE)            AS FSCMonthFirst,
    CAST(FiscalMonthLastDate AS DATE)             AS FSCMonthLast,

    -- Fiscal Quarter (existing + 3 NEW: indicator + first/last via window function)
    CAST(FiscalQuarter AS INT)                    AS FSCQuarterNum,
    TRIM(FiscalQuarterName)                       AS FSCQuarterName,
    CAST(FiscalQuarterIndicator AS INT)           AS FSCQuarterIndicatorNum,     -- NEW
    CAST(FiscalQuarterYear AS INT)                AS FSCQuarterYearNum,
    TRIM(FiscalQuarterYearName)                   AS FSCQuarterYearName,
    MIN(CAST(FiscalMonthFirstDate AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterFirst,            -- NEW
    MAX(CAST(FiscalMonthLastDate  AS DATE)) OVER (PARTITION BY FiscalYear, FiscalQuarter)
                                                  AS FSCQuarterLast,             -- NEW

    -- Fiscal Semester + Year (5 NEW)
    CAST(FiscalSemester AS INT)                   AS FSCSemesterNum,             -- NEW
    CAST(FiscalSemesterYear AS INT)               AS FSCSemesterYearNum,         -- NEW
    CAST(FiscalYear AS INT)                       AS FSCYearNum,
    TRIM(FiscalYearName)                          AS FSCYearName,
    CAST(FiscalYearIndicator AS INT)              AS FSCYearIndicatorNum,        -- NEW
    CAST(FiscalYearFirstDate AS DATE)             AS FSCYearFirst,               -- NEW
    CAST(FiscalYearLastDate AS DATE)              AS FSCYearLast,                -- NEW

    -- Holiday + Working Day (existing)
    TRIM(HolidayIndicator)                        AS HolidayIndicatorCode,
    TRIM(HolidayName)                             AS HolidayName,
    TRIM(WorkingDayIndicator)                     AS WorkingDayCode,
    TRIM(WeekdayWeekend)                          AS WeekdayWeekendCode

FROM Enterprise_Lakehouse.MasterData_DW.DimDate
WHERE DateKey IS NOT NULL;

GO

-- ---- ReferenceMaster_Enh.v_CustomerAccount ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerAccount AS
SELECT
    CAST(TRIM(src.[cmaCustomerNumber]) AS VARCHAR(8000)) AS [cmaCustomerNumber],
    CAST(TRIM(src.[cmaPhone]) AS VARCHAR(8000)) AS [cmaPhone],
    CAST(TRIM(src.[cmaFaxtn]) AS VARCHAR(8000)) AS [cmaFaxtn],
    CAST(TRIM(src.[cmaContact]) AS VARCHAR(8000)) AS [cmaContact],
    CAST(TRIM(src.[cmaEmail]) AS VARCHAR(8000)) AS [cmaEmail],
    CAST(TRIM(src.[cmaPrimaryTerritory]) AS VARCHAR(8000)) AS [cmaPrimaryTerritory],
    CAST(TRIM(src.[cmaMinimumFreightCode]) AS VARCHAR(8000)) AS [cmaMinimumFreightCode],
    CAST(src.[cmaCreditLimitAmount] AS INT) AS [cmaCreditLimitAmount],
    CAST(TRIM(src.[cmaTermsCode]) AS VARCHAR(8000)) AS [cmaTermsCode],
    CAST(src.[cmaTermsDays] AS SMALLINT) AS [cmaTermsDays],
    CAST(src.[cmaCreditTerritoryID] AS SMALLINT) AS [cmaCreditTerritoryID],
    CAST(src.[cmaCancelBackOrders] AS SMALLINT) AS [cmaCancelBackOrders],
    CAST(src.[cmaAllowPartialShipment] AS SMALLINT) AS [cmaAllowPartialShipment],
    CAST(TRIM(src.[cmaCustomerClassCode]) AS VARCHAR(8000)) AS [cmaCustomerClassCode],
    CAST(TRIM(src.[cmaLanguageCode]) AS VARCHAR(8000)) AS [cmaLanguageCode],
    CAST(src.[cmaStatementCode] AS SMALLINT) AS [cmaStatementCode],
    CAST(TRIM(src.[cmaItemCrossReferenceCode]) AS VARCHAR(8000)) AS [cmaItemCrossReferenceCode],
    CAST(src.[cmaTerritoryChangeDate] AS DATETIME2(6)) AS [cmaTerritoryChangeDate],
    CAST(TRIM(src.[cmaCreditAuthorizationCode]) AS VARCHAR(8000)) AS [cmaCreditAuthorizationCode],
    CAST(TRIM(src.[cmaMemo]) AS VARCHAR(8000)) AS [cmaMemo],
    CAST(src.[cmaChgCustAr] AS BIT) AS [cmaChgCustAr],
    CAST(src.[cmaChgCust] AS BIT) AS [cmaChgCust],
    CAST(src.[cmaChgCustExt] AS BIT) AS [cmaChgCustExt],
    CAST(src.[cmaPercentAvailableCredit] AS DECIMAL(3,2)) AS [cmaPercentAvailableCredit],
    CAST(src.[cmaCommAudit] AS BIT) AS [cmaCommAudit],
    CAST(src.[cmaInheritBlocking] AS BIT) AS [cmaInheritBlocking],
    CAST(TRIM(src.[cmaCustomerName]) AS VARCHAR(8000)) AS [cmaCustomerName],
    CAST(TRIM(src.[usra]) AS VARCHAR(8000)) AS [usra],
    CAST(src.[dtea] AS DATETIME2(6)) AS [dtea],
    CAST(TRIM(src.[usrc]) AS VARCHAR(8000)) AS [usrc],
    CAST(src.[dtec] AS DATETIME2(6)) AS [dtec],
    CAST(TRIM(src.[acrec]) AS VARCHAR(8000)) AS [acrec],
    CAST(src.[cmaLastStatusChangeDate] AS DATETIME2(6)) AS [cmaLastStatusChangeDate],
    CAST(src.[cmaBillingAddressID] AS INT) AS [cmaBillingAddressID],
    CAST(TRIM(src.[cmaDBAName]) AS VARCHAR(8000)) AS [cmaDBAName],
    CAST(src.[cmaLateChargePercent] AS DECIMAL(5,4)) AS [cmaLateChargePercent],
    CAST(src.[cmaMinPreapprovalAmount] AS DECIMAL(12,2)) AS [cmaMinPreapprovalAmount],
    CAST(TRIM(src.[cmaCreditAddessCode]) AS VARCHAR(8000)) AS [cmaCreditAddessCode],
    CAST(TRIM(src.[cmaRFCTaxIdNumber]) AS VARCHAR(8000)) AS [cmaRFCTaxIdNumber],
    CAST(TRIM(src.[cmaDocumentationHold]) AS VARCHAR(8000)) AS [cmaDocumentationHold],
    CAST(TRIM(src.[cmaPARSByPurchaser]) AS VARCHAR(8000)) AS [cmaPARSByPurchaser],
    CAST(TRIM(src.[cma10DigitScheduleB]) AS VARCHAR(8000)) AS [cma10DigitScheduleB],
    CAST(TRIM(src.[cmaTypeOfInsurance]) AS VARCHAR(8000)) AS [cmaTypeOfInsurance],
    CAST(src.[cmaInsExpirationDate] AS DATETIME2(6)) AS [cmaInsExpirationDate],
    CAST(src.[cmaInsCoverageRequested] AS DECIMAL(10,2)) AS [cmaInsCoverageRequested],
    CAST(src.[cmaInsCoverageApproved] AS DECIMAL(10,2)) AS [cmaInsCoverageApproved],
    CAST(TRIM(src.[cmaInsuranceStatus]) AS VARCHAR(8000)) AS [cmaInsuranceStatus],
    CAST(TRIM(src.[cmaHomestoreFacingWhse]) AS VARCHAR(8000)) AS [cmaHomestoreFacingWhse],
    CAST(src.[cmaAppcd] AS INT) AS [cmaAppcd],
    CAST(src.[cmaDeductTerritoryID] AS DECIMAL(2,0)) AS [cmaDeductTerritoryID],
    CAST(TRIM(src.[cmaCurrencyCode]) AS VARCHAR(8000)) AS [cmaCurrencyCode],
    CAST(src.[cmaAllowAllowanceCredits] AS BIT) AS [cmaAllowAllowanceCredits],
    CAST(TRIM(src.[cmaCustomerChannelID]) AS VARCHAR(8000)) AS [cmaCustomerChannelID]
FROM [Enterprise_Lakehouse].[Customers].[AccountMaster] AS src

GO

-- ---- ReferenceMaster_Enh.v_CustomerAccountGroup ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerAccountGroup AS
SELECT TRIM(CustomerNumber) AS Customer, UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode,
    TRIM(CustomerGroupLevel3) AS CustomerGroupLevel3Code, TRIM(BusinessTypeCode) AS BusinessTypeCode
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping

GO

-- ---- ReferenceMaster_Enh.v_CustomerGrouping ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerGrouping AS
SELECT DISTINCT UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode, TRIM(CustomerNumber) AS Customer
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping WHERE CustomerGroup IS NOT NULL

GO

-- ---- ReferenceMaster_Enh.v_CustomerShippingLocation ----
CREATE VIEW ReferenceMaster_Enh.v_CustomerShippingLocation AS
SELECT
    CAST(src.[commAudit] AS BIT) AS [commAudit],
    CAST(src.[commAudit2] AS BIT) AS [commAudit2],
    CAST(TRIM(src.[cslCustomerNumber]) AS VARCHAR(8000)) AS [cslCustomerNumber],
    CAST(TRIM(src.[cslShiptoNumber]) AS VARCHAR(8000)) AS [cslShiptoNumber],
    CAST(src.[cslMapicsSequenceNumber] AS SMALLINT) AS [cslMapicsSequenceNumber],
    CAST(TRIM(src.[cslName]) AS VARCHAR(8000)) AS [cslName],
    CAST(TRIM(src.[csmShpa1]) AS VARCHAR(8000)) AS [csmShpa1],
    CAST(TRIM(src.[csmShpa2]) AS VARCHAR(8000)) AS [csmShpa2],
    CAST(TRIM(src.[csmShpa3]) AS VARCHAR(8000)) AS [csmShpa3],
    CAST(TRIM(src.[csmShpzp]) AS VARCHAR(8000)) AS [csmShpzp],
    CAST(TRIM(src.[csmShpst]) AS VARCHAR(8000)) AS [csmShpst],
    CAST(TRIM(src.[csmShpco]) AS VARCHAR(8000)) AS [csmShpco],
    CAST(TRIM(src.[csmPhone]) AS VARCHAR(8000)) AS [csmPhone],
    CAST(TRIM(src.[csmFaxTn]) AS VARCHAR(8000)) AS [csmFaxTn],
    CAST(TRIM(src.[cslTaxExempt]) AS VARCHAR(8000)) AS [cslTaxExempt],
    CAST(TRIM(src.[csmWebsite]) AS VARCHAR(8000)) AS [csmWebsite],
    CAST(TRIM(src.[csmEmail]) AS VARCHAR(8000)) AS [csmEmail],
    CAST(TRIM(src.[cslCommissionCode]) AS VARCHAR(8000)) AS [cslCommissionCode],
    CAST(TRIM(src.[cslFreightCode]) AS VARCHAR(8000)) AS [cslFreightCode],
    CAST(TRIM(src.[cslPriceCode]) AS VARCHAR(8000)) AS [cslPriceCode],
    CAST(TRIM(src.[cslDiscountCode]) AS VARCHAR(8000)) AS [cslDiscountCode],
    CAST(src.[cslCommissionSplit] AS DECIMAL(7,4)) AS [cslCommissionSplit],
    CAST(TRIM(src.[cslDefaultWarehouse]) AS VARCHAR(8000)) AS [cslDefaultWarehouse],
    CAST(TRIM(src.[cslShippingTerritory]) AS VARCHAR(8000)) AS [cslShippingTerritory],
    CAST(TRIM(src.[cslBusinessType]) AS VARCHAR(8000)) AS [cslBusinessType],
    CAST(TRIM(src.[cslShipType]) AS VARCHAR(8000)) AS [cslShipType],
    CAST(TRIM(src.[cslTranscomPrimaryID]) AS VARCHAR(8000)) AS [cslTranscomPrimaryID],
    CAST(TRIM(src.[csmContact]) AS VARCHAR(8000)) AS [csmContact],
    CAST(TRIM(src.[cslComment1]) AS VARCHAR(8000)) AS [cslComment1],
    CAST(TRIM(src.[cslComment2]) AS VARCHAR(8000)) AS [cslComment2],
    CAST(src.[cslTerritoryEffectivityDate] AS DATETIME2(6)) AS [cslTerritoryEffectivityDate],
    CAST(TRIM(src.[cslCrmID]) AS VARCHAR(8000)) AS [cslCrmID],
    CAST(TRIM(src.[csmCsPhone]) AS VARCHAR(8000)) AS [csmCsPhone],
    CAST(TRIM(src.[csmcsFax]) AS VARCHAR(8000)) AS [csmcsFax],
    CAST(TRIM(src.[csmcsContact]) AS VARCHAR(8000)) AS [csmcsContact],
    CAST(TRIM(src.[csmcsEmail]) AS VARCHAR(8000)) AS [csmcsEmail],
    CAST(TRIM(src.[cslMemo]) AS VARCHAR(8000)) AS [cslMemo],
    CAST(TRIM(src.[csmMsa_Fips]) AS VARCHAR(8000)) AS [csmMsa_Fips],
    CAST(src.[csmRMCityNumber] AS INT) AS [csmRMCityNumber],
    CAST(TRIM(src.[cslTranscomAlternateID]) AS VARCHAR(8000)) AS [cslTranscomAlternateID],
    CAST(TRIM(src.[csmDirections]) AS VARCHAR(8000)) AS [csmDirections],
    CAST(TRIM(src.[csmCrossStreet]) AS VARCHAR(8000)) AS [csmCrossStreet],
    CAST(src.[csmChgAddr] AS BIT) AS [csmChgAddr],
    CAST(src.[csmChgShip] AS BIT) AS [csmChgShip],
    CAST(src.[csmChgShipExt] AS BIT) AS [csmChgShipExt],
    CAST(src.[csmChgCust] AS BIT) AS [csmChgCust],
    CAST(TRIM(src.[usra]) AS VARCHAR(8000)) AS [usra],
    CAST(src.[dtea] AS DATETIME2(6)) AS [dtea],
    CAST(TRIM(src.[usrc]) AS VARCHAR(8000)) AS [usrc],
    CAST(src.[dtec] AS DATETIME2(6)) AS [dtec],
    CAST(TRIM(src.[acrec]) AS VARCHAR(8000)) AS [acrec],
    CAST(TRIM(src.[csmCounty]) AS VARCHAR(8000)) AS [csmCounty],
    CAST(src.[cslBlockRepOrderEntry] AS BIT) AS [cslBlockRepOrderEntry],
    CAST(src.[cslCustomerSegment] AS SMALLINT) AS [cslCustomerSegment],
    CAST(src.[cslLastStatusChangeDate] AS DATETIME2(6)) AS [cslLastStatusChangeDate],
    CAST(src.[cslBuyerAddressID] AS INT) AS [cslBuyerAddressID],
    CAST(src.[cslPartyLocationID] AS INT) AS [cslPartyLocationID],
    CAST(src.[cslRouteAddressID] AS INT) AS [cslRouteAddressID],
    CAST(TRIM(src.[cslDefaultOrderType1]) AS VARCHAR(8000)) AS [cslDefaultOrderType1],
    CAST(TRIM(src.[cslDefaultOrderType2]) AS VARCHAR(8000)) AS [cslDefaultOrderType2],
    CAST(TRIM(src.[cslDefaultOrderType3]) AS VARCHAR(8000)) AS [cslDefaultOrderType3],
    CAST(TRIM(src.[cslDefaultOrderType4]) AS VARCHAR(8000)) AS [cslDefaultOrderType4],
    CAST(src.[csmShled] AS SMALLINT) AS [csmShled],
    CAST(src.[csmAppcd] AS INT) AS [csmAppcd],
    CAST(TRIM(src.[cslAllowFax]) AS VARCHAR(8000)) AS [cslAllowFax],
    CAST(TRIM(src.[cslDirectConsumer]) AS VARCHAR(8000)) AS [cslDirectConsumer],
    CAST(TRIM(src.[cslDeliveryUnitOfMeasure]) AS VARCHAR(8000)) AS [cslDeliveryUnitOfMeasure],
    CAST(src.[cslDeliveryUnitOfMeasureFence] AS DECIMAL(7,2)) AS [cslDeliveryUnitOfMeasureFence],
    CAST(TRIM(src.[cslExportsLCLConsolidationFlag]) AS VARCHAR(8000)) AS [cslExportsLCLConsolidationFlag],
    CAST(TRIM(src.[cslExportsDocumentCountry]) AS VARCHAR(8000)) AS [cslExportsDocumentCountry],
    CAST(TRIM(src.[cslExportsProductOnPallets]) AS VARCHAR(8000)) AS [cslExportsProductOnPallets],
    CAST(TRIM(src.[cslExportsAppointmentsRequired]) AS VARCHAR(8000)) AS [cslExportsAppointmentsRequired],
    CAST(src.[cslHasDock] AS BIT) AS [cslHasDock],
    CAST(TRIM(src.[cslHasDockUserDate]) AS VARCHAR(8000)) AS [cslHasDockUserDate],
    CAST(TRIM(src.[cslExpressShippingMethod]) AS VARCHAR(8000)) AS [cslExpressShippingMethod],
    CAST(TRIM(src.[cslDirectIncludeShipto]) AS VARCHAR(8000)) AS [cslDirectIncludeShipto],
    CAST(src.[cslExpressHandlingCharge] AS DECIMAL(4,3)) AS [cslExpressHandlingCharge],
    CAST(src.[cslExpressMinimum] AS DECIMAL(10,2)) AS [cslExpressMinimum],
    CAST(src.[cslExpressMaximum] AS DECIMAL(10,2)) AS [cslExpressMaximum],
    CAST(TRIM(src.[cslDefaultLanguage]) AS VARCHAR(8000)) AS [cslDefaultLanguage],
    CAST(TRIM(src.[cslExpressServiceContractNumber]) AS VARCHAR(8000)) AS [cslExpressServiceContractNumber],
    CAST(TRIM(src.[cslUseNegotiatedFreightRate]) AS VARCHAR(8000)) AS [cslUseNegotiatedFreightRate],
    CAST(TRIM(src.[cslUseStandardFreightRate]) AS VARCHAR(8000)) AS [cslUseStandardFreightRate],
    CAST(TRIM(src.[cslDoNotRepriceOrders]) AS VARCHAR(8000)) AS [cslDoNotRepriceOrders],
    CAST(TRIM(src.[cslPricingUseOfflineFiles]) AS VARCHAR(8000)) AS [cslPricingUseOfflineFiles],
    CAST(src.[cslReturnAddressID] AS INT) AS [cslReturnAddressID],
    CAST(TRIM(src.[cslReturnAddressName]) AS VARCHAR(8000)) AS [cslReturnAddressName]
FROM [Enterprise_Lakehouse].[Customers].[ShippingLocations] AS src

GO

-- ---- ReferenceMaster_Enh.v_ForecastCycle ----
CREATE VIEW ReferenceMaster_Enh.v_ForecastCycle AS
SELECT
    CAST(TRIM(src.[code_cycle]) AS VARCHAR(8000)) AS [CycleName],
    CAST(TRIM(src.[name_cycle_description]) AS VARCHAR(8000)) AS [CycleDescription],
    CAST(src.[dt_cycle_month_last] AS DATE) AS [CycleMonthLastDate],
    CAST(src.[dt_forecast_snapshot] AS DATE) AS [ForecastSnapshot],
    CAST(TRIM(src.[name_exception_note]) AS VARCHAR(8000)) AS [ExceptionNote],
    CAST(src.[ts_modified] AS DATETIME2(6)) AS [Modified],
    CAST(src.[ts_created] AS DATETIME2(6)) AS [Created]
FROM ProcessingSeed.ForecastCycle AS src

GO

-- ---- ReferenceMaster_Enh.v_ForecastHorizon ----

CREATE   VIEW ReferenceMaster_Enh.v_ForecastHorizon AS
SELECT
    CAST(TRIM(src.HorizonCode) AS VARCHAR(20)) AS HorizonCode,
    CAST(src.[Rank] AS INT) AS [Rank]
FROM ProcessingSeed.ForecastHorizon AS src

GO

-- ---- ReferenceMaster_Enh.v_ItemMaster ----
CREATE VIEW ReferenceMaster_Enh.v_ItemMaster AS
SELECT
    CAST(src.[RowID] AS BIGINT) AS [RowID],
    CAST(TRIM(src.[ItemSKU]) AS VARCHAR(8000)) AS [ItemSKU],
    CAST(TRIM(src.[ItemKey]) AS VARCHAR(8000)) AS [ItemKey],
    CAST(TRIM(src.[Item]) AS VARCHAR(8000)) AS [Item],
    CAST(TRIM(src.[ItemCode]) AS VARCHAR(8000)) AS [ItemCode],
    CAST(TRIM(src.[SeriesNumber]) AS VARCHAR(8000)) AS [SeriesNumber],
    CAST(TRIM(src.[ExtSeriesNumber]) AS VARCHAR(8000)) AS [ExtSeriesNumber],
    CAST(TRIM(src.[FrameNumber]) AS VARCHAR(8000)) AS [FrameNumber],
    CAST(src.[QtyInBox] AS DECIMAL(4,0)) AS [QtyInBox],
    CAST(TRIM(src.[UOM]) AS VARCHAR(8000)) AS [UOM],
    CAST(src.[ProductHeightMeters] AS DECIMAL(7,2)) AS [ProductHeightMeters],
    CAST(src.[ProductWidthMeters] AS DECIMAL(7,2)) AS [ProductWidthMeters],
    CAST(src.[ProductDepthMeters] AS DECIMAL(7,2)) AS [ProductDepthMeters],
    CAST(src.[CartonHeightMeters] AS DECIMAL(7,2)) AS [CartonHeightMeters],
    CAST(src.[CartonWidthMeters] AS DECIMAL(7,2)) AS [CartonWidthMeters],
    CAST(src.[CartonDepthMeters] AS DECIMAL(7,2)) AS [CartonDepthMeters],
    CAST(src.[ProductHeightInches] AS DECIMAL(7,2)) AS [ProductHeightInches],
    CAST(src.[ProductWidthInches] AS DECIMAL(7,2)) AS [ProductWidthInches],
    CAST(src.[ProductDepthInches] AS DECIMAL(7,2)) AS [ProductDepthInches],
    CAST(src.[CartonHeightInches] AS DECIMAL(7,2)) AS [CartonHeightInches],
    CAST(src.[CartonWidthInches] AS DECIMAL(7,2)) AS [CartonWidthInches],
    CAST(src.[CartonDepthInches] AS DECIMAL(7,2)) AS [CartonDepthInches],
    CAST(src.[Cubes] AS DECIMAL(5,2)) AS [Cubes],
    CAST(src.[Seats] AS DECIMAL(5,2)) AS [Seats],
    CAST(TRIM(src.[ItemDescription]) AS VARCHAR(8000)) AS [ItemDescription],
    CAST(TRIM(src.[SeriesName]) AS VARCHAR(8000)) AS [SeriesName],
    CAST(TRIM(src.[SeriesColor]) AS VARCHAR(8000)) AS [SeriesColor],
    CAST(TRIM(src.[Colors]) AS VARCHAR(8000)) AS [Colors],
    CAST(TRIM(src.[ItemDescriptionSeries]) AS VARCHAR(8000)) AS [ItemDescriptionSeries],
    CAST(TRIM(src.[SHItemDescriptionSeries]) AS VARCHAR(8000)) AS [SHItemDescriptionSeries],
    CAST(TRIM(src.[SHSeriesDescription]) AS VARCHAR(8000)) AS [SHSeriesDescription],
    CAST(TRIM(src.[ItemDescriptionSeriesItemColor]) AS VARCHAR(8000)) AS [ItemDescriptionSeriesItemColor],
    CAST(TRIM(src.[ChildStyleDescription]) AS VARCHAR(8000)) AS [ChildStyleDescription],
    CAST(TRIM(src.[ParentStyleDescription]) AS VARCHAR(8000)) AS [ParentStyleDescription],
    CAST(TRIM(src.[SeriesDescription]) AS VARCHAR(8000)) AS [SeriesDescription],
    CAST(TRIM(src.[ItemName]) AS VARCHAR(8000)) AS [ItemName],
    CAST(TRIM(src.[ItemConsumerDescription]) AS VARCHAR(8000)) AS [ItemConsumerDescription],
    CAST(TRIM(src.[RetailTypeDescription]) AS VARCHAR(8000)) AS [RetailTypeDescription],
    CAST(TRIM(src.[MainPieceItem]) AS VARCHAR(8000)) AS [MainPieceItem],
    CAST(TRIM(src.[ItemClass]) AS VARCHAR(8000)) AS [ItemClass],
    CAST(TRIM(src.[ItemClassCode]) AS VARCHAR(8000)) AS [ItemClassCode],
    CAST(TRIM(src.[ItemClassName]) AS VARCHAR(8000)) AS [ItemClassName],
    CAST(TRIM(src.[ProductLine]) AS VARCHAR(8000)) AS [ProductLine],
    CAST(TRIM(src.[RetailCategoryCode]) AS VARCHAR(8000)) AS [RetailCategoryCode],
    CAST(TRIM(src.[RetailCategoryDescription]) AS VARCHAR(8000)) AS [RetailCategoryDescription],
    CAST(TRIM(src.[RetailCategoryName]) AS VARCHAR(8000)) AS [RetailCategoryName],
    CAST(TRIM(src.[RetailDepartmentName]) AS VARCHAR(8000)) AS [RetailDepartmentName],
    CAST(TRIM(src.[RetailCategoryGroup]) AS VARCHAR(8000)) AS [RetailCategoryGroup],
    CAST(TRIM(src.[RetailCategoryChargeType]) AS VARCHAR(8000)) AS [RetailCategoryChargeType],
    CAST(TRIM(src.[AFIFinanceDivision]) AS VARCHAR(8000)) AS [AFIFinanceDivision],
    CAST(TRIM(src.[AFIFinanceDivisionCode]) AS VARCHAR(8000)) AS [AFIFinanceDivisionCode],
    CAST(TRIM(src.[AFISalesCategoryCode]) AS VARCHAR(8000)) AS [AFISalesCategoryCode],
    CAST(TRIM(src.[AFISalesCategory]) AS VARCHAR(8000)) AS [AFISalesCategory],
    CAST(TRIM(src.[ItemStyleCode]) AS VARCHAR(8000)) AS [ItemStyleCode],
    CAST(TRIM(src.[ItemStyleGroup]) AS VARCHAR(8000)) AS [ItemStyleGroup],
    CAST(TRIM(src.[ItemStyle]) AS VARCHAR(8000)) AS [ItemStyle],
    CAST(TRIM(src.[Division]) AS VARCHAR(8000)) AS [Division],
    CAST(TRIM(src.[AFISalesDivisionCode]) AS VARCHAR(8000)) AS [AFISalesDivisionCode],
    CAST(TRIM(src.[AFISalesDivision]) AS VARCHAR(8000)) AS [AFISalesDivision],
    CAST(src.[KeyItem] AS BIT) AS [KeyItem],
    CAST(TRIM(src.[ItemType]) AS VARCHAR(8000)) AS [ItemType],
    CAST(TRIM(src.[SalesClassCode]) AS VARCHAR(8000)) AS [SalesClassCode],
    CAST(TRIM(src.[SalesClassDescription]) AS VARCHAR(8000)) AS [SalesClassDescription],
    CAST(TRIM(src.[SalesClass]) AS VARCHAR(8000)) AS [SalesClass],
    CAST(TRIM(src.[DiscountClassCode]) AS VARCHAR(8000)) AS [DiscountClassCode],
    CAST(TRIM(src.[DiscountClassDescription]) AS VARCHAR(8000)) AS [DiscountClassDescription],
    CAST(TRIM(src.[DiscountClass]) AS VARCHAR(8000)) AS [DiscountClass],
    CAST(TRIM(src.[CommissionClassCode]) AS VARCHAR(8000)) AS [CommissionClassCode],
    CAST(TRIM(src.[CommissionClassDescription]) AS VARCHAR(8000)) AS [CommissionClassDescription],
    CAST(TRIM(src.[CommissionClass]) AS VARCHAR(8000)) AS [CommissionClass],
    CAST(TRIM(src.[FreightClassCode]) AS VARCHAR(8000)) AS [FreightClassCode],
    CAST(TRIM(src.[FreightClassDescription]) AS VARCHAR(8000)) AS [FreightClassDescription],
    CAST(TRIM(src.[FreightClass]) AS VARCHAR(8000)) AS [FreightClass],
    CAST(TRIM(src.[AFIItemStatus]) AS VARCHAR(8000)) AS [AFIItemStatus],
    CAST(TRIM(src.[SellableItemFlag]) AS VARCHAR(8000)) AS [SellableItemFlag],
    CAST(TRIM(src.[ManufacturingStatus]) AS VARCHAR(8000)) AS [ManufacturingStatus],
    CAST(TRIM(src.[ResponsibleOffice]) AS VARCHAR(8000)) AS [ResponsibleOffice],
    CAST(TRIM(src.[ResponsibleOfficeName]) AS VARCHAR(8000)) AS [ResponsibleOfficeName],
    CAST(TRIM(src.[ImportDomesticCode]) AS VARCHAR(8000)) AS [ImportDomesticCode],
    CAST(TRIM(src.[CountryofOrigin]) AS VARCHAR(8000)) AS [CountryofOrigin],
    CAST(TRIM(src.[PrimaryVendor]) AS VARCHAR(8000)) AS [PrimaryVendor],
    CAST(src.[ManufacturingStatusChangeDate] AS DATE) AS [ManufacturingStatusChangeDate],
    CAST(TRIM(src.[ItemForecastPlannerID]) AS VARCHAR(8000)) AS [ItemForecastPlannerID],
    CAST(src.[NewItemFlag] AS BIT) AS [NewItemFlag],
    CAST(src.[DiscontinuedFlag] AS BIT) AS [DiscontinuedFlag],
    CAST(TRIM(src.[DiscontinuedYearPeriod]) AS VARCHAR(8000)) AS [DiscontinuedYearPeriod],
    CAST(TRIM(src.[CommonCarrierFlag]) AS VARCHAR(8000)) AS [CommonCarrierFlag],
    CAST(TRIM(src.[ExpressShipFlag]) AS VARCHAR(8000)) AS [ExpressShipFlag],
    CAST(src.[DiscontinuedDate] AS DATE) AS [DiscontinuedDate],
    CAST(src.[SeriesDateArchived] AS DATE) AS [SeriesDateArchived],
    CAST(src.[SeriesDiscontinuedFlag] AS BIT) AS [SeriesDiscontinuedFlag],
    CAST(TRIM(src.[PreviousStatusCode]) AS VARCHAR(8000)) AS [PreviousStatusCode],
    CAST(src.[StatusCodeChangeDate] AS DATE) AS [StatusCodeChangeDate],
    CAST(src.[CurrentUnitCost] AS DECIMAL(19,8)) AS [CurrentUnitCost],
    CAST(TRIM(src.[CEXCode]) AS VARCHAR(8000)) AS [CEXCode],
    CAST(TRIM(src.[MarketIntroducedAt]) AS VARCHAR(8000)) AS [MarketIntroducedAt],
    CAST(src.[MerchandisingCategory] AS SMALLINT) AS [MerchandisingCategory],
    CAST(src.[PricePoint] AS INT) AS [PricePoint],
    CAST(TRIM(src.[ItemGrouping]) AS VARCHAR(8000)) AS [ItemGrouping],
    CAST(src.[SeriesGrouping] AS SMALLINT) AS [SeriesGrouping],
    CAST(TRIM(src.[MasterGroupCode]) AS VARCHAR(8000)) AS [MasterGroupCode],
    CAST(TRIM(src.[AssociationCode]) AS VARCHAR(8000)) AS [AssociationCode],
    CAST(TRIM(src.[MarketingItemStatus]) AS VARCHAR(8000)) AS [MarketingItemStatus],
    CAST(TRIM(src.[MarketingStatusDescription]) AS VARCHAR(8000)) AS [MarketingStatusDescription],
    CAST(TRIM(src.[Lifestyle]) AS VARCHAR(8000)) AS [Lifestyle],
    CAST(src.[CommodityItem] AS BIT) AS [CommodityItem],
    CAST(src.[F123ProductFlag] AS BIT) AS [F123ProductFlag],
    CAST(src.[HSCoreProductFlag] AS BIT) AS [HSCoreProductFlag],
    CAST(src.[HSProprietaryProductFlag] AS BIT) AS [HSProprietaryProductFlag],
    CAST(src.[HSExclusiveFlag] AS BIT) AS [HSExclusiveFlag],
    CAST(src.[BerklineProductFlag] AS BIT) AS [BerklineProductFlag],
    CAST(src.[BenchcraftProductFlag] AS BIT) AS [BenchcraftProductFlag],
    CAST(src.[NewMillenniumProductFlag] AS BIT) AS [NewMillenniumProductFlag],
    CAST(src.[BardiniProductFlag] AS BIT) AS [BardiniProductFlag],
    CAST(src.[ShanghaiStore] AS BIT) AS [ShanghaiStore],
    CAST(src.[DefaultGroup] AS BIT) AS [DefaultGroup],
    CAST(TRIM(src.[GoodBetterBestForPricePoint]) AS VARCHAR(8000)) AS [GoodBetterBestForPricePoint],
    CAST(src.[GBBSortId] AS INT) AS [GBBSortId],
    CAST(TRIM(src.[InitialInvoicePeriod]) AS VARCHAR(8000)) AS [InitialInvoicePeriod],
    CAST(src.[InitialInvoiceQty] AS DECIMAL(38,0)) AS [InitialInvoiceQty],
    CAST(src.[MarketBeginDate] AS DATE) AS [MarketBeginDate],
    CAST(src.[MarketEndDate] AS DATE) AS [MarketEndDate],
    CAST(TRIM(src.[Showroom]) AS VARCHAR(8000)) AS [Showroom],
    CAST(TRIM(src.[ItemImage]) AS VARCHAR(8000)) AS [ItemImage],
    CAST(src.[FOBArcPrice] AS DECIMAL(8,2)) AS [FOBArcPrice],
    CAST(src.[DivisionRanking] AS INT) AS [DivisionRanking],
    CAST(TRIM(src.[TrendArrow]) AS VARCHAR(8000)) AS [TrendArrow],
    CAST(TRIM(src.[ItemMerchGridOverridePhoto]) AS VARCHAR(8000)) AS [ItemMerchGridOverridePhoto],
    CAST(src.[GroupPriceIncr] AS DECIMAL(5,0)) AS [GroupPriceIncr],
    CAST(TRIM(src.[GroupPricePointType]) AS VARCHAR(8000)) AS [GroupPricePointType],
    CAST(TRIM(src.[ExclusiveComment]) AS VARCHAR(8000)) AS [ExclusiveComment],
    CAST(TRIM(src.[SeriesImage]) AS VARCHAR(8000)) AS [SeriesImage],
    CAST(TRIM(src.[SofaTableSeriesFlag]) AS VARCHAR(8000)) AS [SofaTableSeriesFlag],
    CAST(TRIM(src.[ReclinerSeriesFlag]) AS VARCHAR(8000)) AS [ReclinerSeriesFlag],
    CAST(TRIM(src.[PowerMotionSeriesFlag]) AS VARCHAR(8000)) AS [PowerMotionSeriesFlag],
    CAST(TRIM(src.[WedgeSeriesFlag]) AS VARCHAR(8000)) AS [WedgeSeriesFlag],
    CAST(TRIM(src.[DiningSeriesFlag]) AS VARCHAR(8000)) AS [DiningSeriesFlag],
    CAST(TRIM(src.[ItemThirdPartyItem]) AS VARCHAR(8000)) AS [ItemThirdPartyItem],
    CAST(TRIM(src.[SeriesThirdParty]) AS VARCHAR(8000)) AS [SeriesThirdParty],
    CAST(TRIM(src.[ItemHomeStoreProductLine]) AS VARCHAR(8000)) AS [ItemHomeStoreProductLine],
    CAST(TRIM(src.[ItemEcomMerchantNotes]) AS VARCHAR(8000)) AS [ItemEcomMerchantNotes],
    CAST(TRIM(src.[ItemAmazonBrandOwner]) AS VARCHAR(8000)) AS [ItemAmazonBrandOwner],
    CAST(TRIM(src.[ItemSupplierDirectShipOnly]) AS VARCHAR(8000)) AS [ItemSupplierDirectShipOnly],
    CAST(TRIM(src.[ConsumerChoiceFlag]) AS VARCHAR(8000)) AS [ConsumerChoiceFlag],
    CAST(TRIM(src.[EligibleForProtectionPlan]) AS VARCHAR(8000)) AS [EligibleForProtectionPlan],
    CAST(TRIM(src.[IsProtectionPlan]) AS VARCHAR(8000)) AS [IsProtectionPlan],
    CAST(TRIM(src.[CollectiveClass]) AS VARCHAR(8000)) AS [CollectiveClass],
    CAST(TRIM(src.[FriendlyDimensions]) AS VARCHAR(8000)) AS [FriendlyDimensions],
    CAST(TRIM(src.[Knockout]) AS VARCHAR(8000)) AS [Knockout],
    CAST(TRIM(src.[Scene7ImageSet]) AS VARCHAR(8000)) AS [Scene7ImageSet],
    CAST(TRIM(src.[FluffAFI]) AS VARCHAR(8000)) AS [FluffAFI],
    CAST(TRIM(src.[SeriesPrimary]) AS VARCHAR(8000)) AS [SeriesPrimary],
    CAST(TRIM(src.[SeriesMainImage]) AS VARCHAR(8000)) AS [SeriesMainImage],
    CAST(TRIM(src.[StandAloneFlag]) AS VARCHAR(8000)) AS [StandAloneFlag],
    CAST(TRIM(src.[SuppWeightNetWeightLbs]) AS VARCHAR(8000)) AS [SuppWeightNetWeightLbs],
    CAST(TRIM(src.[UnitWeightLbs]) AS VARCHAR(8000)) AS [UnitWeightLbs],
    CAST(TRIM(src.[UPC]) AS VARCHAR(8000)) AS [UPC],
    CAST(TRIM(src.[RetailBrandName]) AS VARCHAR(8000)) AS [RetailBrandName],
    CAST(TRIM(src.[MfgWarranty]) AS VARCHAR(8000)) AS [MfgWarranty],
    CAST(TRIM(src.[Material]) AS VARCHAR(8000)) AS [Material],
    CAST(TRIM(src.[SeriesFeatures]) AS VARCHAR(8000)) AS [SeriesFeatures],
    CAST(TRIM(src.[ItemIsRTA]) AS VARCHAR(8000)) AS [ItemIsRTA],
    CAST(TRIM(src.[PrimaryChannelSku]) AS VARCHAR(8000)) AS [PrimaryChannelSku],
    CAST(TRIM(src.[PrimarySeriesName]) AS VARCHAR(8000)) AS [PrimarySeriesName],
    CAST(TRIM(src.[PrimarySeriesNumber]) AS VARCHAR(8000)) AS [PrimarySeriesNumber],
    CAST(TRIM(src.[ERetailChannelSku]) AS VARCHAR(8000)) AS [ERetailChannelSku],
    CAST(TRIM(src.[ERetailSeriesName]) AS VARCHAR(8000)) AS [ERetailSeriesName],
    CAST(TRIM(src.[ERetailSeriesNumber]) AS VARCHAR(8000)) AS [ERetailSeriesNumber],
    CAST(TRIM(src.[ItemTableShapeType]) AS VARCHAR(8000)) AS [ItemTableShapeType],
    CAST(TRIM(src.[ItemBedSizeType]) AS VARCHAR(8000)) AS [ItemBedSizeType],
    CAST(TRIM(src.[ItemBedStyleType]) AS VARCHAR(8000)) AS [ItemBedStyleType],
    CAST(TRIM(src.[ItemGeneralColor]) AS VARCHAR(8000)) AS [ItemGeneralColor],
    CAST(TRIM(src.[ItemPricePointRating]) AS VARCHAR(8000)) AS [ItemPricePointRating]
FROM [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] AS src

GO

-- ---- ReferenceMaster_Enh.v_OrderType ----
CREATE VIEW ReferenceMaster_Enh.v_OrderType AS
SELECT
    CAST(TRIM(src.[OTCODE]) AS VARCHAR(8000)) AS [OTCODE],
    CAST(TRIM(src.[OTDES1]) AS VARCHAR(8000)) AS [OTDES1],
    CAST(TRIM(src.[OTDES2]) AS VARCHAR(8000)) AS [OTDES2],
    CAST(TRIM(src.[OTUSER]) AS VARCHAR(8000)) AS [OTUSER],
    CAST(src.[OTDATE] AS DECIMAL(8,0)) AS [OTDATE],
    CAST(TRIM(src.[OORDCL]) AS VARCHAR(8000)) AS [OORDCL],
    CAST(TRIM(src.[OROUTE]) AS VARCHAR(8000)) AS [OROUTE],
    CAST(TRIM(src.[OOTCAT]) AS VARCHAR(8000)) AS [OOTCAT],
    CAST(TRIM(src.[OADCHG]) AS VARCHAR(8000)) AS [OADCHG],
    CAST(TRIM(src.[OARFLG]) AS VARCHAR(8000)) AS [OARFLG],
    CAST(TRIM(src.[OWNEXP]) AS VARCHAR(8000)) AS [OWNEXP],
    CAST(TRIM(src.[OMINEXC]) AS VARCHAR(8000)) AS [OMINEXC],
    CAST(TRIM(src.[OREQMNT]) AS VARCHAR(8000)) AS [OREQMNT],
    CAST(TRIM(src.[OFDESCH]) AS VARCHAR(8000)) AS [OFDESCH],
    CAST(TRIM(src.[OFDRIMS]) AS VARCHAR(8000)) AS [OFDRIMS],
    CAST(TRIM(src.[OTRPTYP]) AS VARCHAR(8000)) AS [OTRPTYP],
    CAST(TRIM(src.[OZNLTIM]) AS VARCHAR(8000)) AS [OZNLTIM],
    CAST(TRIM(src.[OSPECHND]) AS VARCHAR(8000)) AS [OSPECHND],
    CAST(TRIM(src.[OAUTORSCH]) AS VARCHAR(8000)) AS [OAUTORSCH],
    CAST(TRIM(src.[OUSRDFN]) AS VARCHAR(8000)) AS [OUSRDFN]
FROM [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AAORDTYP] AS src

GO

-- ---- ReferenceMaster_Enh.v_Product ----
CREATE VIEW ReferenceMaster_Enh.v_Product AS SELECT * FROM Staging_Wrk.ProductEdw

GO

-- ---- ReferenceMaster_Enh.v_Warehouse ----
-- 2026-05-28 SOURCE FIX: EL.SupplyChain_DW.DimAFIWarehouses no longer resolves in SQL endpoint.
-- Repoint to EL.CustomerOrders_AFI.WarehouseMaster, preserving the ReferenceMaster_Enh.Warehouse contract.
-- 2026-05-29 REPORT FIX: new source WarehouseType is only D/W; keep WarehouseLocation
-- as the report display label expected by Forecast visuals.
-- 2026-05-25 FIX: WarehouseCode stored padded with trailing spaces.
-- Power BI Vertipaq exact-match → relationship JOIN fails when downstream Fact has trimmed key.
-- Add RTRIM at Silver source to propagate clean to Gold (DimWarehouse + Fact*).
CREATE VIEW ReferenceMaster_Enh.v_Warehouse AS
SELECT
    CAST(LocationID AS INT) AS AFIWarehousesKey,
    CAST(RTRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode,
    CAST(RTRIM(IntransitWarehouse) AS VARCHAR(50)) AS IntransitWarehouse,
    CAST(RTRIM(ContainerDirectWhse) AS VARCHAR(50)) AS ContainerDirectWarehouse,
    CAST(CASE WHEN Controlled = 1 THEN 1 ELSE 0 END AS INT) AS ControlledWarehouse,
    CAST(COALESCE(NULLIF(RTRIM(WarehouseOrderGroup), ''), NULLIF(RTRIM(Warehouse), '')) AS VARCHAR(100)) AS WarehouseLocation,
    CAST(RTRIM(WarehouseOrderGroup) AS VARCHAR(100)) AS WarehouseOrderGroup,
    CAST(CASE WHEN ActiveRecord = 'A' THEN 1 ELSE 0 END AS INT) AS FinanceInventoryReportFlag
FROM Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
WHERE NULLIF(TRIM(Warehouse), '') IS NOT NULL

GO

-- ---- SalesHistory_Enh.v_ActualDemandMonthly ----
CREATE VIEW SalesHistory_Enh.v_ActualDemandMonthly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCMonthFirst, CAL.FSCMonthLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCMonthFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCMonthFirst, CAL.FSCMonthLast

GO

-- ---- SalesHistory_Enh.v_ActualDemandWeekly ----
CREATE VIEW SalesHistory_Enh.v_ActualDemandWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast

GO

-- ---- SalesHistory_Enh.v_InvoiceDetailLineLevel ----
CREATE VIEW SalesHistory_Enh.v_InvoiceDetailLineLevel AS
-- 2026-06-22 SOURCE FIX: switch from legacy source to SalesHistory_AFI_Enh
SELECT INV.InvoiceID, INV.InvoiceExtended, INV.OrderID, INV.ItemSequenceNum,
    INV.Customer, INV.ShipToCode,
    UPPER(RTRIM(CASE WHEN INV.ShipToCode IS NULL OR TRIM(INV.ShipToCode)='' THEN TRIM(INV.Customer) ELSE CONCAT(TRIM(INV.Customer),'-',TRIM(INV.ShipToCode)) END)) AS AccountShipTo,
    INV.ItemSKU, INV.WarehouseCode,
    UPPER(CG.CustomerGroupCode) AS CustomerGroupCode, IH.LeadTimeDaysNum,
    INV.QtyShipped, INV.QtyOrdered, INV.QtyBackordered,
    INV.AmtInvoice, INV.AmtNetSales, INV.AmtPrice, INV.AmtStandardPrice,
    INV.AmtContractPrice, INV.AmtDiscount, INV.AmtPriceAdjustment, INV.AmtFreight,
    INV.InvoiceDate, INV.OrderDate, INV.Request, INV.CurrentRequest,
    INV.CurrentPromise, INV.OriginalRequest, INV.OriginalPromise,
    INV.PromisedDelivery, INV.Delivery, INV.ActualDelivery,
    INV.OrderTypeCode, INV.OrderType3Code, INV.CreditCode, INV.ItemClassCode, INV.OrderItemStatusCode
FROM Enterprise_Lakehouse.SalesHistory_AFI_Enh.InvoiceDetail AS INV
LEFT JOIN Enterprise_Lakehouse.SalesHistory_AFI_Enh.InvoiceHeader AS IH ON INV.InvoiceID=IH.InvoiceID AND INV.InvoiceDate=IH.InvoiceDate AND INV.OrderDate=IH.OrderDate AND INV.OrderID=IH.OrderID
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup AS CG ON CG.Customer=INV.Customer

GO

-- ---- SalesHistory_Enh.v_InvoiceWeekly ----
CREATE VIEW SalesHistory_Enh.v_InvoiceWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyShipped, SUM(INV.AmtNetSales) AS AmtNetSales,
    SUM(INV.AmtInvoice) AS AmtInvoice, SUM(INV.AmtFreight) AS AmtFreight,
    COUNT(*) AS InvoiceLines, COUNT(DISTINCT INV.InvoiceID) AS DistinctInvoices
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=INV.InvoiceDate
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum>=cf.FSCYearNum-3
GROUP BY INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode, CAL.FSCWeekFirst, CAL.FSCWeekLast

GO
