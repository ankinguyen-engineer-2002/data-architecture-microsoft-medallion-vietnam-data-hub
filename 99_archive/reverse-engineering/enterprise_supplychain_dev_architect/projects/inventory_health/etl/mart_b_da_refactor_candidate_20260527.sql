-- SUPERSEDED 2026-05-28: production now uses direct SalesHistory_Enh.v_InvoiceDetailLineLevel in helpers/COGS; do not deploy this candidate alias script.
-- =====================================================================
-- Mart B Inventory Health - DA-first refactor candidate
-- Created: 2026-05-27
--
-- Purpose:
--   Build additive candidate views for the DA Silver_Check refactor without
--   replacing production tables/views.
--
-- Source of truth:
--   1. artifacts/source_inputs/inventory_health_project_resources_2026-06-02.xlsx, sheet Silver_Check
--   2. artifacts/source_inputs/inventoryhistory_enh_silver_view_sql_export_2026-06-02.md
--   3. Live 2026-05-26 post-fix architecture:
--      InventorySnapshotWeeklyFactBase remains the helper/fact base.
--
-- Safety:
--   - This script creates/updates *_DARefactorCandidate views only.
--   - It does not DROP, TRUNCATE, DELETE, or replace production objects.
--   - Do not swap production registry/view names from this script without
--     explicit approval.
-- =====================================================================


-- ---------------------------------------------------------------------
-- P0 candidate: replace Mart B SalesShipment source with Mart A invoice
-- silver view. Same Mart B output contract as InventoryHistory_Enh.SalesShipment.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate AS
SELECT
    CAST(InvoiceID AS DECIMAL(18,0))            AS InvoiceNumber,
    CAST(ItemSequenceNum AS DECIMAL(18,0))      AS ItemSequence,
    CAST(TRIM(ItemSKU) AS VARCHAR(50))          AS ItemSku,
    CAST(TRIM(WarehouseCode) AS VARCHAR(50))    AS WarehouseCode,
    CAST(InvoiceDate AS DATE)                   AS InvoiceDate,
    CAST(OrderDate AS DATE)                     AS OrderDate,
    CAST(QtyShipped AS DECIMAL(18,4))           AS QuantityShipped,
    CAST(QtyOrdered AS DECIMAL(18,4))           AS QuantityOrdered,
    CAST(AmtPrice AS DECIMAL(18,4))             AS Price,
    CAST('SalesHistory_Enh' AS VARCHAR(64))     AS SourceSystem,
    CAST('v_InvoiceDetailLineLevel' AS VARCHAR(128)) AS SourceTable
FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
WHERE ItemSKU IS NOT NULL
  AND WarehouseCode IS NOT NULL
  AND TRIM(ItemSKU) <> ''
  AND TRIM(WarehouseCode) <> '';
GO


-- ---------------------------------------------------------------------
-- DA forecast candidate:
--   ForecastQty = ResultantForecast + PromotionalLift.
--   Keep this as a candidate because the current production table has a
--   PermComptQty column and downstream schema impact must be verified first.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_ForecastSnapshotWeeklySat_DARefactorCandidate AS
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
FROM Staging.DemandForecastSnapshotDaily
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
GO


-- ---------------------------------------------------------------------
-- AWD candidate:
--   - Preserves the 2026-05-26 FactBase path.
--   - Uses DA 3 fiscal month forecast horizon and dependent demand roll-up.
--   - Uses the candidate SalesShipment alias for historical fallback.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_AwdHelper_DARefactorCandidate AS
WITH current_inventory AS (
    SELECT
        CAST(TRIM(b.ITNBR) AS VARCHAR(50))      AS ItemSku,
        CAST(TRIM(b.HOUSE) AS VARCHAR(50))      AS WarehouseCode,
        CAST(b.MOHTQ AS DECIMAL(18,4))          AS OnHandQty,
        CAST(TRIM(b.ITCLS) AS VARCHAR(50))      AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE) AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
),
asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate,
        DATEDIFF(day,
            DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1),
            DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1))
        ) AS HorizonDays
    FROM asof_dates
),
item_wh AS (
    SELECT DISTINCT ItemSku, WarehouseCode FROM current_inventory
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
),
fcst_recent AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonthDate,
        ForecastQty
    FROM InventoryHistory_Enh.v_ForecastSnapshotWeeklySat_DARefactorCandidate
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
      AND FiscalMonthDate IS NOT NULL
),
latest_snap AS (
    SELECT
        f.ItemSku,
        f.WarehouseCode,
        a.AsOfDate,
        MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a
      ON f.SnapshotDate <= a.AsOfDate
     AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
inventory_source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(NULLIF(TRIM(dinMakeBuyCode), '') AS VARCHAR(10)) AS MakeBuyCode,
        CAST(NULLIF(TRIM(dinSource1), '') AS VARCHAR(50)) AS SourceWarehouseCode,
        ROW_NUMBER() OVER (
            PARTITION BY
                CAST(TRIM(dinItem) AS VARCHAR(50)),
                CAST(TRIM(dinWarehouse) AS VARCHAR(50)),
                CAST(dinSnapshot AS DATE),
                CAST(dinFiscalMonth AS INT)
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotDaily]
    WHERE dinItem IS NOT NULL
      AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> ''
      AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND CAST(dinFiscalMonth AS INT) BETWEEN 190001 AND 209912
      AND CAST(dinFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
      AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
),
inventory_source AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotDate) AS LatestInventorySnapshotDate
    FROM inventory_source_rows isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)
    WHERE (isw.MakeBuyCode IS NOT NULL
       OR isw.SourceWarehouseCode IS NOT NULL)
      AND isw.rn = 1
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
source_map AS (
    SELECT
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate,
        CAST(MAX(NULLIF(TRIM(isw.MakeBuyCode), '')) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(MAX(NULLIF(TRIM(isw.SourceWarehouseCode), '')) AS VARCHAR(50)) AS SourceWarehouseCode
    FROM inventory_source src
    JOIN inventory_source_rows isw
      ON isw.ItemSku = src.ItemSku
     AND isw.WarehouseCode = src.WarehouseCode
     AND isw.SnapshotDate = src.LatestInventorySnapshotDate
     AND isw.rn = 1
    GROUP BY src.ItemSku, src.WarehouseCode, src.AsOfDate
),
forecast_components AS (
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        SUM(f.ForecastQty) AS ThreeMoForecastQty,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
      ON f.ItemSku = ls.ItemSku
     AND f.WarehouseCode = ls.WarehouseCode
     AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
      ON a.AsOfDate = ls.AsOfDate
     AND f.FiscalMonthDate >= a.HorizonStartDate
     AND f.FiscalMonthDate < a.HorizonEndDate
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate

    UNION ALL

    SELECT
        ls.ItemSku,
        CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)) AS WarehouseCode,
        ls.AsOfDate,
        CAST(0 AS DECIMAL(18,4)) AS ThreeMoForecastQty,
        SUM(f.ForecastQty) AS ThreeMoDependentDemandQty
    FROM latest_snap ls
    JOIN fcst_recent f
      ON f.ItemSku = ls.ItemSku
     AND f.WarehouseCode = ls.WarehouseCode
     AND f.SnapshotDate = ls.LatestSnapshotDate
    JOIN asof a
      ON a.AsOfDate = ls.AsOfDate
     AND f.FiscalMonthDate >= a.HorizonStartDate
     AND f.FiscalMonthDate < a.HorizonEndDate
    JOIN source_map sm
      ON sm.ItemSku = f.ItemSku
     AND sm.WarehouseCode = f.WarehouseCode
     AND sm.AsOfDate = ls.AsOfDate
    WHERE TRIM(sm.MakeBuyCode) = 'X'
      AND NULLIF(TRIM(sm.SourceWarehouseCode), '') IS NOT NULL
    GROUP BY ls.ItemSku, CAST(NULLIF(TRIM(sm.SourceWarehouseCode), '') AS VARCHAR(50)), ls.AsOfDate
),
demand_3mo AS (
    SELECT
        ItemSku,
        WarehouseCode,
        AsOfDate,
        SUM(ThreeMoForecastQty) AS ThreeMoForecastQty,
        SUM(ThreeMoDependentDemandQty) AS ThreeMoDependentDemandQty,
        SUM(ThreeMoForecastQty + ThreeMoDependentDemandQty) AS ThreeMoTotalDemandQty
    FROM forecast_components
    WHERE WarehouseCode IS NOT NULL
    GROUP BY ItemSku, WarehouseCode, AsOfDate
),
hist13w AS (
    SELECT
        s.ItemSku,
        s.WarehouseCode,
        a.AsOfDate,
        SUM(CAST(s.QuantityShipped AS DECIMAL(18,4))) AS Hist13WQty
    FROM InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate s
    JOIN asof a
      ON s.InvoiceDate > DATEADD(week, -13, a.AsOfDate)
     AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(iw.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(iw.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(a.AsOfDate AS DATE) AS AsOfDate,
    CAST(a.HorizonStartDate AS DATE) AS HorizonStartDate,
    CAST(a.HorizonEndDate AS DATE) AS HorizonEndDate,
    CAST(a.HorizonDays AS INT) AS HorizonDays,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) AS DECIMAL(18,4)) AS ThreeMoForecastQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoDependentDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS ThreeMoTotalDemandQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) AS DECIMAL(18,4)) AS Fwd13WForecastQty,
    CAST(ISNULL(h.Hist13WQty, 0) AS DECIMAL(18,4)) AS Hist13WShippedQty,
    CAST(ISNULL(d.ThreeMoForecastQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DailyFcstQty,
    CAST(ISNULL(d.ThreeMoDependentDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS DependentDemandDailyQty,
    CAST(ISNULL(d.ThreeMoTotalDemandQty, 0) / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4)) AS TotalDemandDailyQty,
    CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4)) AS Hist13WShippedDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN d.ThreeMoTotalDemandQty / 13.0
        ELSE ISNULL(h.Hist13WQty, 0) / 13.0
    END AS DECIMAL(18,4)) AS AwdQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN d.ThreeMoTotalDemandQty / NULLIF(a.HorizonDays, 0)
        ELSE ISNULL(h.Hist13WQty, 0) / 91.0
    END AS DECIMAL(18,4)) AS AwdDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
             AND ISNULL(d.ThreeMoDependentDemandQty, 0) > 0 THEN 'Forecast+Dependent'
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN 'Forecast'
        ELSE 'HistoricalFallback'
    END AS VARCHAR(20)) AS AwdSource
FROM item_wh iw
CROSS JOIN asof a
LEFT JOIN demand_3mo d
  ON d.ItemSku = iw.ItemSku
 AND d.WarehouseCode = iw.WarehouseCode
 AND d.AsOfDate = a.AsOfDate
LEFT JOIN hist13w h
  ON h.ItemSku = iw.ItemSku
 AND h.WarehouseCode = iw.WarehouseCode
 AND h.AsOfDate = a.AsOfDate
WHERE COALESCE(d.ThreeMoTotalDemandQty, h.Hist13WQty) IS NOT NULL;
GO


-- ---------------------------------------------------------------------
-- Last invoice candidate: DA as-of behavior + Mart A invoice source.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LastInvoiceHelper_DARefactorCandidate AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(s.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(a.AsOfDate AS DATE) AS AsOfDate,
    CAST(MAX(s.InvoiceDate) AS DATE) AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate s
JOIN asof a
  ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate;
GO


-- ---------------------------------------------------------------------
-- Movement flag candidate: DA as-of behavior + Mart A invoice source.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_MovementFlagHelper_DARefactorCandidate AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
    WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
moves AS (
    SELECT
        s.ItemSku,
        s.WarehouseCode,
        a.AsOfDate,
        MAX(CASE
            WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
             AND s.InvoiceDate <= a.AsOfDate THEN 1
            ELSE 0
        END) AS HasMovementLast17W,
        COUNT(*) AS MovementCountLast17W
    FROM InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate s
    JOIN asof a
      ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
     AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate AS DATE) AS AsOfDate,
    CAST(HasMovementLast17W AS BIT) AS HasMovementLast17W,
    CAST(MovementCountLast17W AS INT) AS MovementCountLast17W
FROM moves;
GO


-- ---------------------------------------------------------------------
-- Safety stock candidate: next 3 fiscal months, fallback prior 13 weeks.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_SafetyStockHelper_DARefactorCandidate AS
WITH asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase
),
asof AS (
    SELECT
        AsOfDate,
        DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1) AS HorizonStartDate,
        DATEADD(month, 3, DATEFROMPARTS(YEAR(AsOfDate), MONTH(AsOfDate), 1)) AS HorizonEndDate
    FROM asof_dates
),
latest_snap AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotDate) AS LatestSnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
fiscal_ss AS (
    SELECT
        ls.ItemSku,
        ls.WarehouseCode,
        ls.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM latest_snap ls
    JOIN asof a
      ON a.AsOfDate = ls.AsOfDate
    JOIN InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
      ON isw.ItemSku = ls.ItemSku
     AND isw.WarehouseCode = ls.WarehouseCode
     AND isw.SnapshotDate = ls.LatestSnapshotDate
     AND isw.FiscalMonthDate >= a.HorizonStartDate
     AND isw.FiscalMonthDate < a.HorizonEndDate
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate
),
fallback_ss AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        AVG(isw.SafetyStockTarget) AS SafetyStockTarget,
        COUNT(*) AS SnapshotCount
    FROM InventoryHistory_Enh.InventorySnapshotWeeklyFactBase isw
    JOIN asof a
      ON isw.SnapshotDate <= a.AsOfDate
     AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
keys AS (
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fiscal_ss
    UNION
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fallback_ss
)
SELECT
    CAST(k.ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(k.WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(k.AsOfDate AS DATE) AS AsOfDate,
    CAST(COALESCE(f.SafetyStockTarget, fb.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COALESCE(f.SnapshotCount, fb.SnapshotCount) AS INT) AS SnapshotCount,
    CAST(CASE
        WHEN f.SafetyStockTarget IS NOT NULL THEN 'Next3FiscalMonths'
        ELSE 'Historical13W'
    END AS VARCHAR(30)) AS SafetyStockSource
FROM keys k
LEFT JOIN fiscal_ss f
  ON f.ItemSku = k.ItemSku
 AND f.WarehouseCode = k.WarehouseCode
 AND f.AsOfDate = k.AsOfDate
LEFT JOIN fallback_ss fb
  ON fb.ItemSku = k.ItemSku
 AND fb.WarehouseCode = k.WarehouseCode
 AND fb.AsOfDate = k.AsOfDate;
GO


-- ---------------------------------------------------------------------
-- Holding transfer candidate: remove cancel filter per DA.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_HoldingTransferSnapshotDaily_DARefactorCandidate AS
WITH holding_transfer AS (
    SELECT
        TransferNumber,
        ItemSku,
        WarehouseCode,
        SourceWarehouseCode,
        ReceivingWarehouseCode,
        ShipDateKey,
        ShipDate,
        ShipWeekEndingDate,
        DueDateKey,
        DueDate,
        DueWeekEndingDate,
        HeaderComment,
        DetailComment,
        TransferQty,
        ShippedQty,
        TotalShippedQty,
        ExpediteCode,
        FirmCode,
        TransferCube,
        HeaderStatus,
        CancelFlag
    FROM (
        SELECT
            TRIM(d.DTFRNO) AS TransferNumber,
            TRIM(d.DITNBR) AS ItemSku,
            TRIM(h.HFHOUS) AS WarehouseCode,
            TRIM(h.HFHOUS) AS SourceWarehouseCode,
            TRIM(h.HTHOUS) AS ReceivingWarehouseCode,
            CAST(h.HSHDTE AS INT) AS ShipDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112) AS ShipDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)
            ) AS DATE) AS ShipWeekEndingDate,
            CAST(h.HDLDTE AS INT) AS DueDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112) AS DueDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)
            ) AS DATE) AS DueWeekEndingDate,
            CAST(h.HTRCMT AS VARCHAR(200)) AS HeaderComment,
            CAST(d.DCOMNT AS VARCHAR(200)) AS DetailComment,
            CAST(d.DTFRQT AS DECIMAL(18,4)) AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4)) AS ShippedQty,
            CAST(d.DTSHPQ AS DECIMAL(18,4)) AS TotalShippedQty,
            CAST(d.DEXPED AS VARCHAR(20)) AS ExpediteCode,
            CAST(d.DFIRMC AS VARCHAR(20)) AS FirmCode,
            CAST(d.DCUBES AS DECIMAL(18,4)) AS TransferCube,
            TRIM(h.HSTATS) AS HeaderStatus,
            TRIM(h.HCANCL) AS CancelFlag,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
                ORDER BY h.HDLDTE DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
          ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
          AND d.DITNBR IS NOT NULL
          AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> ''
          AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE) AS SnapshotDate,
    CAST(TransferNumber AS VARCHAR(50)) AS TransferNumber,
    CAST(ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS INT) AS TransferLine,
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(SourceWarehouseCode AS VARCHAR(50)) AS SourceWarehouseCode,
    CAST(ReceivingWarehouseCode AS VARCHAR(50)) AS ReceivingWarehouseCode,
    CAST(ShipDateKey AS INT) AS ShipDateKey,
    CAST(ShipDate AS DATE) AS ShipDate,
    CAST(ShipWeekEndingDate AS DATE) AS ShipWeekEndingDate,
    CAST(DueDateKey AS INT) AS DueDateKey,
    CAST(DueDate AS DATE) AS DueDate,
    CAST(DueWeekEndingDate AS DATE) AS DueWeekEndingDate,
    CAST(HeaderComment AS VARCHAR(200)) AS HeaderComment,
    CAST(DetailComment AS VARCHAR(200)) AS DetailComment,
    CAST(TransferQty AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TotalShippedQty AS DECIMAL(18,4)) AS TotalShippedQty,
    CAST(ExpediteCode AS VARCHAR(20)) AS ExpediteCode,
    CAST(FirmCode AS VARCHAR(20)) AS FirmCode,
    CAST(TransferCube AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus AS VARCHAR(10)) AS HeaderStatus,
    CAST(CancelFlag AS VARCHAR(10)) AS CancelFlag,
    CAST('Manufacturing_Inventory_AFI' AS VARCHAR(64)) AS SourceSystem,
    CAST('TFRDTL+TFRHDR' AS VARCHAR(128)) AS SourceTable
FROM holding_transfer;
GO


-- ---------------------------------------------------------------------
-- Purchase order snapshot candidate:
--   Remove PoMaster vendor join condition per DA.
--   Preserve VendorNumber in the grain because PoDetail reuses
--   (PoNumber, PoLine) across vendors.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily_DARefactorCandidate AS
WITH purchase_order AS (
    SELECT
        r.PoNumber,
        r.PoLine,
        r.VendorNumber,
        r.ItemSku,
        r.WarehouseCode,
        r.StatusCode,
        r.StockQty,
        r.OrderedQty,
        r.InTransitQtySource,
        r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa AS DATE) AS EstimatedArrivalDate,
        CAST(h.pometd AS DATE) AS EstimatedDepartureDate,
        CAST(h.pomdue AS DATE) AS PromisedReceiptDate,
        CAST('Enterprise_Lakehouse' AS VARCHAR(64)) AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)' AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum) AS PoNumber,
            CAST(poditemsequence AS INT) AS PoLine,
            TRIM(podvendornum) AS VendorNumber,
            TRIM(poditemnum) AS ItemSku,
            TRIM(podwarehouse) AS WarehouseCode,
            CAST(podstatuscode AS VARCHAR(10)) AS StatusCode,
            CAST(podstockqty AS DECIMAL(18,4)) AS StockQty,
            CAST(podqtyordered AS DECIMAL(18,4)) AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4)) AS InTransitQtySource,
            CAST(podduedate AS DATE) AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL
          AND podwarehouse IS NOT NULL
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
      ON TRIM(h.pomordernum) = r.PoNumber
    WHERE r.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE) AS SnapshotDate,
    CAST(PoNumber AS VARCHAR(50)) AS PoNumber,
    CAST(PoLine AS INT) AS PoLine,
    CAST(VendorNumber AS VARCHAR(50)) AS VendorNumber,
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(StatusCode AS VARCHAR(10)) AS StatusCode,
    CAST(StockQty AS DECIMAL(18,4)) AS StockQty,
    CAST(OrderedQty AS DECIMAL(18,4)) AS OrderedQty,
    CAST(InTransitQtySource AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(POOnOrderQty AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(POInTransitQty AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(TotalOpenPOQty AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(DueDate AS DATE) AS DueDate,
    CAST(EstimatedArrivalDate AS DATE) AS EstimatedArrivalDate,
    CAST(EstimatedDepartureDate AS DATE) AS EstimatedDepartureDate,
    CAST(SourceSystem AS VARCHAR(64)) AS SourceSystem,
    CAST(SourceTable AS VARCHAR(128)) AS SourceTable
FROM purchase_order;
GO


-- ---------------------------------------------------------------------
-- Candidate QC queries.
-- Run after creating candidate views.
-- ---------------------------------------------------------------------

-- SalesShipment parity summary.
SELECT
    'production' AS dataset,
    COUNT_BIG(*) AS row_count,
    MIN(InvoiceDate) AS min_invoice_date,
    MAX(InvoiceDate) AS max_invoice_date,
    SUM(CAST(QuantityShipped AS DECIMAL(38,4))) AS qty_shipped,
    SUM(CAST(QuantityOrdered AS DECIMAL(38,4))) AS qty_ordered,
    SUM(CAST(Price AS DECIMAL(38,4))) AS price_sum
FROM InventoryHistory_Enh.SalesShipment
UNION ALL
SELECT
    'candidate' AS dataset,
    COUNT_BIG(*) AS row_count,
    MIN(InvoiceDate) AS min_invoice_date,
    MAX(InvoiceDate) AS max_invoice_date,
    SUM(CAST(QuantityShipped AS DECIMAL(38,4))) AS qty_shipped,
    SUM(CAST(QuantityOrdered AS DECIMAL(38,4))) AS qty_ordered,
    SUM(CAST(Price AS DECIMAL(38,4))) AS price_sum
FROM InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate;


-- Candidate grain duplicate checks.
WITH checks AS (
    SELECT 'SalesShipment candidate' AS object_name, COUNT_BIG(*) AS raw_rows, COUNT_BIG(DISTINCT CONCAT(InvoiceNumber, '|', ItemSequence)) AS distinct_keys
    FROM InventoryHistory_Enh.v_SalesShipment_DARefactorCandidate
    UNION ALL
    SELECT 'AwdHelper candidate', COUNT_BIG(*), COUNT_BIG(DISTINCT CONCAT(AsOfDate, '|', ItemSku, '|', WarehouseCode))
    FROM InventoryHistory_Enh.v_AwdHelper_DARefactorCandidate
    UNION ALL
    SELECT 'LastInvoiceHelper candidate', COUNT_BIG(*), COUNT_BIG(DISTINCT CONCAT(AsOfDate, '|', ItemSku, '|', WarehouseCode))
    FROM InventoryHistory_Enh.v_LastInvoiceHelper_DARefactorCandidate
    UNION ALL
    SELECT 'MovementFlagHelper candidate', COUNT_BIG(*), COUNT_BIG(DISTINCT CONCAT(AsOfDate, '|', ItemSku, '|', WarehouseCode))
    FROM InventoryHistory_Enh.v_MovementFlagHelper_DARefactorCandidate
    UNION ALL
    SELECT 'SafetyStockHelper candidate', COUNT_BIG(*), COUNT_BIG(DISTINCT CONCAT(AsOfDate, '|', ItemSku, '|', WarehouseCode))
    FROM InventoryHistory_Enh.v_SafetyStockHelper_DARefactorCandidate
)
SELECT
    object_name,
    raw_rows,
    distinct_keys,
    raw_rows - distinct_keys AS duplicate_extra_rows
FROM checks;


-- Purchase order candidate grain check. Expected duplicate_extra_rows = 0.
WITH po_grain AS (
    SELECT
        SnapshotDate,
        PoNumber,
        PoLine,
        VendorNumber,
        COUNT_BIG(*) AS row_count
    FROM InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily_DARefactorCandidate
    GROUP BY SnapshotDate, PoNumber, PoLine, VendorNumber
)
SELECT
    SUM(row_count) AS raw_rows,
    COUNT_BIG(*) AS grain_rows,
    SUM(row_count) - COUNT_BIG(*) AS duplicate_extra_rows,
    MAX(row_count) AS max_rows_per_key
FROM po_grain;


-- Snapshot history retention check for existing production datekey tables.
SELECT
    'ManufacturingOrderSnapshotDaily' AS table_name,
    COUNT_BIG(*) AS row_count,
    COUNT(DISTINCT SnapshotDate) AS distinct_snapshot_dates,
    MIN(SnapshotDate) AS min_snapshot_date,
    MAX(SnapshotDate) AS max_snapshot_date
FROM InventoryHistory_Enh.ManufacturingOrderSnapshotDaily
UNION ALL
SELECT
    'PurchaseOrderSnapshotDaily',
    COUNT_BIG(*),
    COUNT(DISTINCT SnapshotDate),
    MIN(SnapshotDate),
    MAX(SnapshotDate)
FROM InventoryHistory_Enh.PurchaseOrderSnapshotDaily
UNION ALL
SELECT
    'HoldingTransferSnapshotDaily',
    COUNT_BIG(*),
    COUNT(DISTINCT SnapshotDate),
    MIN(SnapshotDate),
    MAX(SnapshotDate)
FROM InventoryHistory_Enh.HoldingTransferSnapshotDaily;
