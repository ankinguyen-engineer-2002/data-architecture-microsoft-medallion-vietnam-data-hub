-- SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel
CREATE   VIEW [SalesHistory_Enh_Wrk].[v_InvoiceDetailLineLevel]
AS
WITH INV_Ranked AS
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
        OrderItemStatus,
        ROW_NUMBER() OVER
        (
            PARTITION BY InvoiceNumber, OrderNumber, ItemSKU, ItemSequence
            ORDER BY (SELECT NULL)
        ) AS _rn
    FROM Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail
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
INV_Dedup AS
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
        OrderItemStatus,
        QtyShipped,
        QtyOrdered,
        QtyBackordered,
        AmtInvoice,
        AmtNetSales,
        AmtPrice,
        AmtStandardPrice,
        AmtContractPrice,
        AmtDiscount,
        AmtPriceAdjustment,
        AmtFreight
    FROM INV_Ranked
    WHERE _rn = 1
),
IH_Dedup AS
(
    SELECT
        InvoiceNumber,
        InvoiceDate,
        OrderDate,
        OrderNumber,
        MAX(LeadTime) AS LeadTime
    FROM Enterprise_Lakehouse.SalesHistory_AFI.InvoiceHeader
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
    INV_Dedup.InvoiceNumber                           AS InvoiceID,
    INV_Dedup.ExtendedInvoiceNumber                   AS InvoiceExtended,
    INV_Dedup.OrderNumber                             AS OrderID,
    INV_Dedup.ItemSequence                            AS ItemSequenceNum,
    INV_Dedup.CustomerNumber                          AS Customer,
    INV_Dedup.ShiptoNumber                            AS ShipToCode,
    UPPER(RTRIM(
        CASE
            WHEN INV_Dedup.ShiptoNumber IS NULL
                 OR TRIM(INV_Dedup.ShiptoNumber) = ''
            THEN TRIM(INV_Dedup.CustomerNumber)
            ELSE CONCAT(
                TRIM(INV_Dedup.CustomerNumber),
                '-',
                TRIM(INV_Dedup.ShiptoNumber)
            )
        END
    ))                                                AS AccountShipTo,
    INV_Dedup.ItemSKU,
    INV_Dedup.Warehouse                               AS WarehouseCode,
    UPPER(CG.CustomerGroupCode)                       AS CustomerGroupCode,
    IH_Dedup.LeadTime                                 AS LeadTimeDaysNum,
    INV_Dedup.QtyShipped,
    INV_Dedup.QtyOrdered,
    INV_Dedup.QtyBackordered,
    INV_Dedup.AmtInvoice,
    INV_Dedup.AmtNetSales,
    INV_Dedup.AmtPrice,
    INV_Dedup.AmtStandardPrice,
    INV_Dedup.AmtContractPrice,
    INV_Dedup.AmtDiscount,
    INV_Dedup.AmtPriceAdjustment,
    INV_Dedup.AmtFreight,
    INV_Dedup.InvoiceDate,
    INV_Dedup.OrderDate,
    INV_Dedup.RequestDate                             AS Request,
    INV_Dedup.CurrentRequestDate                      AS CurrentRequest,
    INV_Dedup.CurrentPromiseDate                      AS CurrentPromise,
    INV_Dedup.OriginalRequestDate                     AS OriginalRequest,
    INV_Dedup.OriginalPromiseDate                     AS OriginalPromise,
    INV_Dedup.PromisedDelivery,
    INV_Dedup.DeliveryDate                            AS Delivery,
    INV_Dedup.ActualDelivery,
    INV_Dedup.OrderType                               AS OrderTypeCode,
    INV_Dedup.OrderType3                              AS OrderType3Code,
    INV_Dedup.CreditCode,
    INV_Dedup.ItemClass                               AS ItemClassCode,
    INV_Dedup.OrderItemStatus                         AS OrderItemStatusCode,
    CAST(SYSUTCDATETIME() AS datetime2(6))            AS LoadDT
FROM INV_Dedup
LEFT JOIN IH_Dedup
    ON INV_Dedup.InvoiceNumber = IH_Dedup.InvoiceNumber
   AND INV_Dedup.InvoiceDate = IH_Dedup.InvoiceDate
   AND INV_Dedup.OrderDate = IH_Dedup.OrderDate
   AND INV_Dedup.OrderNumber = IH_Dedup.OrderNumber
LEFT JOIN CG
    ON CG.Customer = INV_Dedup.CustomerNumber;

GO
