-- InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly
-- CORE CONCEPT UPDATE 2026-05-22:
--   SnapshotDate is the capture date; FiscalMonthDate is the forecast period.
--   Weekly reporting uses Saturday captures from the daily demand-forecast source.
--   Forecast demand is consumed downstream as next 3 fiscal months, not a single week.
--   Reference: Inventory Health Dataset.sql uses ResultantForecast + PromotionalLift for demand.
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- 2026-07-09 CUTOVER: read EL directly via [$(Databricks)].SupplyChain_Enh.DemandForecastSnapshotDaily.
--   Drop physical Staging hop. Transform/grain unchanged. No Source_Wrk wrapper.
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
CREATE VIEW [InventoryHistory_Enh_Wrk].[v_ForecastSnapshotWeekly] AS
SELECT
    CAST(TRIM(dfcItem)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(dfcWarehouse)        AS VARCHAR(50))   AS WarehouseCode,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotDate,
    CAST(dfcSnapshot               AS DATE)          AS SnapshotWeekEndingDate,
    CAST(dfcFiscalMonth            AS INT)           AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth/100 AS INT),
        CAST(dfcFiscalMonth%100 AS INT),
        1) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(ISNULL(CAST(dfcResultantForecast AS DECIMAL(18,4)), 0)
           + ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS ForecastQty,
    CAST(SUM(ISNULL(CAST(dfcPromotionalLift   AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS PromoLiftQty,
    CAST('Enterprise_Lakehouse'           AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily'    AS VARCHAR(128)) AS SourceTable,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM [$(Databricks)].[SupplyChain_Enh].[DemandForecastSnapshotDaily]
WHERE dfcItem IS NOT NULL AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND CAST(dfcFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
  AND dfcSnapshot IS NOT NULL
  -- Weekly reporting grain: keep Saturday captures only.
  AND DATEDIFF(day, CAST('19000106' AS DATE), CAST(dfcSnapshot AS DATE)) % 7 = 0
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth;
