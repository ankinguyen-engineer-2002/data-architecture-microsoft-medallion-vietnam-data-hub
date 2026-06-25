-- 04_create_renamed_views_processing.sql
-- 28 Processing views recreated with new schema (_Enh/_Wrk) and v_ prefix.
-- Source: etl/staging_ddl.sql + etl/silver_views.sql, transformed.

-- ============== Staging views ==============
-- ============================================================
-- Staging_Wrk Views — Raw EDW Projection
-- ============================================================
-- Layer: Staging. Pattern: TRIM strings, TRY_CONVERT dates, PascalCase aliases. No JOIN.
-- Source: SupplyChain_Processing_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- Staging_Wrk.v_Codatan ----
CREATE VIEW Staging_Wrk.v_Codatan AS
SELECT
    TRIM(ORDNO) AS OrderID, TRIM(ITNBR) AS ItemSKU, TRIM(HOUSE) AS WarehouseCode,
    CAST(ITMSQ AS INT) AS ItemSequenceNum,
    CAST(COQTY AS DECIMAL(12,3)) AS QtyOrdered, CAST(QTYSH AS DECIMAL(12,3)) AS QtyShipped,
    CAST(QTYBO AS DECIMAL(12,3)) AS QtyBackordered,
    CAST(INSAM AS DECIMAL(12,2)) AS AmtExtendedSelling,
    CAST(PRICE AS DECIMAL(12,4)) AS AmtSellingPrice,
    TRY_CONVERT(DATE, CAST(CAST(RQIDT AS BIGINT) AS VARCHAR(20))) AS RequestedDate,
    TRY_CONVERT(DATE, CAST(CAST(MFIDT AS BIGINT) AS VARCHAR(20))) AS ManufacturedDate,
    TRIM(CCUSNO) AS Customer, TRIM(CSHPNO) AS ShipToCode,
    TRIM(ITDSC) AS ItemDescriptionName, TRIM(ITDSI) AS ItemDescriptionShortName,
    CAST(IAFLG AS VARCHAR(200)) AS AllocationFlagCode,
    CAST(NUMLDDTCHG AS INT) AS LoadDateChanges
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan WHERE ORDNO IS NOT NULL

GO

-- ---- Staging_Wrk.v_Comast ----
CREATE VIEW Staging_Wrk.v_Comast AS
SELECT TRIM(ORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(ORDTE AS BIGINT) AS VARCHAR(20))) AS OrderDate,
    CAST(SHLTC AS INT) AS LeadTimeDays, TRIM(SHINS) AS ShippingInstructionsName,
    TRIM(ACREC) AS RecordTypeCode
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST

GO

-- ---- Staging_Wrk.v_Extord ----
CREATE VIEW Staging_Wrk.v_Extord AS
SELECT TRIM(XORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(FRZDAT AS BIGINT) AS VARCHAR(20))) AS FreezeDate,
    TRY_CONVERT(DATE, CAST(CAST(RQSDAT AS BIGINT) AS VARCHAR(20))) AS RequestedShipDate,
    TRIM(ORDARR) AS OrderArrangementCode,
    TRIM(OTTYP1) AS OrderType1Code, TRIM(OTTYP2) AS OrderType2Code,
    TRIM(OTTYP3) AS OrderType3Code, TRIM(OTTYP4) AS OrderType4Code
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD

GO

-- ---- Staging_Wrk.v_Extorit ----
CREATE VIEW Staging_Wrk.v_Extorit AS
SELECT TRIM(IORD) AS OrderID, CAST(ISEQ AS INT) AS ItemSequenceNum,
    CAST(IFRGHT AS DECIMAL(12,2)) AS AmtFreight,
    TRY_CONVERT(DATE, CAST(CAST(IPRMDT AS BIGINT) AS VARCHAR(20))) AS PromiseDate
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT

GO


-- ============== Silver views ==============
-- ============================================================
-- Silver Views — Domain Business Logic
-- ============================================================
-- Layer: Silver. Pattern: JOIN + UPPER(TRIM(code)) + business derivations + aggregation.
-- Source: SupplyChain_Processing_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- ForecastHistory_Enh.v_ForecastDemandMonthly ----
CREATE VIEW ForecastHistory_Enh.v_ForecastDemandMonthly AS
WITH Raw AS (
    SELECT f.ItemSKU, f.WarehouseCode, UPPER(f.CustomerGroupCode) AS CustomerGroupCode,
        DATEFROMPARTS(CAST(f.FiscalMonth/100 AS INT), CAST(f.FiscalMonth%100 AS INT), 1) AS FiscalMonth,
        CAST(f.SnapshotTS AS DATE) AS Snapshot, f.QtyResultantForecast, f.QtyPromotionalLift
    FROM Staging_Wrk.DemandForecastSnapshotDailyEdw AS f
    INNER JOIN ReferenceMaster_Enh.ForecastCycle AS c ON CAST(f.SnapshotTS AS DATE)=c.ForecastSnapshot
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
CREATE VIEW ReferenceMaster_Enh.v_CustomerAccount AS SELECT * FROM Enterprise_Lakehouse.Customers.AccountMaster

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
CREATE VIEW ReferenceMaster_Enh.v_CustomerShippingLocation AS SELECT * FROM Enterprise_Lakehouse.Customers.ShippingLocations

GO

-- ---- ReferenceMaster_Enh.v_ForecastCycle ----
CREATE VIEW ReferenceMaster_Enh.v_ForecastCycle AS SELECT * FROM SupplyChain_Lakehouse.dbo.ref_forecast_cycle

GO

-- ---- ReferenceMaster_Enh.v_ForecastHorizon ----

CREATE   VIEW ReferenceMaster_Enh.v_ForecastHorizon AS
SELECT 'Lag-0'          AS HorizonCode, 1 AS [Rank] UNION ALL
SELECT 'Lag-1',          2 UNION ALL
SELECT 'Lag-2',          3 UNION ALL
SELECT 'Lag-3',          4 UNION ALL
SELECT 'Lag-4',          5 UNION ALL
SELECT '>Lag-4',         6 UNION ALL
SELECT 'Actual demand',  7 UNION ALL
SELECT 'Naive forecast', 8

GO

-- ---- ReferenceMaster_Enh.v_ItemMaster ----
CREATE VIEW ReferenceMaster_Enh.v_ItemMaster AS SELECT * FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster

GO

-- ---- ReferenceMaster_Enh.v_OrderType ----
CREATE VIEW ReferenceMaster_Enh.v_OrderType AS SELECT * FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP

GO

-- ---- ReferenceMaster_Enh.v_Product ----
CREATE VIEW ReferenceMaster_Enh.v_Product AS SELECT * FROM Staging_Wrk.ProductEdw

GO

-- ---- ReferenceMaster_Enh.v_Warehouse ----
CREATE VIEW ReferenceMaster_Enh.v_Warehouse AS SELECT * FROM Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses

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
FROM Staging_Wrk.InvoiceDetailEdw AS INV
LEFT JOIN Staging_Wrk.InvoiceHeaderEdw AS IH ON INV.InvoiceID=IH.InvoiceID AND INV.InvoiceDate=IH.InvoiceDate AND INV.OrderDate=IH.OrderDate AND INV.OrderID=IH.OrderID
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
