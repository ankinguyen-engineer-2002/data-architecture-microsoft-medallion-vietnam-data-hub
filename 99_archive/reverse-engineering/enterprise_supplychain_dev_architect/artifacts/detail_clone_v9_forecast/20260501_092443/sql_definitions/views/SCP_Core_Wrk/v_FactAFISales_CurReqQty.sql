-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactAFISales_CurReqQty
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

 CREATE             VIEW [SCP_Core_Wrk].[v_FactAFISales_CurReqQty] AS (

 SELECT RTRIM([DC].[Account And ShipTo Number]) AS [AccountAndShipToNumber]
      ,RTRIM([ID].[ItemSKU]) AS [ItemSKU]
      ,RTRIM([ID].[Warehouse]) AS [Warehouse]
      ,[DD].[Fiscal Week End] AS [CurReqWkEnd]
      ,SUM([ID].[QuantityShipped]) AS [OrderQty]
      ,SUM([ID].[NetSales]) AS [OrderAmt]
			,'Invoiced' AS [OrderStatus]
FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail] AS ID 
LEFT JOIN [SupplyChain_Warehouse].[SCP_Core].[DimCustomerMaster] AS DC
  on [ID].[CustomerNumber] = [DC].[Account Number]
    AND [ID].[ShiptoNumber] = [DC].[ShipTo Number]
INNER JOIN [SupplyChain_Warehouse].[SCP_Core].[DimFiscalCalendar] AS DD
  ON [ID].[CurrentRequestDate] = [DD].[Transaction Date]

WHERE [ID].[QuantityShipped] > 0



GROUP BY [DC].[Account And ShipTo Number]
        ,[ID].[ItemSKU]
        ,[ID].[Warehouse]
        ,[DD].[Fiscal Week End]

UNION

SELECT RTRIM([OO].[Account And ShipTo Number]) AS [AccountAndShipToNumber]
      ,RTRIM([OO].[ItemSKU]) AS [ItemSKU]
      ,RTRIM([OO].[Warehouse]) AS [Warehouse]
      ,[DD].[Fiscal Week End] AS [CurReqWkEnd]
      ,SUM([OO].[OpenOrderQty]) AS [OrderQty]
      ,SUM([OO].[OpenOrderAmt]) AS [OrderAmt]
			,'Open' AS [OrderStatus]
FROM [SupplyChain_Warehouse].[SCP_Core].[FactOpenOrders] AS OO 

INNER JOIN [SupplyChain_Warehouse].[SCP_Core].[DimFiscalCalendar] AS DD
  ON [OO].[CurrentRequestDate] = [DD].[Transaction Date]

WHERE [OO].[InventoryAllocatedFlag] = '2'


GROUP BY [OO].[Account And ShipTo Number]
        ,[OO].[ItemSKU]
        ,[OO].[Warehouse]
        ,[DD].[Fiscal Week End]

)
