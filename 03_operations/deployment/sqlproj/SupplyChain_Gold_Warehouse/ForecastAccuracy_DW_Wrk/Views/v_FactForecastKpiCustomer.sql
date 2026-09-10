-- ForecastAccuracy_DW_Wrk.v_FactForecastKpi
CREATE     VIEW [ForecastAccuracy_DW_Wrk].[v_FactForecastKpiCustomer] AS
WITH
fc AS (
    SELECT UPPER(TRIM(CustomerGroupCode)) AS [CustomerGroupCode]
          ,UPPER(TRIM(ItemSKU)) AS [ItemSKU]
          ,UPPER(TRIM(WarehouseCode)) AS [WarehouseCode]
          ,CAST(FSCMonthFirst AS DATE) AS [FSCMonthFirst]
          ,CAST(FSCMonthLast AS DATE) AS [FSCMonthLast]
          ,TRIM(HorizonCode) AS [HorizonCode]
          ,CAST(Snapshot AS DATE) AS [Snapshot]
          ,CAST(SUM(QtyForecast) AS FLOAT) AS [QtyForecast]
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
    WHERE HorizonCode IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY UPPER(TRIM(CustomerGroupCode))
            ,UPPER(TRIM(ItemSKU))
            ,UPPER(TRIM(WarehouseCode))
            ,CAST(FSCMonthFirst AS DATE)
            ,CAST(FSCMonthLast AS DATE)
            ,TRIM(HorizonCode)
            ,CAST(Snapshot AS DATE)
),
act AS (
    SELECT UPPER(TRIM(CustomerGroupCode)) AS [CustomerGroupCode]
          ,UPPER(TRIM(ItemSKU)) AS [ItemSKU]
          ,UPPER(TRIM(WarehouseCode)) AS [WarehouseCode]
          ,CAST(FSCMonthFirst AS DATE) AS [FSCMonthFirst]
          ,CAST(FSCMonthLast AS DATE) AS [FSCMonthLast]
          ,CAST(SUM(QtyDemand) AS FLOAT) AS [QtyDemand]
    FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
    GROUP BY UPPER(TRIM(CustomerGroupCode))
            ,UPPER(TRIM(ItemSKU))
            ,UPPER(TRIM(WarehouseCode))
            ,CAST(FSCMonthFirst AS DATE)
            ,CAST(FSCMonthLast AS DATE)
),
nv AS (
    SELECT UPPER(TRIM(CustomerGroupCode)) AS [CustomerGroupCode]
          ,UPPER(TRIM(ItemSKU)) AS [ItemSKU]
          ,UPPER(TRIM(WarehouseCode)) AS [WarehouseCode]
          ,CAST(FSCMonthFirst AS DATE) AS [FSCMonthFirst]
          ,CAST(FSCMonthLast AS DATE) AS [FSCMonthLast]
          ,CAST(SUM(QtyDemand) AS FLOAT) AS [QtyDemand]
    FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly
    GROUP BY UPPER(TRIM(CustomerGroupCode))
            ,UPPER(TRIM(ItemSKU))
            ,UPPER(TRIM(WarehouseCode))
            ,CAST(FSCMonthFirst AS DATE)
            ,CAST(FSCMonthLast AS DATE)
),
dk AS (
    SELECT [CustomerGroupCode], [ItemSKU], [WarehouseCode], [FSCMonthFirst], [FSCMonthLast] FROM fc
    UNION SELECT [CustomerGroupCode], [ItemSKU], [WarehouseCode], [FSCMonthFirst], [FSCMonthLast] FROM act
    UNION SELECT [CustomerGroupCode], [ItemSKU], [WarehouseCode], [FSCMonthFirst], [FSCMonthLast] FROM nv
),
sp AS (
    SELECT K.[CustomerGroupCode]
          ,K.[ItemSKU]
          ,K.[WarehouseCode]
          ,K.[FSCMonthFirst]
          ,K.[FSCMonthLast]
          ,H.HorizonCode AS [HorizonCode]
    FROM dk K
    CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon H
)
SELECT sp.[CustomerGroupCode]
      ,sp.[ItemSKU]
      ,sp.[WarehouseCode]
      ,sp.[FSCMonthFirst]
      ,sp.[FSCMonthLast]
      ,sp.[HorizonCode]
      ,fc.[Snapshot]

    -- Quantities (existing 3)
    ,CAST(fc.[QtyForecast] AS INT)            AS QtyForecast
    ,CAST(act.[QtyDemand] AS INT)           AS QtyActual
    ,CAST(nv.[QtyDemand] AS INT)            AS QtyNaiveForecast

    -- Forecast error (existing 2)
    ,CAST(COALESCE(fc.[QtyForecast],0) - COALESCE(act.[QtyDemand],0) AS INT)
                                    AS QtyFcstError
    ,CAST(ABS(COALESCE(fc.[QtyForecast],0) - COALESCE(act.[QtyDemand],0)) AS INT)
                                    AS QtyAbsFcstError

    -- ── NEW: Naive forecast error (2 cols) ──
    ,CAST(COALESCE(nv.[QtyDemand],0) - COALESCE(act.[QtyDemand],0) AS INT)
                                    AS QtyNaiveFcstError
    ,CAST(ABS(COALESCE(nv.[QtyDemand],0) - COALESCE(act.[QtyDemand],0)) AS INT)
                                    AS QtyAbsNaiveFcstError

    -- ── NEW: Squared error components for RMSE (2 cols) ──
    ,CAST(POWER(COALESCE(fc.[QtyForecast],0) - COALESCE(act.[QtyDemand],0), 2) AS INT)
                                    AS QtySquaredFcstError
    ,CAST(POWER(COALESCE(nv.[QtyDemand],0) - COALESCE(act.[QtyDemand],0), 2) AS INT)
                                    AS QtySquaredNaiveFcstError

    -- ── NEW: Validity flags (2 cols) ──
    ,CAST(CASE WHEN act.[QtyDemand] IS NOT NULL AND fc.[QtyForecast] IS NOT NULL THEN 1 ELSE 0 END AS INT)
                                    AS ValidObsFlag
    ,CAST(CASE WHEN act.[QtyDemand] IS NOT NULL AND act.[QtyDemand] <> 0       THEN 1 ELSE 0 END AS INT)
                                    AS ValidActualNonzeroFlag

    -- ── NEW: Absolute percentage error (MAPE component) (1 col) ──
    ,CAST(CASE
        WHEN act.[QtyDemand] IS NOT NULL AND act.[QtyDemand] <> 0
            THEN ABS((COALESCE(fc.[QtyForecast],0) - act.[QtyDemand]) / act.[QtyDemand])
        ELSE NULL
    END AS DEC(10,4))                   AS AbsPctError

    -- Audit
    ,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT

FROM sp
LEFT JOIN fc
    ON (sp.[CustomerGroupCode] = fc.[CustomerGroupCode] OR (sp.[CustomerGroupCode] IS NULL AND fc.[CustomerGroupCode] IS NULL))
   AND (sp.[ItemSKU] = fc.[ItemSKU] OR (sp.[ItemSKU] IS NULL AND fc.[ItemSKU] IS NULL))
   AND (sp.[WarehouseCode] = fc.[WarehouseCode] OR (sp.[WarehouseCode] IS NULL AND fc.[WarehouseCode] IS NULL))
   AND (sp.[FSCMonthFirst] = fc.[FSCMonthFirst] OR (sp.[FSCMonthFirst] IS NULL AND fc.[FSCMonthFirst] IS NULL))
   AND (sp.[FSCMonthLast] = fc.[FSCMonthLast] OR (sp.[FSCMonthLast] IS NULL AND fc.[FSCMonthLast] IS NULL))
   AND (sp.[HorizonCode] = fc.[HorizonCode] OR (sp.[HorizonCode] IS NULL AND fc.[HorizonCode] IS NULL))
LEFT JOIN act
    ON (sp.[CustomerGroupCode] = act.[CustomerGroupCode] OR (sp.[CustomerGroupCode] IS NULL AND act.[CustomerGroupCode] IS NULL))
   AND (sp.[ItemSKU] = act.[ItemSKU] OR (sp.[ItemSKU] IS NULL AND act.[ItemSKU] IS NULL))
   AND (sp.[WarehouseCode] = act.[WarehouseCode] OR (sp.[WarehouseCode] IS NULL AND act.[WarehouseCode] IS NULL))
   AND (sp.[FSCMonthFirst] = act.[FSCMonthFirst] OR (sp.[FSCMonthFirst] IS NULL AND act.[FSCMonthFirst] IS NULL))
   AND (sp.[FSCMonthLast] = act.[FSCMonthLast] OR (sp.[FSCMonthLast] IS NULL AND act.[FSCMonthLast] IS NULL))
LEFT JOIN nv
    ON (sp.[CustomerGroupCode] = nv.[CustomerGroupCode] OR (sp.[CustomerGroupCode] IS NULL AND nv.[CustomerGroupCode] IS NULL))
   AND (sp.[ItemSKU] = nv.[ItemSKU] OR (sp.[ItemSKU] IS NULL AND nv.[ItemSKU] IS NULL))
   AND (sp.[WarehouseCode] = nv.[WarehouseCode] OR (sp.[WarehouseCode] IS NULL AND nv.[WarehouseCode] IS NULL))
   AND (sp.[FSCMonthFirst] = nv.[FSCMonthFirst] OR (sp.[FSCMonthFirst] IS NULL AND nv.[FSCMonthFirst] IS NULL))
   AND (sp.[FSCMonthLast] = nv.[FSCMonthLast] OR (sp.[FSCMonthLast] IS NULL AND nv.[FSCMonthLast] IS NULL));
