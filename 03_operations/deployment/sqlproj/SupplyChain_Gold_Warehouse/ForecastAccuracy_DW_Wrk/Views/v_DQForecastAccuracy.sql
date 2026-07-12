-- Auto Generated (Do not modify) 6DA12462E1F42ACB973CDE84A348C0121829119E87416E3D86EC69EE1D982419
-- DataQuality.v_DQForecastAccuracy
-- 2026-07-10: remove remaining Staging.DemandForecastSnapshotDaily dependencies before physical drop.
-- 2026-07-10: retired Staging DF load-parity rules after direct-EL cutover (Shared_Staging no-op).
CREATE OR ALTER VIEW [DataQuality].[v_DQForecastAccuracy] AS
WITH
run_meta AS (
    SELECT
        CAST(NEWID() AS uniqueidentifier) AS DQRunId,
        CAST(SYSUTCDATETIME() AS datetime2(6)) AS DQRunAtUTC
),
S_cf AS (
    SELECT TOP 1
        FSCYearNum
    FROM ReferenceMaster_Enh_Wrk.v_Calendar
    WHERE Date = CAST(GETDATE() AS DATE)
),
G_Actual_Flat AS (
    SELECT SUM(CAST(Qty AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastActual
    WHERE HorizonCode = 'Actual demand'
),
G_Actual_KPI AS (
    SELECT SUM(CAST(QtyActual AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastKpi
    WHERE HorizonCode = 'Actual demand'
),
G_Forecast_Flat AS (
    SELECT SUM(CAST(Qty AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastActual
    WHERE HorizonCode IN ('Lag-0', 'Lag-1', 'Lag-2', 'Lag-3', 'Lag-4', '>Lag-4')
),
G_Forecast_KPI AS (
    SELECT SUM(CAST(QtyForecast AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastKpi
    WHERE TRIM(HorizonCode) IN ('Lag-0', 'Lag-1', 'Lag-2', 'Lag-3', 'Lag-4', '>Lag-4')
),
G_Naive_Flat AS (
    SELECT SUM(CAST(Qty AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastActual
    WHERE HorizonCode = 'Naive forecast'
),
G_Naive_KPI AS (
    SELECT SUM(CAST(QtyNaiveForecast AS float)) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastKpi
    WHERE HorizonCode = 'Naive forecast'
),
S1_Actual AS (
    SELECT SUM(QtyDemand) AS Qty
    FROM SalesHistory_Enh_Wrk.v_ActualDemandMonthly
),
S1_Invoice AS (
    SELECT SUM(CAST(QtyDemand AS float)) AS Qty
    FROM SalesHistory_Enh_Wrk.v_ActualDemandMonthly
    WHERE StatusCode = 'Invoice'
),
S1_OpenOrder AS (
    SELECT SUM(CAST(QtyDemand AS float)) AS Qty
    FROM SalesHistory_Enh_Wrk.v_ActualDemandMonthly
    WHERE StatusCode = 'Open Order'
),
S1_Forecast AS (
    SELECT SUM(QtyForecast) AS Qty
    FROM ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
),
S1_Naive AS (
    SELECT SUM(QtyDemand) AS Qty
    FROM ForecastHistory_Enh_Wrk.v_NaiveForecastMonthly
),
S2_Invoice AS (
    SELECT SUM(CAST(inv.QtyShipped AS float)) AS Qty
    FROM SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel AS inv
    INNER JOIN ReferenceMaster_Enh_Wrk.v_Calendar AS cal
        ON cal.Date = DATEADD(DAY, -COALESCE(inv.LeadTimeDaysNum, 0), inv.CurrentRequest)
    CROSS JOIN S_cf
    WHERE inv.QtyShipped > 0
      AND cal.FSCYearNum BETWEEN S_cf.FSCYearNum - 3 AND S_cf.FSCYearNum + 1
),
S2_Invoice_NoFilter AS (
    SELECT SUM(CAST(inv.QtyShipped AS float)) AS Qty
    FROM SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel AS inv
),
S2_OpenOrder AS (
    SELECT SUM(CAST(oo.QtyOpenOrder AS float)) AS Qty
    FROM OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel AS oo
    INNER JOIN ReferenceMaster_Enh_Wrk.v_Calendar AS cal
        ON cal.Date = DATEADD(DAY, -COALESCE(oo.LeadTimeDaysNum, 0), oo.CurrentRequest)
    CROSS JOIN S_cf
    WHERE oo.AllocationFlagCode = '2'
      AND cal.FSCYearNum BETWEEN S_cf.FSCYearNum - 3 AND S_cf.FSCYearNum + 1
),
S2_OpenOrder_NoFilter AS (
    SELECT SUM(CAST(oo.QtyOpenOrder AS float)) AS Qty
    FROM OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel AS oo
),
S2_Forecast AS (
    SELECT SUM(CAST(fc.dfcResultantForecast AS float) + CAST(fc.dfcPromotionalLift AS float)) AS Qty
    FROM [Enterprise_Lakehouse].SupplyChain_Enh.DemandForecastSnapshotDaily AS fc
    INNER JOIN ReferenceMaster_Enh_Wrk.v_ForecastCycle AS cyc
        ON CAST(fc.dfcSnapshot AS date) = cyc.ForecastSnapshot
    WHERE DATEFROMPARTS(CAST(fc.dfcFiscalMonth / 100 AS int), CAST(fc.dfcFiscalMonth % 100 AS int), 1)
              >= DATEADD(MONTH, -36, DATETRUNC(YEAR, DATEADD(MONTH, -6, CAST(GETDATE() AS date))))
      AND DATEFROMPARTS(CAST(fc.dfcFiscalMonth / 100 AS int), CAST(fc.dfcFiscalMonth % 100 AS int), 1)
              <= DATEADD(MONTH, 12, DATETRUNC(YEAR, DATEADD(MONTH, 6, CAST(GETDATE() AS date))))
),
S2_Forecast_NoFilter AS (
    SELECT COALESCE(SUM(CAST(COALESCE(fc.dfcResultantForecast, 0) + COALESCE(fc.dfcPromotionalLift, 0) AS decimal(38,6))), 0) AS Qty
    FROM [Enterprise_Lakehouse].SupplyChain_Enh.DemandForecastSnapshotDaily AS fc
),
B_Invoice AS (
    SELECT SUM(CAST(QuantityShipped AS float)) AS Qty
    FROM [Enterprise_Lakehouse].SalesHistory_AFI_Enh.InvoiceDetail
),
B_OpenOrder AS (
    SELECT SUM(CAST(ord.COQTY - ord.QTYSH AS int)) AS Qty
    FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.Codatan AS ord
    LEFT JOIN [Enterprise_Lakehouse].Wholesale_Codis_AFI.Extorit AS oit
        ON ord.ORDNO = oit.IORD
       AND ord.ITMSQ = oit.ISEQ
    INNER JOIN [Enterprise_Lakehouse].Wholesale_Codis_AFI.Comast AS om
        ON ord.ORDNO = om.ORDNO
    INNER JOIN [Enterprise_Lakehouse].Wholesale_Codis_AFI.Extord AS eor
        ON ord.ORDNO = eor.XORDNO
    WHERE (ord.QTYBO <> 0 OR ord.COQTY <> 0)
      AND ord.PRICE <> 0
      AND om.ACREC <> 'X'
      AND ord.COQTY >= 0
),
B_Forecast AS (
    SELECT COALESCE(SUM(CAST(COALESCE(dfcResultantForecast, 0) + COALESCE(dfcPromotionalLift, 0) AS decimal(38,6))), 0) AS Qty
    FROM (
        SELECT
            dfcResultantForecast,
            dfcPromotionalLift,
            ROW_NUMBER() OVER (
                PARTITION BY dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot,
                             DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode
                ORDER BY
                    COALESCE(dtec, dtea) DESC,
                    COALESCE(dtea, dtec) DESC,
                    COALESCE(usrc, usra) DESC,
                    COALESCE(usra, usrc) DESC,
                    CAST(COALESCE(dfcResultantForecast, 0) AS decimal(38,6)) DESC,
                    CAST(COALESCE(dfcPromotionalLift, 0) AS decimal(38,6)) DESC
            ) AS _rn
        FROM [Enterprise_Lakehouse].SupplyChain_Enh.DemandForecastSnapshotDaily
    ) AS d
    WHERE d._rn = 1
),
LP_RefCalendar_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_Calendar
),
LP_RefCalendar_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.Calendar
),
LP_RefCustomerAccount_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_CustomerAccount
),
LP_RefCustomerAccount_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.CustomerAccount
),
LP_RefCustomerAccountGroup_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_CustomerAccountGroup
),
LP_RefCustomerAccountGroup_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.CustomerAccountGroup
),
LP_RefCustomerGrouping_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_CustomerGrouping
),
LP_RefCustomerGrouping_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.CustomerGrouping
),
LP_RefCustomerShippingLocation_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_CustomerShippingLocation
),
LP_RefCustomerShippingLocation_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.CustomerShippingLocation
),
LP_RefForecastCycle_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_ForecastCycle
),
LP_RefForecastCycle_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.ForecastCycle
),
LP_RefForecastHorizon_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_ForecastHorizon
),
LP_RefForecastHorizon_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.ForecastHorizon
),
LP_RefItemMaster_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_ItemMaster
),
LP_RefItemMaster_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.ItemMaster
),
LP_RefOrderType_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_OrderType
),
LP_RefOrderType_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.OrderType
),
LP_RefWarehouse_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh_Wrk.v_Warehouse
),
LP_RefWarehouse_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM ReferenceMaster_Enh.Warehouse
),
LP_StagingDemand_View AS (
    -- RETIRED path 2026-07-10: Staging DF dropped; keep CTE shape with zero stubs for legacy rule names.
    SELECT CAST(0 AS bigint) AS RowCnt, CAST(0 AS decimal(38,6)) AS Qty
),
LP_StagingDemand_Physical AS (
    -- RETIRED path 2026-07-10: physical Staging.DemandForecastSnapshotDaily removed.
    SELECT CAST(0 AS bigint) AS RowCnt, CAST(0 AS decimal(38,6)) AS Qty
),
LP_InvoiceLine_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyShipped, 0) AS decimal(38,6))), 0) AS QtyShipped,
        COALESCE(SUM(CAST(COALESCE(AmtNetSales, 0) AS decimal(38,6))), 0) AS AmtNetSales
    FROM SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel
),
LP_InvoiceLine_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyShipped, 0) AS decimal(38,6))), 0) AS QtyShipped,
        COALESCE(SUM(CAST(COALESCE(AmtNetSales, 0) AS decimal(38,6))), 0) AS AmtNetSales
    FROM SalesHistory_Enh.InvoiceDetailLineLevel
),
LP_OpenOrderLine_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyOpenOrder, 0) AS decimal(38,6))), 0) AS QtyOpenOrder,
        COALESCE(SUM(CAST(COALESCE(AmtOpenOrder, 0) AS decimal(38,6))), 0) AS AmtOpenOrder
    FROM OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel
),
LP_OpenOrderLine_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyOpenOrder, 0) AS decimal(38,6))), 0) AS QtyOpenOrder,
        COALESCE(SUM(CAST(COALESCE(AmtOpenOrder, 0) AS decimal(38,6))), 0) AS AmtOpenOrder
    FROM OpenOrderHistory_Enh.OpenOrderLineLevel
),
LP_ActualDemandMonthly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand,
        COALESCE(SUM(CAST(COALESCE(AmtDemand, 0) AS decimal(38,6))), 0) AS AmtDemand
    FROM SalesHistory_Enh_Wrk.v_ActualDemandMonthly
),
LP_ActualDemandMonthly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand,
        COALESCE(SUM(CAST(COALESCE(AmtDemand, 0) AS decimal(38,6))), 0) AS AmtDemand
    FROM SalesHistory_Enh.ActualDemandMonthly
),
LP_ActualDemandWeekly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand,
        COALESCE(SUM(CAST(COALESCE(AmtDemand, 0) AS decimal(38,6))), 0) AS AmtDemand
    FROM SalesHistory_Enh_Wrk.v_ActualDemandWeekly
),
LP_ActualDemandWeekly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand,
        COALESCE(SUM(CAST(COALESCE(AmtDemand, 0) AS decimal(38,6))), 0) AS AmtDemand
    FROM SalesHistory_Enh.ActualDemandWeekly
),
LP_InvoiceWeekly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyShipped, 0) AS decimal(38,6))), 0) AS QtyShipped,
        COALESCE(SUM(CAST(COALESCE(AmtNetSales, 0) AS decimal(38,6))), 0) AS AmtNetSales,
        COALESCE(SUM(CAST(COALESCE(AmtInvoice, 0) AS decimal(38,6))), 0) AS AmtInvoice,
        COALESCE(SUM(CAST(COALESCE(AmtFreight, 0) AS decimal(38,6))), 0) AS AmtFreight
    FROM SalesHistory_Enh_Wrk.v_InvoiceWeekly
),
LP_InvoiceWeekly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyShipped, 0) AS decimal(38,6))), 0) AS QtyShipped,
        COALESCE(SUM(CAST(COALESCE(AmtNetSales, 0) AS decimal(38,6))), 0) AS AmtNetSales,
        COALESCE(SUM(CAST(COALESCE(AmtInvoice, 0) AS decimal(38,6))), 0) AS AmtInvoice,
        COALESCE(SUM(CAST(COALESCE(AmtFreight, 0) AS decimal(38,6))), 0) AS AmtFreight
    FROM SalesHistory_Enh.InvoiceWeekly
),
LP_ForecastDemandMonthly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyForecast, 0) AS decimal(38,6))), 0) AS QtyForecast
    FROM ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly
),
LP_ForecastDemandMonthly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyForecast, 0) AS decimal(38,6))), 0) AS QtyForecast
    FROM ForecastHistory_Enh.ForecastDemandMonthly
),
LP_NaiveForecastMonthly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand
    FROM ForecastHistory_Enh_Wrk.v_NaiveForecastMonthly
),
LP_NaiveForecastMonthly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyDemand, 0) AS decimal(38,6))), 0) AS QtyDemand
    FROM ForecastHistory_Enh.NaiveForecastMonthly
),
LP_OpenOrderMonthly_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyOpenOrder, 0) AS decimal(38,6))), 0) AS QtyOpenOrder,
        COALESCE(SUM(CAST(COALESCE(QtyBackorder, 0) AS decimal(38,6))), 0) AS QtyBackorder,
        COALESCE(SUM(CAST(COALESCE(AmtOpenOrder, 0) AS decimal(38,6))), 0) AS AmtOpenOrder,
        COALESCE(SUM(CAST(COALESCE(AmtBackorder, 0) AS decimal(38,6))), 0) AS AmtBackorder,
        COALESCE(SUM(CAST(COALESCE(QtyPastDue, 0) AS decimal(38,6))), 0) AS QtyPastDue,
        COALESCE(SUM(CAST(COALESCE(AmtPastDue, 0) AS decimal(38,6))), 0) AS AmtPastDue
    FROM OpenOrderHistory_Enh_Wrk.v_OpenOrderMonthly
),
LP_OpenOrderMonthly_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyOpenOrder, 0) AS decimal(38,6))), 0) AS QtyOpenOrder,
        COALESCE(SUM(CAST(COALESCE(QtyBackorder, 0) AS decimal(38,6))), 0) AS QtyBackorder,
        COALESCE(SUM(CAST(COALESCE(AmtOpenOrder, 0) AS decimal(38,6))), 0) AS AmtOpenOrder,
        COALESCE(SUM(CAST(COALESCE(AmtBackorder, 0) AS decimal(38,6))), 0) AS AmtBackorder,
        COALESCE(SUM(CAST(COALESCE(QtyPastDue, 0) AS decimal(38,6))), 0) AS QtyPastDue,
        COALESCE(SUM(CAST(COALESCE(AmtPastDue, 0) AS decimal(38,6))), 0) AS AmtPastDue
    FROM OpenOrderHistory_Enh.OpenOrderMonthly
),
LP_SharedDimCalendar_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW_Wrk.v_DimCalendar
),
LP_SharedDimCalendar_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW.DimCalendar
),
LP_SharedDimProduct_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW_Wrk.v_DimProduct
),
LP_SharedDimProduct_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW.DimProduct
),
LP_SharedDimWarehouse_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW_Wrk.v_DimWarehouse
),
LP_SharedDimWarehouse_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].Shared_DW.DimWarehouse
),
LP_FactForecastActual_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(Qty, 0) AS decimal(38,6))), 0) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastActual
),
LP_FactForecastActual_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(Qty, 0) AS decimal(38,6))), 0) AS Qty
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.FactForecastActual
),
LP_FactForecastKpi_View AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyForecast, 0) AS decimal(38,6))), 0) AS QtyForecast,
        COALESCE(SUM(CAST(COALESCE(QtyActual, 0) AS decimal(38,6))), 0) AS QtyActual,
        COALESCE(SUM(CAST(COALESCE(QtyNaiveForecast, 0) AS decimal(38,6))), 0) AS QtyNaiveForecast
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_FactForecastKpi
),
LP_FactForecastKpi_Physical AS (
    SELECT
        COUNT_BIG(*) AS RowCnt,
        COALESCE(SUM(CAST(COALESCE(QtyForecast, 0) AS decimal(38,6))), 0) AS QtyForecast,
        COALESCE(SUM(CAST(COALESCE(QtyActual, 0) AS decimal(38,6))), 0) AS QtyActual,
        COALESCE(SUM(CAST(COALESCE(QtyNaiveForecast, 0) AS decimal(38,6))), 0) AS QtyNaiveForecast
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.FactForecastKpi
),
LP_DimForecastHorizon_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_DimForecastHorizon
),
LP_DimForecastHorizon_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.DimForecastHorizon
),
LP_DimCustomerGrouping_View AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW_Wrk.v_DimCustomerGrouping
),
LP_DimCustomerGrouping_Physical AS (
    SELECT COUNT_BIG(*) AS RowCnt
    FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.DimCustomerGrouping
),
DQ AS (
    SELECT
        'DQ_G2G_Actual_Qty' AS RuleName,
        'Actual demand qty must match between both gold tables' AS RuleDescription,
        CASE WHEN ABS((SELECT Qty FROM G_Actual_Flat) - (SELECT Qty FROM G_Actual_KPI)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END AS Result
    UNION ALL
    SELECT
        'DQ_G2G_Forecast_Qty',
        'Forecast qty (Lag-0 to >Lag-4) must match between both gold tables',
        CASE WHEN ABS((SELECT Qty FROM G_Forecast_Flat) - (SELECT Qty FROM G_Forecast_KPI)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_G2G_NaiveForecast_Qty',
        'Naive forecast qty must match between both gold tables',
        CASE WHEN ABS((SELECT Qty FROM G_Naive_Flat) - (SELECT Qty FROM G_Naive_KPI)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2G_Actual_Qty',
        'Actual demand qty must match between silver and gold table',
        CASE WHEN ABS((SELECT Qty FROM G_Actual_Flat) - (SELECT Qty FROM S1_Actual)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2G_Forecast_Qty',
        'Forecast demand qty must match between silver and gold table',
        CASE WHEN ABS((SELECT Qty FROM G_Forecast_Flat) - (SELECT Qty FROM S1_Forecast)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2G_NaiveForecast_Qty',
        'Naive forecast demand qty must match between silver and gold table',
        CASE WHEN ABS((SELECT Qty FROM G_Naive_Flat) - (SELECT Qty FROM S1_Naive)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2S1_Invoice_Qty',
        'Invoice QtyShipped (silver wave 2) must match QtyDemand (silver wave 1, StatusCode=Invoice)',
        CASE WHEN ABS((SELECT Qty FROM S2_Invoice) - (SELECT Qty FROM S1_Invoice)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2S1_OpenOrder_Qty',
        'Open Order QtyOpenOrder (silver wave 2) must match QtyDemand (silver wave 1, StatusCode=Open Order)',
        CASE WHEN ABS((SELECT Qty FROM S2_OpenOrder) - (SELECT Qty FROM S1_OpenOrder)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_S2S1_Forecast_Qty',
        'Forecast QtyResultantForecast+QtyPromotionalLift (silver wave 2) must match QtyForecast (silver wave 1)',
        CASE WHEN ABS((SELECT Qty FROM S2_Forecast) - (SELECT Qty FROM S1_Forecast)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_B2S2_Invoice_Qty',
        'QuantityShipped (bronze raw) must match QtyShipped in silver transform view SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel',
        CASE WHEN ABS((SELECT Qty FROM B_Invoice) - (SELECT Qty FROM S2_Invoice_NoFilter)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_B2S2_OpenOrder_Qty',
        'QtyOpenOrder (bronze raw) must match QtyOpenOrder in silver transform view OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel',
        CASE WHEN ABS((SELECT Qty FROM B_OpenOrder) - (SELECT Qty FROM S2_OpenOrder_NoFilter)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_B2S2_Forecast_Qty',
        'ResultantForecast+PromotionalLift (bronze raw deduped by canonical 7-key) must match silver/staging-wrapper path (now direct EL after Staging drop 2026-07-10)',
        CASE WHEN ABS((SELECT Qty FROM B_Forecast) - (SELECT Qty FROM S2_Forecast_NoFilter)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_Calendar_RowCount',
        'ReferenceMaster_Enh_Wrk.v_Calendar row count must match ReferenceMaster_Enh.Calendar physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefCalendar_View) = (SELECT RowCnt FROM LP_RefCalendar_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_CustomerAccount_RowCount',
        'ReferenceMaster_Enh_Wrk.v_CustomerAccount row count must match ReferenceMaster_Enh.CustomerAccount physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefCustomerAccount_View) = (SELECT RowCnt FROM LP_RefCustomerAccount_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_CustomerAccountGroup_RowCount',
        'ReferenceMaster_Enh_Wrk.v_CustomerAccountGroup row count must match ReferenceMaster_Enh.CustomerAccountGroup physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefCustomerAccountGroup_View) = (SELECT RowCnt FROM LP_RefCustomerAccountGroup_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_CustomerGrouping_RowCount',
        'ReferenceMaster_Enh_Wrk.v_CustomerGrouping row count must match ReferenceMaster_Enh.CustomerGrouping physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefCustomerGrouping_View) = (SELECT RowCnt FROM LP_RefCustomerGrouping_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_CustomerShippingLocation_RowCount',
        'ReferenceMaster_Enh_Wrk.v_CustomerShippingLocation row count must match ReferenceMaster_Enh.CustomerShippingLocation physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefCustomerShippingLocation_View) = (SELECT RowCnt FROM LP_RefCustomerShippingLocation_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_ForecastCycle_RowCount',
        'ReferenceMaster_Enh_Wrk.v_ForecastCycle row count must match ReferenceMaster_Enh.ForecastCycle physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefForecastCycle_View) = (SELECT RowCnt FROM LP_RefForecastCycle_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_ForecastHorizon_RowCount',
        'ReferenceMaster_Enh_Wrk.v_ForecastHorizon row count must match ReferenceMaster_Enh.ForecastHorizon physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefForecastHorizon_View) = (SELECT RowCnt FROM LP_RefForecastHorizon_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_ItemMaster_RowCount',
        'ReferenceMaster_Enh_Wrk.v_ItemMaster row count must match ReferenceMaster_Enh.ItemMaster physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefItemMaster_View) = (SELECT RowCnt FROM LP_RefItemMaster_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_OrderType_RowCount',
        'ReferenceMaster_Enh_Wrk.v_OrderType row count must match ReferenceMaster_Enh.OrderType physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefOrderType_View) = (SELECT RowCnt FROM LP_RefOrderType_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ReferenceMaster_Warehouse_RowCount',
        'ReferenceMaster_Enh_Wrk.v_Warehouse row count must match ReferenceMaster_Enh.Warehouse physical table',
        CASE WHEN (SELECT RowCnt FROM LP_RefWarehouse_View) = (SELECT RowCnt FROM LP_RefWarehouse_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_StagingDemandForecastSnapshotDaily_RowCount',
        'RETIRED 2026-07-10 after direct-EL cutover: Staging DF no longer on primary path (Shared_Staging no-op). Rule forced PASS.',
        'PASS'
    UNION ALL
    SELECT
        'DQ_LoadParity_StagingDemandForecastSnapshotDaily_Qty',
        'RETIRED 2026-07-10 after direct-EL cutover: Staging DF no longer on primary path (Shared_Staging no-op). Rule forced PASS.',
        'PASS'
    UNION ALL
    SELECT
        'DQ_LoadParity_InvoiceDetailLineLevel_RowCount',
        'SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel row count must match SalesHistory_Enh.InvoiceDetailLineLevel physical table',
        CASE WHEN (SELECT RowCnt FROM LP_InvoiceLine_View) = (SELECT RowCnt FROM LP_InvoiceLine_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_InvoiceDetailLineLevel_Measures',
        'SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel QtyShipped and AmtNetSales totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyShipped FROM LP_InvoiceLine_View) - (SELECT QtyShipped FROM LP_InvoiceLine_Physical)) < 0.000001
             AND ABS((SELECT AmtNetSales FROM LP_InvoiceLine_View) - (SELECT AmtNetSales FROM LP_InvoiceLine_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_OpenOrderLineLevel_RowCount',
        'OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel row count must match OpenOrderHistory_Enh.OpenOrderLineLevel physical table',
        CASE WHEN (SELECT RowCnt FROM LP_OpenOrderLine_View) = (SELECT RowCnt FROM LP_OpenOrderLine_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_OpenOrderLineLevel_Measures',
        'OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel QtyOpenOrder and AmtOpenOrder totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyOpenOrder FROM LP_OpenOrderLine_View) - (SELECT QtyOpenOrder FROM LP_OpenOrderLine_Physical)) < 0.000001
             AND ABS((SELECT AmtOpenOrder FROM LP_OpenOrderLine_View) - (SELECT AmtOpenOrder FROM LP_OpenOrderLine_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_ActualDemandMonthly_RowCount',
        'SalesHistory_Enh_Wrk.v_ActualDemandMonthly row count must match SalesHistory_Enh.ActualDemandMonthly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_ActualDemandMonthly_View) = (SELECT RowCnt FROM LP_ActualDemandMonthly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ActualDemandMonthly_Measures',
        'SalesHistory_Enh_Wrk.v_ActualDemandMonthly QtyDemand and AmtDemand totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyDemand FROM LP_ActualDemandMonthly_View) - (SELECT QtyDemand FROM LP_ActualDemandMonthly_Physical)) < 0.000001
             AND ABS((SELECT AmtDemand FROM LP_ActualDemandMonthly_View) - (SELECT AmtDemand FROM LP_ActualDemandMonthly_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_ActualDemandWeekly_RowCount',
        'SalesHistory_Enh_Wrk.v_ActualDemandWeekly row count must match SalesHistory_Enh.ActualDemandWeekly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_ActualDemandWeekly_View) = (SELECT RowCnt FROM LP_ActualDemandWeekly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ActualDemandWeekly_Measures',
        'SalesHistory_Enh_Wrk.v_ActualDemandWeekly QtyDemand and AmtDemand totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyDemand FROM LP_ActualDemandWeekly_View) - (SELECT QtyDemand FROM LP_ActualDemandWeekly_Physical)) < 0.000001
             AND ABS((SELECT AmtDemand FROM LP_ActualDemandWeekly_View) - (SELECT AmtDemand FROM LP_ActualDemandWeekly_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_InvoiceWeekly_RowCount',
        'SalesHistory_Enh_Wrk.v_InvoiceWeekly row count must match SalesHistory_Enh.InvoiceWeekly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_InvoiceWeekly_View) = (SELECT RowCnt FROM LP_InvoiceWeekly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_InvoiceWeekly_Measures',
        'SalesHistory_Enh_Wrk.v_InvoiceWeekly QtyShipped, AmtNetSales, AmtInvoice, and AmtFreight totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyShipped FROM LP_InvoiceWeekly_View) - (SELECT QtyShipped FROM LP_InvoiceWeekly_Physical)) < 0.000001
             AND ABS((SELECT AmtNetSales FROM LP_InvoiceWeekly_View) - (SELECT AmtNetSales FROM LP_InvoiceWeekly_Physical)) < 0.000001
             AND ABS((SELECT AmtInvoice FROM LP_InvoiceWeekly_View) - (SELECT AmtInvoice FROM LP_InvoiceWeekly_Physical)) < 0.000001
             AND ABS((SELECT AmtFreight FROM LP_InvoiceWeekly_View) - (SELECT AmtFreight FROM LP_InvoiceWeekly_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_ForecastDemandMonthly_RowCount',
        'ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly row count must match ForecastHistory_Enh.ForecastDemandMonthly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_ForecastDemandMonthly_View) = (SELECT RowCnt FROM LP_ForecastDemandMonthly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_ForecastDemandMonthly_Qty',
        'ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly QtyForecast total must match physical table',
        CASE WHEN ABS((SELECT QtyForecast FROM LP_ForecastDemandMonthly_View) - (SELECT QtyForecast FROM LP_ForecastDemandMonthly_Physical)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_NaiveForecastMonthly_RowCount',
        'ForecastHistory_Enh_Wrk.v_NaiveForecastMonthly row count must match ForecastHistory_Enh.NaiveForecastMonthly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_NaiveForecastMonthly_View) = (SELECT RowCnt FROM LP_NaiveForecastMonthly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_NaiveForecastMonthly_Qty',
        'ForecastHistory_Enh_Wrk.v_NaiveForecastMonthly QtyDemand total must match physical table',
        CASE WHEN ABS((SELECT QtyDemand FROM LP_NaiveForecastMonthly_View) - (SELECT QtyDemand FROM LP_NaiveForecastMonthly_Physical)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_OpenOrderMonthly_RowCount',
        'OpenOrderHistory_Enh_Wrk.v_OpenOrderMonthly row count must match OpenOrderHistory_Enh.OpenOrderMonthly physical table',
        CASE WHEN (SELECT RowCnt FROM LP_OpenOrderMonthly_View) = (SELECT RowCnt FROM LP_OpenOrderMonthly_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_OpenOrderMonthly_Measures',
        'OpenOrderHistory_Enh_Wrk.v_OpenOrderMonthly order, backorder, and past due totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyOpenOrder FROM LP_OpenOrderMonthly_View) - (SELECT QtyOpenOrder FROM LP_OpenOrderMonthly_Physical)) < 0.000001
             AND ABS((SELECT QtyBackorder FROM LP_OpenOrderMonthly_View) - (SELECT QtyBackorder FROM LP_OpenOrderMonthly_Physical)) < 0.000001
             AND ABS((SELECT AmtOpenOrder FROM LP_OpenOrderMonthly_View) - (SELECT AmtOpenOrder FROM LP_OpenOrderMonthly_Physical)) < 0.000001
             AND ABS((SELECT AmtBackorder FROM LP_OpenOrderMonthly_View) - (SELECT AmtBackorder FROM LP_OpenOrderMonthly_Physical)) < 0.000001
             AND ABS((SELECT QtyPastDue FROM LP_OpenOrderMonthly_View) - (SELECT QtyPastDue FROM LP_OpenOrderMonthly_Physical)) < 0.000001
             AND ABS((SELECT AmtPastDue FROM LP_OpenOrderMonthly_View) - (SELECT AmtPastDue FROM LP_OpenOrderMonthly_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_SharedDimCalendar_RowCount',
        'Shared_DW_Wrk.v_DimCalendar row count must match Shared_DW.DimCalendar physical table',
        CASE WHEN (SELECT RowCnt FROM LP_SharedDimCalendar_View) = (SELECT RowCnt FROM LP_SharedDimCalendar_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_SharedDimProduct_RowCount',
        'Shared_DW_Wrk.v_DimProduct row count must match Shared_DW.DimProduct physical table',
        CASE WHEN (SELECT RowCnt FROM LP_SharedDimProduct_View) = (SELECT RowCnt FROM LP_SharedDimProduct_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_SharedDimWarehouse_RowCount',
        'Shared_DW_Wrk.v_DimWarehouse row count must match Shared_DW.DimWarehouse physical table',
        CASE WHEN (SELECT RowCnt FROM LP_SharedDimWarehouse_View) = (SELECT RowCnt FROM LP_SharedDimWarehouse_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_FactForecastActual_RowCount',
        'ForecastAccuracy_DW_Wrk.v_FactForecastActual row count must match ForecastAccuracy_DW.FactForecastActual physical table',
        CASE WHEN (SELECT RowCnt FROM LP_FactForecastActual_View) = (SELECT RowCnt FROM LP_FactForecastActual_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_FactForecastActual_Qty',
        'ForecastAccuracy_DW_Wrk.v_FactForecastActual Qty total must match physical table',
        CASE WHEN ABS((SELECT Qty FROM LP_FactForecastActual_View) - (SELECT Qty FROM LP_FactForecastActual_Physical)) < 0.000001 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_FactForecastKpi_RowCount',
        'ForecastAccuracy_DW_Wrk.v_FactForecastKpi row count must match ForecastAccuracy_DW.FactForecastKpi physical table',
        CASE WHEN (SELECT RowCnt FROM LP_FactForecastKpi_View) = (SELECT RowCnt FROM LP_FactForecastKpi_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_FactForecastKpi_Measures',
        'ForecastAccuracy_DW_Wrk.v_FactForecastKpi QtyForecast, QtyActual, and QtyNaiveForecast totals must match physical table',
        CASE
            WHEN ABS((SELECT QtyForecast FROM LP_FactForecastKpi_View) - (SELECT QtyForecast FROM LP_FactForecastKpi_Physical)) < 0.000001
             AND ABS((SELECT QtyActual FROM LP_FactForecastKpi_View) - (SELECT QtyActual FROM LP_FactForecastKpi_Physical)) < 0.000001
             AND ABS((SELECT QtyNaiveForecast FROM LP_FactForecastKpi_View) - (SELECT QtyNaiveForecast FROM LP_FactForecastKpi_Physical)) < 0.000001
            THEN 'PASS' ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        'DQ_LoadParity_DimForecastHorizon_RowCount',
        'ForecastAccuracy_DW_Wrk.v_DimForecastHorizon row count must match ForecastAccuracy_DW.DimForecastHorizon physical table',
        CASE WHEN (SELECT RowCnt FROM LP_DimForecastHorizon_View) = (SELECT RowCnt FROM LP_DimForecastHorizon_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_LoadParity_DimCustomerGrouping_RowCount',
        'ForecastAccuracy_DW_Wrk.v_DimCustomerGrouping row count must match ForecastAccuracy_DW.DimCustomerGrouping physical table',
        CASE WHEN (SELECT RowCnt FROM LP_DimCustomerGrouping_View) = (SELECT RowCnt FROM LP_DimCustomerGrouping_Physical) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT
        'DQ_Gold_Grain_FactForecastKPI',
        '(ItemSKU, WarehouseCode, FSCMonthLast, HorizonCode, Snapshot) must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, FSCMonthLast, HorizonCode, Snapshot
            FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.FactForecastKpi
            GROUP BY ItemSKU, WarehouseCode, FSCMonthLast, HorizonCode, Snapshot
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Gold_Grain_FactForecastActual',
        '(ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, HorizonCode, VersionName, StatusCode) must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, HorizonCode, VersionName, StatusCode
            FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.FactForecastActual
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, HorizonCode, VersionName, StatusCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Gold_Grain_DimForecastHorizon',
        'HorizonCode must be unique',
        CASE WHEN EXISTS (
            SELECT HorizonCode
            FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.DimForecastHorizon
            GROUP BY HorizonCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Gold_Grain_DimCustomerGrouping',
        'Customer must be unique',
        CASE WHEN EXISTS (
            SELECT Customer
            FROM [SupplyChain_Gold_Warehouse].ForecastAccuracy_DW.DimCustomerGrouping
            GROUP BY Customer
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_ForecastCycle',
        'dt_forecast_snapshot must be unique',
        CASE WHEN EXISTS (
            SELECT dt_forecast_snapshot
            FROM ProcessingSeed.ForecastCycle
            GROUP BY dt_forecast_snapshot
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_ActualDemandMonthly',
        'ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, StatusCode must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, StatusCode
            FROM SalesHistory_Enh.ActualDemandMonthly
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, StatusCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_ActualDemandWeekly',
        'ItemSKU, WarehouseCode, CustomerGroupCode, FSCWeekLast, StatusCode must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCWeekLast, StatusCode
            FROM SalesHistory_Enh.ActualDemandWeekly
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCWeekLast, StatusCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_InvoiceWeekly',
        'ItemSKU, WarehouseCode, AccountShipTo, FSCWeekLast must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, AccountShipTo, FSCWeekLast
            FROM SalesHistory_Enh.InvoiceWeekly
            GROUP BY ItemSKU, WarehouseCode, AccountShipTo, FSCWeekLast
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_OpenOrderMonthly',
        'ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast
            FROM OpenOrderHistory_Enh.OpenOrderMonthly
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_OpenOrderLineLevel',
        'OrderID, ItemSequenceNum, AccountShipTo, ItemSKU, WarehouseCode must be unique',
        CASE WHEN EXISTS (
            SELECT OrderID, ItemSequenceNum, AccountShipTo, ItemSKU, WarehouseCode
            FROM OpenOrderHistory_Enh.OpenOrderLineLevel
            GROUP BY OrderID, ItemSequenceNum, AccountShipTo, ItemSKU, WarehouseCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_ForecastDemandMonthly',
        'ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, Snapshot, HorizonCode must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, Snapshot, HorizonCode
            FROM ForecastHistory_Enh.ForecastDemandMonthly
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, Snapshot, HorizonCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Silver_Grain_NaiveForecastMonthly',
        'ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast must be unique',
        CASE WHEN EXISTS (
            SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast
            FROM ForecastHistory_Enh.NaiveForecastMonthly
            GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_AAORDTYP',
        'OTCODE must be unique',
        CASE WHEN EXISTS (
            SELECT OTCODE
            FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.AAORDTYP
            GROUP BY OTCODE
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_COMAST',
        'ORDNO must be unique',
        CASE WHEN EXISTS (
            SELECT ORDNO
            FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.Comast
            GROUP BY ORDNO
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_EXTORD',
        'XORDNO must be unique',
        CASE WHEN EXISTS (
            SELECT XORDNO
            FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.Extord
            GROUP BY XORDNO
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_EXTORIT',
        '(IORD, ISEQ) must be unique',
        CASE WHEN EXISTS (
            SELECT IORD, ISEQ
            FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.Extorit
            GROUP BY IORD, ISEQ
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_CODATAN',
        '(ORDNO, ITMSQ) must be unique',
        CASE WHEN EXISTS (
            SELECT ORDNO, ITMSQ
            FROM [Enterprise_Lakehouse].Wholesale_Codis_AFI.Codatan
            GROUP BY ORDNO, ITMSQ
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_InvoiceDetail',
        '(InvoiceNumber, OrderNumber, ItemSKU, ItemSequence) must be unique',
        CASE WHEN EXISTS (
            SELECT InvoiceNumber, OrderNumber, ItemSKU, ItemSequence
            FROM [Enterprise_Lakehouse].SalesHistory_AFI_Enh.InvoiceDetail
            GROUP BY InvoiceNumber, OrderNumber, ItemSKU, ItemSequence
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_InvoiceHeader',
        '(InvoiceNumber, OrderNumber) must be unique',
        CASE WHEN EXISTS (
            SELECT InvoiceNumber, OrderNumber
            FROM [Enterprise_Lakehouse].SalesHistory_AFI_Enh.InvoiceHeader
            GROUP BY InvoiceNumber, OrderNumber
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
    UNION ALL
    SELECT
        'DQ_Bronze_Grain_DemandForecastSnapshotDaily',
        'Raw bronze source must be unique by canonical 7-key (dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode)',
        CASE WHEN EXISTS (
            SELECT dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode
            FROM [Enterprise_Lakehouse].SupplyChain_Enh.DemandForecastSnapshotDaily
            GROUP BY dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode
            HAVING COUNT(*) > 1
        ) THEN 'FAIL' ELSE 'PASS' END
)
SELECT
    dq.RuleName,
    dq.RuleDescription,
    dq.Result,
    rm.DQRunId,
    rm.DQRunAtUTC,
    rm.DQRunAtUTC AS LoadDT
FROM DQ AS dq
CROSS JOIN run_meta AS rm;
