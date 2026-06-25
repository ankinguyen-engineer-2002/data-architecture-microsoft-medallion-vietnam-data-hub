CREATE VIEW SalesHistory_ENH.vw_ActualDemandWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_ENH.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_ENH.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_ENH.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_ENH.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_ENH.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_ENH.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast