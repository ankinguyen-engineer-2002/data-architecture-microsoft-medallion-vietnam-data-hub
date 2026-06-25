-- SalesHistory_Enh_Wrk.v_ActualDemandWeekly
CREATE   VIEW [SalesHistory_Enh_Wrk].[v_ActualDemandWeekly] AS
WITH cf AS (SELECT TOP 1 FSCYearNum FROM ReferenceMaster_Enh.Calendar WHERE Date=CAST(GETDATE() AS DATE)),
__bob_source AS (
SELECT INV.ItemSKU, INV.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END AS CustomerGroupCode,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(INV.QtyShipped) AS QtyDemand, SUM(INV.AmtNetSales) AS AmtDemand, 'Invoice' AS StatusCode, 'Actual Demand' AS VersionName
FROM SalesHistory_Enh.InvoiceDetailLineLevel INV
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-INV.LeadTimeDaysNum,INV.CurrentRequest)
CROSS JOIN cf WHERE INV.QtyShipped>0 AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY INV.ItemSKU, INV.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE INV.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
UNION ALL
SELECT OO.ItemSKU, OO.WarehouseCode,
    CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END,
    CAL.FSCWeekFirst, CAL.FSCWeekLast,
    SUM(OO.QtyOpenOrder), SUM(OO.AmtOpenOrder), 'Open Order', 'Actual Demand'
FROM OpenOrderHistory_Enh.OpenOrderLineLevel OO
INNER JOIN ReferenceMaster_Enh.Calendar CAL ON CAL.Date=DATEADD(DAY,-OO.LeadTimeDaysNum,OO.CurrentRequest)
LEFT JOIN ReferenceMaster_Enh.CustomerAccountGroup CG ON CG.Customer=OO.Customer
CROSS JOIN cf WHERE OO.AllocationFlagCode='2' AND CAL.FSCYearNum BETWEEN cf.FSCYearNum-3 AND cf.FSCYearNum+1
GROUP BY OO.ItemSKU, OO.WarehouseCode, CASE WHEN CAL.FSCWeekFirst<'2025-04-01' THEN 'AFICONS' ELSE CG.CustomerGroupCode END, CAL.FSCWeekFirst, CAL.FSCWeekLast
)
SELECT
    [ItemSKU] = src.[ItemSKU],
    [WarehouseCode] = src.[WarehouseCode],
    [CustomerGroupCode] = src.[CustomerGroupCode],
    [FSCWeekFirst] = src.[FSCWeekFirst],
    [FSCWeekLast] = src.[FSCWeekLast],
    [QtyDemand] = src.[QtyDemand],
    [AmtDemand] = src.[AmtDemand],
    [StatusCode] = src.[StatusCode],
    [VersionName] = src.[VersionName],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
