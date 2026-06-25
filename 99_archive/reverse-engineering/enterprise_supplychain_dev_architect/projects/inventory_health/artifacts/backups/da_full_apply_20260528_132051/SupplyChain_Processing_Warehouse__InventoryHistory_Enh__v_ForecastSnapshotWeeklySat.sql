-- ---------------------------------------------------------------------
-- DA forecast candidate:
--   ForecastQty = ResultantForecast + PromotionalLift.
--   Keep this as a candidate because the current production table has a
--   PermComptQty column and downstream schema impact must be verified first.
-- ---------------------------------------------------------------------
CREATE   VIEW InventoryHistory_Enh.v_ForecastSnapshotWeeklySat AS
SELECT
    CAST(TRIM(dfcItem) AS VARCHAR(50))          AS ItemSku,
    CAST(TRIM(dfcWarehouse) AS VARCHAR(50))     AS WarehouseCode,
    CAST(dfcSnapshot AS DATE)                   AS SnapshotDate,
    CAST(dfcFiscalMonth AS INT)                 AS FiscalMonth,
    CAST(DATEFROMPARTS(
        CAST(dfcFiscalMonth / 100 AS INT),
        CAST(dfcFiscalMonth % 100 AS INT),
        1
    ) AS DATE)                                  AS FiscalMonthDate,
    CAST(SUM(
        ISNULL(CAST(dfcResultantForecast AS DECIMAL(18,4)), 0)
      + ISNULL(CAST(dfcPromotionalLift AS DECIMAL(18,4)), 0)
    ) AS DECIMAL(18,4))                         AS ForecastQty,
    CAST(SUM(ISNULL(CAST(dfcPromotionalLift AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4)) AS PromoLiftQty,
    CAST('Staging_Wrk' AS VARCHAR(64))          AS SourceSystem,
    CAST('DemandForecastSnapshotDaily (Sat)' AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.DemandForecastSnapshotDaily
WHERE dfcItem IS NOT NULL
  AND dfcWarehouse IS NOT NULL
  AND dfcFiscalMonth IS NOT NULL
  AND CAST(dfcFiscalMonth AS INT) BETWEEN 190001 AND 209912
  AND CAST(dfcFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
  AND dfcSnapshot IS NOT NULL
  AND DATEDIFF(day, CAST('19000106' AS DATE), CAST(dfcSnapshot AS DATE)) % 7 = 0
GROUP BY
    TRIM(dfcItem),
    TRIM(dfcWarehouse),
    CAST(dfcSnapshot AS DATE),
    dfcFiscalMonth;