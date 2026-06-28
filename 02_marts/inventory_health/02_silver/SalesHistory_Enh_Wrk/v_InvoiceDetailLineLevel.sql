-- SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel
CREATE   VIEW [SalesHistory_Enh_Wrk].[v_InvoiceDetailLineLevel]
AS
WITH INV AS
(
    SELECT
        InvoiceNumber,
        ExtendedInvoiceNumber,
        OrderNumber,
        ItemSequence,
        CustomerNumber,
        ShiptoNumber,
        ItemSKU,
        Warehouse,
        SUM(QuantityShipped)      AS QtyShipped,
        SUM(QuantityOrdered)      AS QtyOrdered,
        SUM(QuantityBackOrdered)  AS QtyBackordered,
        SUM(InvoiceAmount)        AS AmtInvoice,
        SUM(NetSales)             AS AmtNetSales,
        SUM(Price)                AS AmtPrice,
        SUM(StandardPrice)        AS AmtStandardPrice,
        SUM(ContractPrice)        AS AmtContractPrice,
        SUM(Discount)             AS AmtDiscount,
        SUM(PriceAdjustment)      AS AmtPriceAdjustment,
        SUM(Freight)              AS AmtFreight,
        InvoiceDate,
        OrderDate,
        RequestDate,
        CurrentRequestDate,
        CurrentPromiseDate,
        OriginalRequestDate,
        OriginalPromiseDate,
        PromisedDelivery,
        DeliveryDate,
        ActualDelivery,
        OrderType,
        OrderType3,
        CreditCode,
        ItemClass,
        OrderItemStatus
    FROM Enterprise_Lakehouse.SalesHistory_AFI_Enh.InvoiceDetail
    GROUP BY
        InvoiceNumber,
        ExtendedInvoiceNumber,
        OrderNumber,
        ItemSequence,
        CustomerNumber,
        ShiptoNumber,
        ItemSKU,
        Warehouse,
        InvoiceDate,
        OrderDate,
        RequestDate,
        CurrentRequestDate,
        CurrentPromiseDate,
        OriginalRequestDate,
        OriginalPromiseDate,
        PromisedDelivery,
        DeliveryDate,
        ActualDelivery,
        OrderType,
        OrderType3,
        CreditCode,
        ItemClass,
        OrderItemStatus
),
IH AS
(
    SELECT
        InvoiceNumber,
        InvoiceDate,
        OrderDate,
        OrderNumber,
        MAX(LeadTime) AS LeadTime
    FROM Enterprise_Lakehouse.SalesHistory_AFI_Enh.InvoiceHeader
    GROUP BY
        InvoiceNumber,
        InvoiceDate,
        OrderDate,
        OrderNumber
),
CG AS
(
    SELECT
        Customer,
        MAX(CustomerGroupCode) AS CustomerGroupCode
    FROM ReferenceMaster_Enh.CustomerAccountGroup
    GROUP BY Customer
)
SELECT
    INV.InvoiceNumber                                 AS InvoiceID,
    INV.ExtendedInvoiceNumber                         AS InvoiceExtended,
    INV.OrderNumber                                   AS OrderID,
    INV.ItemSequence                                  AS ItemSequenceNum,
    INV.CustomerNumber                                AS Customer,
    INV.ShiptoNumber                                  AS ShipToCode,
    UPPER(RTRIM(
        CASE
            WHEN INV.ShiptoNumber IS NULL
                 OR TRIM(INV.ShiptoNumber) = ''
            THEN TRIM(INV.CustomerNumber)
            ELSE CONCAT(TRIM(INV.CustomerNumber), '-', TRIM(INV.ShiptoNumber))
        END
    ))                                                AS AccountShipTo,
    INV.ItemSKU,
    INV.Warehouse                                     AS WarehouseCode,
    UPPER(CG.CustomerGroupCode)                       AS CustomerGroupCode,
    IH.LeadTime                                       AS LeadTimeDaysNum,
    INV.QtyShipped,
    INV.QtyOrdered,
    INV.QtyBackordered,
    INV.AmtInvoice,
    INV.AmtNetSales,
    INV.AmtPrice,
    INV.AmtStandardPrice,
    INV.AmtContractPrice,
    INV.AmtDiscount,
    INV.AmtPriceAdjustment,
    INV.AmtFreight,
    INV.InvoiceDate,
    INV.OrderDate,
    INV.RequestDate                                   AS Request,
    INV.CurrentRequestDate                            AS CurrentRequest,
    INV.CurrentPromiseDate                            AS CurrentPromise,
    INV.OriginalRequestDate                           AS OriginalRequest,
    INV.OriginalPromiseDate                           AS OriginalPromise,
    INV.PromisedDelivery,
    INV.DeliveryDate                                  AS Delivery,
    INV.ActualDelivery,
    INV.OrderType                                     AS OrderTypeCode,
    INV.OrderType3                                    AS OrderType3Code,
    INV.CreditCode,
    INV.ItemClass                                     AS ItemClassCode,
    INV.OrderItemStatus                               AS OrderItemStatusCode,
    CAST(SYSUTCDATETIME() AS datetime2(6))            AS LoadDT
FROM INV
LEFT JOIN IH
    ON INV.InvoiceNumber = IH.InvoiceNumber
   AND INV.InvoiceDate = IH.InvoiceDate
   AND INV.OrderDate = IH.OrderDate
   AND INV.OrderNumber = IH.OrderNumber
LEFT JOIN CG
    ON CG.Customer = INV.CustomerNumber;
