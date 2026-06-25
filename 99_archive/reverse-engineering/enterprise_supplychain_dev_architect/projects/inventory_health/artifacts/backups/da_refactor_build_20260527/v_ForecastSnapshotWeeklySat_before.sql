
CREATE     VIEW InventoryHistory_Enh.v_ForecastSnapshotWeeklySat AS
-- 2026-05-22: NEW Weekly snapshot from Daily filtered Saturday only.
-- Drop-in replacement for v_ForecastSnapshotWeekly (Monday-source, DEAD upstream since 2024-03-25).
-- Source: Staging_Wrk.DemandForecastSnapshotDaily (cross-mart cleaned, deduped via ROW_NUMBER=1).
-- BRD requirement: 'week ending Saturday' — dfcSnapshot IS the Saturday date.
-- Schema mirrors live v_ForecastSnapshotWeekly (post-Giang fix 2026-05-20):
--   ItemSku, WarehouseCode, SnapshotDate, FiscalMonth, FiscalMonthDate, ForecastQty, PermComptQty, SourceSystem, SourceTable
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth) — same as Weekly.
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
    CAST('Staging_Wrk'                       AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily (Sat)' AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.DemandForecastSnapshotDaily
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND DATENAME(WEEKDAY, dfcSnapshot) = 'Saturday'
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth;
