CREATE VIEW SalesHistory_ENH.vw_InvoiceDetailLineLevel AS
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
FROM Staging_WRK.InvoiceDetailEdw AS INV
LEFT JOIN Staging_WRK.InvoiceHeaderEdw AS IH ON INV.InvoiceID=IH.InvoiceID AND INV.InvoiceDate=IH.InvoiceDate AND INV.OrderDate=IH.OrderDate AND INV.OrderID=IH.OrderID
LEFT JOIN ReferenceMaster_ENH.CustomerAccountGroup AS CG ON CG.Customer=INV.Customer