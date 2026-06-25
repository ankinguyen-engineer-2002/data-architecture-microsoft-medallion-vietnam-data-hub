-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactWorkingForecastCurrent
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE         VIEW [SCP_Core_Wrk].[v_FactWorkingForecastCurrent] AS (

SELECT RTRIM([DFC].[DfcCustomerGroups] ) AS [CustomerGroup]
      ,RTRIM([DFC].[dfcItem]     ) AS [ItemSKU]
      ,RTRIM([DFC].[dfcWarehouse]) AS [Warehouse]
      ,ISNULL([DD].[FiscalMonthLastDate],CONVERT(DATE, LEFT([DFC].[dfcFiscalMonth],4)+'-'+RIGHT([DFC].[dfcFiscalMonth],2)+'-15')) AS [FiscalMonthLastDate]
      ,[DFC].[dfcResultantForecast] AS [ResultantForecastQty]
      ,[DFC].[dfcPromotionalLift] AS [PromoLiftQty]
      ,[DFC].[dfcOrderFutureQty] AS [FutureOrderQty]
      ,CONVERT(DATE, [DFC].[dtea]) AS [SnapshotDate]
  FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[DemandForecast]  AS DFC
  LEFT JOIN (
SELECT DISTINCT [FiscalMonthYear], [FiscalMonthLastDate]
  FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate]
  ) AS DD
  ON [DFC].[dfcFiscalMonth] = [DD].[FiscalMonthYear]

);