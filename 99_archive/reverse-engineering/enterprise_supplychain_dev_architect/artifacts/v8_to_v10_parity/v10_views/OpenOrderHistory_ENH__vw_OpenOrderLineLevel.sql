CREATE VIEW OpenOrderHistory_ENH.vw_OpenOrderLineLevel AS
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
FROM Staging_WRK.vw_Codatan AS T1
LEFT JOIN Staging_WRK.vw_Extorit AS T2 ON T1.OrderID=T2.OrderID AND T1.ItemSequenceNum=T2.ItemSequenceNum
INNER JOIN Staging_WRK.vw_Comast AS T3 ON T1.OrderID=T3.OrderID
INNER JOIN Staging_WRK.vw_Extord AS T4 ON T1.OrderID=T4.OrderID
WHERE (T1.QtyBackordered<>0 OR T1.QtyOrdered<>0) AND T1.AmtSellingPrice<>0 AND T3.RecordTypeCode<>'X' AND T1.QtyOrdered>=0