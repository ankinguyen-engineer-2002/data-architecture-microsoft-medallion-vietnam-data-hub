CREATE VIEW ForecastAccuracy_DW.vw_FactForecastKpi AS
WITH
fc AS (SELECT UPPER(TRIM(ItemSKU)) i, UPPER(TRIM(WarehouseCode)) w, CAST(FSCMonthFirst AS DATE) mf, CAST(FSCMonthLast AS DATE) ml, TRIM(HorizonCode) h, CAST(Snapshot AS DATE) ds, CAST(SUM(QtyForecast) AS FLOAT) qf FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.ForecastDemandMonthly WHERE HorizonCode IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4') GROUP BY UPPER(TRIM(ItemSKU)),UPPER(TRIM(WarehouseCode)),CAST(FSCMonthFirst AS DATE),CAST(FSCMonthLast AS DATE),TRIM(HorizonCode),CAST(Snapshot AS DATE)),
act AS (SELECT UPPER(TRIM(ItemSKU)) i, UPPER(TRIM(WarehouseCode)) w, CAST(FSCMonthFirst AS DATE) mf, CAST(FSCMonthLast AS DATE) ml, CAST(SUM(QtyDemand) AS FLOAT) qa FROM SupplyChain_Processing_Warehouse.SalesHistory_ENH.ActualDemandMonthly GROUP BY UPPER(TRIM(ItemSKU)),UPPER(TRIM(WarehouseCode)),CAST(FSCMonthFirst AS DATE),CAST(FSCMonthLast AS DATE)),
nv AS (SELECT UPPER(TRIM(ItemSKU)) i, UPPER(TRIM(WarehouseCode)) w, CAST(FSCMonthFirst AS DATE) mf, CAST(FSCMonthLast AS DATE) ml, CAST(SUM(QtyDemand) AS FLOAT) qn FROM SupplyChain_Processing_Warehouse.ForecastHistory_ENH.NaiveForecastMonthly GROUP BY UPPER(TRIM(ItemSKU)),UPPER(TRIM(WarehouseCode)),CAST(FSCMonthFirst AS DATE),CAST(FSCMonthLast AS DATE)),
dk AS (SELECT i,w,mf,ml FROM fc UNION SELECT i,w,mf,ml FROM act UNION SELECT i,w,mf,ml FROM nv),
sp AS (SELECT K.i,K.w,K.mf,K.ml,H.HorizonCode h FROM dk K CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.ForecastHorizon H)
SELECT sp.i AS ItemSKU, sp.w AS WarehouseCode, sp.mf AS FSCMonthFirst, sp.ml AS FSCMonthLast, sp.h AS HorizonCode, fc.ds AS Snapshot,
    CAST(fc.qf AS FLOAT) AS QtyForecast, CAST(act.qa AS FLOAT) AS QtyActual, CAST(nv.qn AS FLOAT) AS QtyNaiveForecast,
    CAST(COALESCE(fc.qf,0)-COALESCE(act.qa,0) AS FLOAT) AS QtyFcstError,
    CAST(ABS(COALESCE(fc.qf,0)-COALESCE(act.qa,0)) AS FLOAT) AS QtyAbsFcstError,
    CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM sp LEFT JOIN fc ON sp.i=fc.i AND sp.w=fc.w AND sp.mf=fc.mf AND sp.ml=fc.ml AND sp.h=fc.h
LEFT JOIN act ON sp.i=act.i AND sp.w=act.w AND sp.mf=act.mf AND sp.ml=act.ml
LEFT JOIN nv ON sp.i=nv.i AND sp.w=nv.w AND sp.mf=nv.mf AND sp.ml=nv.ml