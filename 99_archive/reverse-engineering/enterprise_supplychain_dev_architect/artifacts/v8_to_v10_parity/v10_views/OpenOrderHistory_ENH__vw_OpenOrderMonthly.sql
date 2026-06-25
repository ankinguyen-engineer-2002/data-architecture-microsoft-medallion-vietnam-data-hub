
CREATE VIEW OpenOrderHistory_ENH.vw_OpenOrderMonthly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_ENH.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode) AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder) AS QtyOpenOrder, SUM(OO.QtyBackorder) AS QtyBackorder,
    SUM(OO.AmtOpenOrder) AS AmtOpenOrder, SUM(OO.AmtBackorder) AS AmtBackorder,
    COUNT(*) AS OrderLines, COUNT(DISTINCT OO.OrderID) AS DistinctOrders,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.QtyOpenOrder ELSE 0 END) AS QtyPastDue,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.AmtOpenOrder ELSE 0 END) AS AmtPastDue
FROM OpenOrderHistory_ENH.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_ENH.Calendar CAL ON CAL.Date=OO.CurrentRequest
LEFT JOIN ReferenceMaster_ENH.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode), CAL.FSCMonthFirst, CAL.FSCMonthLast
