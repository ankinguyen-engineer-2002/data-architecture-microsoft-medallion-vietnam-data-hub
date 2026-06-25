-- SupplyChain_Processing_Warehouse.OpenOrderHistory_Enh_Wrk.v_OpenOrderMonthly
CREATE   VIEW [OpenOrderHistory_Enh_Wrk].[v_OpenOrderMonthly] AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode) AS CustomerGroupCode,
    CAL.FSCMonthFirst, CAL.FSCMonthLast,
    SUM(OO.QtyOpenOrder) AS QtyOpenOrder, SUM(OO.QtyBackorder) AS QtyBackorder,
    SUM(OO.AmtOpenOrder) AS AmtOpenOrder, SUM(OO.AmtBackorder) AS AmtBackorder,
    COUNT(*) AS OrderLines, COUNT(DISTINCT OO.OrderID) AS DistinctOrders,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.QtyOpenOrder ELSE 0 END) AS QtyPastDue,
    SUM(CASE WHEN OO.PastDueFlagCode='Past Due' THEN OO.AmtOpenOrder ELSE 0 END) AS AmtPastDue,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=OO.CurrentRequest
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, UPPER(CG.CustomerGroupCode), CAL.FSCMonthFirst, CAL.FSCMonthLast;
