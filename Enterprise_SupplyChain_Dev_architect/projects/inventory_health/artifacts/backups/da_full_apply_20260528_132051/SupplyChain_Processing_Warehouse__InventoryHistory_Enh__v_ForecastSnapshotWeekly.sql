
CREATE   VIEW InventoryHistory_Enh.v_ForecastSnapshotWeekly AS
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(CAST(dfcResultantForecast AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty,
    CAST('SupplyChain_Enh_1'              AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotWeekly'   AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotWeekly]
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth
