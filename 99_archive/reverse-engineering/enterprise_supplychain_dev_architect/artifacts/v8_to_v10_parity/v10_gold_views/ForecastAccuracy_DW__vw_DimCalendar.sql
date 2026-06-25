CREATE VIEW ForecastAccuracy_DW.vw_DimCalendar AS
SELECT DISTINCT
    CAL.FSCMonthFirst AS DateSK,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    CAL.FSCMonthName, CAL.FSCMonthYearName,
    CAL.FSCQuarterName, CAL.FSCQuarterYearName,
    CAL.FSCYearNum, CAL.FSCYearName,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.Calendar CAL
WHERE CAL.FSCMonthFirst IS NOT NULL