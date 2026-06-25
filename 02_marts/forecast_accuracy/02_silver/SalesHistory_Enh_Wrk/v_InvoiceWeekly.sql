-- SupplyChain_Processing_Warehouse.SalesHistory_Enh_Wrk.v_InvoiceWeekly
CREATE   VIEW [SalesHistory_Enh_Wrk].[v_InvoiceWeekly] AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE)),
__bob_source AS (
SELECT INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyShipped, SUM(INV.AmtNetSales) AS AmtNetSales,
    SUM(INV.AmtInvoice) AS AmtInvoice, SUM(INV.AmtFreight) AS AmtFreight,
    COUNT(*) AS InvoiceLines, COUNT(DISTINCT INV.InvoiceID) AS DistinctInvoices
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=INV.InvoiceDate
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum>=cf.FSCYearNum-3
GROUP BY INV.AccountShipTo, INV.ItemSKU, INV.WarehouseCode, INV.CustomerGroupCode, CAL.FSCWeekFirst, CAL.FSCWeekLast
)
SELECT
    [AccountShipTo] = src.[AccountShipTo],
    [ItemSKU] = src.[ItemSKU],
    [WarehouseCode] = src.[WarehouseCode],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [FSCWeekFirst] = src.[FSCWeekFirst],
    [FSCWeekLast] = src.[FSCWeekLast],
    [QtyShipped] = src.[QtyShipped],
    [AmtNetSales] = src.[AmtNetSales],
    [AmtInvoice] = src.[AmtInvoice],
    [AmtFreight] = src.[AmtFreight],
    [InvoiceLines] = src.[InvoiceLines],
    [DistinctInvoices] = src.[DistinctInvoices],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
