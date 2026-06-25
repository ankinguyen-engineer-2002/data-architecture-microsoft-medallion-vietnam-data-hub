-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimFcstSnapshotDates
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE         VIEW [SCP_Core_Wrk].[v_DimFcstSnapshotDates] AS (
-- Create Forecast Date table for relating forecast cycles, snapshot date, lags, and Actuals

SELECT DISTINCT
       [DD1].[FcstCycle]
      ,[DD1].[FcstPeriod]
      ,[DD1].[FcstSnapshotDate]
      ,[DD].[FiscalMonthLastDate] AS [ActualsMonthEnd]
      ,[DD].[FiscalMonthYear]     AS [ActualsFiscalPeriod]
      ,[DD1].[SortFcstPeriod]
  FROM [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD

      -- Join table of forecast snapshot dates and Lag Periods

      INNER JOIN (
                     -- Create Lag-0 table relating Snapshot date to relevant Month End Actuals
                     SELECT [C].[CycleName]                AS [FcstCycle]
                           ,[C].[FcstSnapshot]         AS [FcstSnapshotDate]
                           ,[DD].[FiscalMonthIndicator] AS [SnapshotIndicator]
                           ,'Lag-0'                     AS [FcstPeriod]
                           ,'0'                         AS [SortFcstPeriod]
                       FROM [SupplyChain_Warehouse].[SCP_Core].[DimFcstConsensusCycleDates]                        AS C
                           LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD
                               ON [C].[FcstSnapshot] = [DD].[DateID]
                     UNION

                     -- Append Lag-1 table relating Snapshot date to relevant Month End Actuals
                     SELECT [C].[CycleName]                AS [FcstCycle]
                           ,[C].[FcstSnapshot]         AS [FcstSnapshotDate]
                           ,[DD].[FiscalMonthIndicator] + 1 AS [SnapshotIndicator]
                           ,'Lag-1'                         AS [FcstPeriod]
                           ,'1'                             AS [SortFcstPeriod]
                       FROM [SupplyChain_Warehouse].[SCP_Core].[DimFcstConsensusCycleDates]                        AS C
                           LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD
                               ON [C].[FcstSnapshot] = [DD].[DateID] 

                     UNION

                     -- Append Lag-2 table relating Snapshot date to relevant Month End Actuals
                     SELECT [C].[CycleName]                AS [FcstCycle]
                           ,[C].[FcstSnapshot]         AS [FcstSnapshotDate]
                           ,[DD].[FiscalMonthIndicator] + 2 AS [SnapshotIndicator]
                           ,'Lag-2'                         AS [FcstPeriod]
                           ,'2'                             AS [SortFcstPeriod]
                       FROM [SupplyChain_Warehouse].[SCP_Core].[DimFcstConsensusCycleDates]                        AS C
                           LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD
                               ON [C].[FcstSnapshot] = [DD].[DateID] 

                     UNION

                     -- Append Lag-3 table relating Snapshot date to relevant Month End Actuals
                     SELECT [C].[CycleName]                AS [FcstCycle]
                           ,[C].[FcstSnapshot]         AS [FcstSnapshotDate]
                           ,[DD].[FiscalMonthIndicator] + 3 AS [SnapshotIndicator]
                           ,'Lag-3'                         AS [FcstPeriod]
                           ,'3'                             AS [SortFcstPeriod]
                       FROM [SupplyChain_Warehouse].[SCP_Core].[DimFcstConsensusCycleDates]                        AS C
                           LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD
                               ON [C].[FcstSnapshot] = [DD].[DateID] 

                     UNION

                     -- Append Lag-4 table relating Snapshot date to relevant Month End Actuals
                     SELECT [C].[CycleName]                AS [FcstCycle]
                           ,[C].[FcstSnapshot]         AS [FcstSnapshotDate]
                           ,[DD].[FiscalMonthIndicator] + 4 AS [SnapshotIndicator]
                           ,'Lag-4'                         AS [FcstPeriod]
                           ,'4'                             AS [SortFcstPeriod]
                       FROM [SupplyChain_Warehouse].[SCP_Core].[DimFcstConsensusCycleDates]                        AS C
                           LEFT JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimDate] AS DD
                               ON [C].[FcstSnapshot] = [DD].[DateID] 

                 )               AS DD1
          ON [DD].[FiscalMonthIndicator] = [DD1].[SnapshotIndicator]


  )