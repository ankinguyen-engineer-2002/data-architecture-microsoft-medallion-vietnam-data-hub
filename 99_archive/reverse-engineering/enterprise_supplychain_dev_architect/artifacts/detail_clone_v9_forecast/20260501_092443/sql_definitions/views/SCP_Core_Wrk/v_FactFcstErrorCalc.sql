-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactFcstErrorCalc
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE               VIEW [SCP_Core_Wrk].[v_FactFcstErrorCalc] AS (

SELECT [FC].[Customer Group]                                                 AS [CustomerGroup]
      ,[FC].[ItemSKU]
      ,[FC].[Warehouse]
      ,[FC].[FiscalMonthYear]
      ,[FC].[ActualsMonthEnd]                                                AS [FiscalMonthEnd]
      ,[FC].[SortFcstPeriod]
      ,[FC].[FcstPeriod]
      ,[FC].[TotalForecast]
      ,ISNULL([ACT].[ActualDemand], 0)                                       AS [ActualDemand]
      ,[FC].[TotalForecast] - ISNULL([ACT].[ActualDemand], 0)                AS [FcstError]
      ,ABS([FC].[TotalForecast] - ISNULL([ACT].[ActualDemand], 0))           AS [ABS_FcstError]
      ,SQUARE([FC].[TotalForecast] - ISNULL([ACT].[ActualDemand], 0))        AS [SqFcstError]
      ,ISNULL([NF].[NaiveFcst], 0)                                           AS [NaiveFcst]
      ,(ISNULL([NF].[NaiveFcst], 0) - ISNULL([ACT].[ActualDemand], 0))       AS [NaiveFcstError]
      ,ABS(ISNULL([NF].[NaiveFcst], 0) - ISNULL([ACT].[ActualDemand], 0))    AS [ABS_NaiveFcstError]
      ,SQUARE(ISNULL([NF].[NaiveFcst], 0) - ISNULL([ACT].[ActualDemand], 0)) AS [SqNaiveFcstError]
      ,[FC].[SnapshotDate]
      ,[FC].[FcstCycle]
  FROM (
           -- Get all of the Lag forecasts for the last completed month using the FcstAccuracySnapshotDates table
           SELECT [DFC].[dfcItem]                                                AS [ItemSKU]
                 ,[DFC].[dfcWarehouse]                                           AS [Warehouse]
                 ,[DFC].[dfcCustomergroups]                                      AS [Customer Group]
                 ,[DFC].[dfcFiscalMonth]                                         AS [FiscalMonthYear]
                 ,[SD].[ActualsMonthEnd]
                 ,[SD].[SortFcstPeriod]
                 ,[SD].[FcstPeriod]
                 ,SUM([DFC].[dfcResultantForecast] + [DFC].[dfcPromotionalLift]) AS [TotalForecast]
                 ,CONVERT(DATE, [DFC].[dfcSnapshot])                             AS [SnapshotDate]
                 ,[SD].[FcstCycle]
             FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotDaily] AS DFC
                 INNER JOIN [SupplyChain_Warehouse].[SCP_Core].[DimFcstSnapshotDates]      AS SD
                     ON [DFC].[dfcFiscalMonth] = [SD].[ActualsFiscalPeriod]
                    AND [DFC].[dfcSnapshot] = [SD].[FcstSnapshotDate]
            WHERE [DFC].[dfcFiscalMonth] = (
                                               SELECT DISTINCT
                                                      [FiscalMonthYear]
                                                 FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate]
                                                WHERE [FiscalMonthIndicator] = -1
                                           )
            GROUP BY CONVERT(DATE, [DFC].[dfcSnapshot])
                    ,[DFC].[dfcItem]
                    ,[DFC].[dfcWarehouse]
                    ,[DFC].[dfcCustomergroups]
                    ,[DFC].[dfcFiscalMonth]
                    ,[SD].[ActualsMonthEnd]
                    ,[SD].[SortFcstPeriod]
                    ,[SD].[FcstPeriod]
                    ,[SD].[FcstCycle]
       )          AS FC
      LEFT JOIN (
                    -- Get ActualDemand by Customer Group

                    -- This field is Current Request Date minus load lead time from AFISales schemas
                    SELECT [A].[Customer Group]
                          ,[A].[ItemSKU]
                          ,[A].[Warehouse]
                          ,[A].[ActualsMonthEnd]
                          ,SUM([A].[OrderQty]) AS [ActualDemand]
                      FROM (
                               SELECT RTRIM([DC].[Customer Group]) AS [Customer Group]
                                     ,RTRIM([ID].[ItemSKU])        AS [ItemSKU]
                                     ,RTRIM([ID].[Warehouse])      AS [Warehouse]
                                     ,[DD].[Fiscal Month End]      AS [ActualsMonthEnd]
                                     ,SUM([ID].[QuantityShipped])  AS [OrderQty]
                                 FROM [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail]           AS ID
                                     INNER JOIN [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceHeader] AS IH
                                         ON [ID].[InvoiceNumber] = [IH].[InvoiceNumber]
                                        AND [ID].[InvoiceDate] = [IH].[InvoiceDate]
                                        AND [ID].[OrderDate] = [IH].[OrderDate]
                                        AND [ID].[OrderNumber] = [IH].[OrderNumber]

                                     LEFT JOIN [SupplyChain_Warehouse].[SCP_Core].[DimCustomerMaster]     AS DC
                                         ON [ID].[CustomerNumber] = [DC].[Account Number]
                                        AND [ID].[ShiptoNumber] = [DC].[ShipTo Number]

                                     INNER JOIN [SupplyChain_Warehouse].[SCP_Core].[DimFiscalCalendar]    AS DD
                                         ON DATEADD(
                                                       DAY
                                                      ,-[IH].[LeadTime]
                                                      ,[ID].[CurrentRequestDate]
                                                   ) = [DD].[Transaction Date]
                                WHERE [ID].[QuantityShipped] > 0
                                  AND [DD].[Fiscal Month Indicator] = -1
                                GROUP BY RTRIM([DC].[Customer Group])
                                        ,RTRIM([ID].[ItemSKU])
                                        ,RTRIM([ID].[Warehouse])
                                        ,[DD].[Fiscal Month End]
                               UNION
                               SELECT [DC].[Customer Group]    AS [Customer Group]
                                     ,RTRIM([OO].[ItemSKU])    AS [ItemSKU]
                                     ,RTRIM([OO].[Warehouse])  AS [Warehouse]
                                     ,[DD].[Fiscal Month End]  AS [ActualsMonthEnd]
                                     ,SUM([OO].[OpenOrderQty]) AS [OrderQty]
                                 FROM [SupplyChain_Warehouse].[SCP_Core].[FactOpenOrders]              AS OO
                                     INNER JOIN [SupplyChain_Warehouse].[SCP_Core].[DimFiscalCalendar] AS DD
                                         ON DATEADD(
                                                       DAY
                                                      ,-[OO].[LoadLeadTime]
                                                      ,[OO].[CurrentRequestDate]
                                                   ) = [DD].[Transaction Date]

                                     LEFT JOIN [SupplyChain_Warehouse].[SCP_Core].[DimCustomerMaster]  AS DC
                                         ON [OO].[Account And ShipTo Number] = [DC].[Account And ShipTo Number]
                                WHERE [OO].[InventoryAllocatedFlag] = '2'
                                  AND [DD].[Fiscal Month Indicator] = -1
                                GROUP BY [DC].[Customer Group]
                                        ,RTRIM([OO].[ItemSku])
                                        ,RTRIM([OO].[Warehouse])
                                        ,[DD].[Fiscal Month End]
                           ) AS A
                     GROUP BY [A].[Customer Group]
                             ,[A].[ItemSKU]
                             ,[A].[Warehouse]
                             ,[A].[ActualsMonthEnd]
                ) AS ACT
          ON [FC].[Customer Group] = [ACT].[Customer Group]
         AND [FC].[ItemSKU] = [ACT].[ItemSKU]
         AND [FC].[Warehouse] = [ACT].[Warehouse]
         AND [FC].[ActualsMonthEnd] = [ACT].[ActualsMonthEnd]

      LEFT JOIN (
                    -- Get the Naive Forecast
                    -- Preceding months Actuals (controlled for 4-4-5 Fiscal calendar)
                    SELECT [N].[ItemSKU]                            AS [ItemSKU]
                          ,[N].[Warehouse]                          AS [Warehouse]
                          ,[N].[Customer Group]
                          ,[D2].[FiscalMonthYear]
                          ,CAST([N].[Qty] * [D2].[NumWeeks] AS INT) AS [NaiveFcst]
                      FROM (
                               SELECT [ACT].[ItemSKU]
                                     ,[ACT].[Warehouse]
                                     ,[CUS].[Customer Group]
                                     ,[DD].[FiscalMonthIndicator]
                                     ,[D2].[FiscalMonthYear]
                                     ,SUM([ACT].[OrderQty]) / [D2].[NumWeeks] AS [Qty]
                                 FROM [SupplyChain_Warehouse].[SCP_Core].[FactAFISales_CurReqQty]     AS ACT
                                     LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate]       AS DD
                                         ON [ACT].[CurReqWkEnd] = [DD].[DateID]

                                     LEFT JOIN [SupplyChain_Warehouse].[SCP_Core].[DimCustomerMaster] AS CUS
                                         ON [ACT].[AccountAndShipToNumber] = [CUS].[Account And ShipTo Number]

                                     INNER JOIN (
                                                    SELECT [FiscalMonthYear]
                                                          ,[FiscalMonthLastDate]
                                                          ,COUNT(DISTINCT [FiscalWeekLastDate]) AS [NumWeeks]
                                                      FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate]
                                                     WHERE [FiscalMonthIndicator] = -2 -- Pull Two Months ago Actuals
                                                     GROUP BY [FiscalMonthYear]
                                                             ,[FiscalMonthLastDate]
                                                )                                                     AS D2
                                         ON [DD].[FiscalMonthLastDate] = [D2].[FiscalMonthLastDate]
                                WHERE [ACT].[Warehouse] NOT IN ( 'C', 'CNW', 'C35', '55' )
                                GROUP BY [ACT].[ItemSKU]
                                        ,[ACT].[Warehouse]
                                        ,[CUS].[Customer Group]
                                        ,[DD].[FiscalMonthIndicator]
                                        ,[D2].[NumWeeks]
                                        ,[D2].[FiscalMonthYear]
                           )           AS N
                          INNER JOIN (

                                         -- Join last completed month's date and numweeks
                                         SELECT [FiscalMonthYear]
                                               ,[FiscalMonthLastDate]
                                               ,[FiscalMonthIndicator]
                                               ,COUNT(DISTINCT [FiscalWeekLastDate]) AS [NumWeeks]
                                           FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate]
                                          WHERE [FiscalMonthIndicator] = -1
                                          GROUP BY [FiscalMonthYear]
                                                  ,[FiscalMonthLastDate]
                                                  ,[FiscalMonthIndicator]
                                     ) AS D2
                              ON ([N].[FiscalMonthIndicator] + 1) = [D2].[FiscalMonthIndicator]
                ) AS NF
          ON [ACT].[ItemSKU] = [NF].[ItemSKU]
         AND [FC].[Warehouse] = [NF].[Warehouse]
         AND [FC].[FiscalMonthYear] = [NF].[FiscalMonthYear]
         AND [FC].[Customer Group] = [NF].[Customer Group]
 WHERE (
           [FC].[TotalForecast] > 0
      OR   ISNULL([ACT].[ActualDemand], 0) > 0
      OR   ISNULL([NF].[NaiveFcst], 0) > 0
       )

) 