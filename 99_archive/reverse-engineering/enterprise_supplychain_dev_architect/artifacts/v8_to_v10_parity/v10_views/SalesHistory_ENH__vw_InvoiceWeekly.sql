CREATE VIEW SalesHistory_ENH.vw_InvoiceWeekly AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_ENH.Calendar WHERE Date=CAST(GETDATE() AS DATE))
SELECT INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyShipped, SUM(INV.AmtNetSales) AS AmtNetSales,
    SUM(INV.AmtInvoice) AS AmtInvoice, SUM(INV.AmtFreight) AS AmtFreight,
    COUNT(*) AS InvoiceLines, COUNT(DISTINCT INV.InvoiceID) AS DistinctInvoices
FROM SalesHistory_ENH.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_ENH.Calendar CAL ON CAL.Date=INV.InvoiceDate
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum>=cf.FSCYearNum-3
GROUP BY INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode, CAL.FSCWeekFirst, CAL.FSCWeekLast