# InventoryHistory_Enh Silver View SQL Export

- Workspace: `Enterprise SupplyChain-Dev`
- Warehouse: `SupplyChain_Processing_Warehouse`
- Schema: `InventoryHistory_Enh`
- SQL endpoint: `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com`
- Export source: `sys.views` + `sys.sql_modules`
- Exported at: `2026-05-22 09:09:26 +07:00`
- View count: `13`

## Views

- [`InventoryHistory_Enh.v_AwdHelper`](#inventoryhistory-enhv-awdhelper)
- [`InventoryHistory_Enh.v_ForecastSnapshotWeekly`](#inventoryhistory-enhv-forecastsnapshotweekly)
- [`InventoryHistory_Enh.v_HoldingTransferSnapshotDaily`](#inventoryhistory-enhv-holdingtransfersnapshotdaily)
- [`InventoryHistory_Enh.v_InventorySnapshotWeekly`](#inventoryhistory-enhv-inventorysnapshotweekly)
- [`InventoryHistory_Enh.v_ItemBalanceHistorical`](#inventoryhistory-enhv-itembalancehistorical)
- [`InventoryHistory_Enh.v_LastInvoiceHelper`](#inventoryhistory-enhv-lastinvoicehelper)
- [`InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly`](#inventoryhistory-enhv-logilityitemstatussnapshotweekly)
- [`InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily`](#inventoryhistory-enhv-manufacturingordersnapshotdaily)
- [`InventoryHistory_Enh.v_MovementFlagHelper`](#inventoryhistory-enhv-movementflaghelper)
- [`InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily`](#inventoryhistory-enhv-purchaseordersnapshotdaily)
- [`InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical`](#inventoryhistory-enhv-purchaseordersnapshothistorical)
- [`InventoryHistory_Enh.v_SafetyStockHelper`](#inventoryhistory-enhv-safetystockhelper)
- [`InventoryHistory_Enh.v_SalesShipment`](#inventoryhistory-enhv-salesshipment)

## `InventoryHistory_Enh.v_AwdHelper`

```sql
CREATE   VIEW InventoryHistory_Enh.v_AwdHelper AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   Forecast demand = next 3 fiscal months, not one forecast week.
--   DailyFcstQty = ThreeMoForecastQty / HorizonDays.
--   Dependent demand rolls buy/source-dependent demand to source warehouse via InventorySnapshotWeekly.SourceWarehouseCode.
--   TotalDemandDailyQty = DailyFcstQty + DependentDemandDailyQty.
--   AwdQty is weekly-equivalent demand for existing Gold WeeksOfSupply.
--   AwdDailyQty is daily demand for DaysOfSupply = OnHandQty / AwdDailyQty.
--   If forecast demand is zero or missing, fallback to 13-week shipped demand.
-- 2026-05-20 FIX (Giang #4): three-month forecast uses FiscalMonthDate (forecast period)
-- 2026-05-21 PERF OPTIMIZATION: limit latest_snap lookback to 13 weeks of forecast snapshots.
-- Pre-fix: 153M ForecastSnapshotWeekly × 100+ AsOfDates → huge intermediate JOIN.
-- Post-fix: only join snapshots within 13W of each AsOfDate → ~13× weekly snapshots scanned per AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH _InventoryCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.InventoryCurrent (dropped entity)
    SELECT
        CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
        CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
        CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
        CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
    WHERE LEFT(TRIM(b.ITCLS), 1) = 'Z'
      AND RIGHT(TRIM(b.ITCLS), 1) = 'K' -- FG
),
asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE)) -- Giang Historical weekly 3 years
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
    SELECT DISTINCT ItemSku, WarehouseCode FROM _InventoryCurrent
    UNION
    SELECT DISTINCT ItemSku, WarehouseCode FROM InventoryHistory_Enh.InventorySnapshotWeekly
),
-- Pre-limit ForecastSnapshotWeekly to last 13 weeks of snapshots (weekly cadence → ~13 rows per Item×WH)
fcst_recent AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        FiscalMonthDate,
        ForecastQty
    FROM InventoryHistory_Enh.ForecastSnapshotWeekly
    WHERE SnapshotDate >= DATEADD(week, -156, CAST(SYSUTCDATETIME() AS DATE))
      AND SnapshotDate <= CAST(SYSUTCDATETIME() AS DATE)
      AND FiscalMonthDate IS NOT NULL
),
latest_snap AS (
    SELECT
        f.ItemSku, f.WarehouseCode, a.AsOfDate,
        MAX(f.SnapshotDate) AS LatestSnapshotDate
    FROM fcst_recent f
    JOIN asof a
         ON f.SnapshotDate <= a.AsOfDate
        AND f.SnapshotDate >= DATEADD(week, -13, a.AsOfDate)   -- only look back 13W of weekly snapshots
    GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
),
inventory_source AS (
    SELECT
        isw.ItemSku,
        isw.WarehouseCode,
        a.AsOfDate,
        MAX(isw.SnapshotWeekEndingDate) AS LatestInventorySnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate >= DATEADD(week, -13, a.AsOfDate)
    WHERE isw.MakeBuyCode IS NOT NULL
       OR isw.SourceWarehouseCode IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
source_map AS (
    -- Reference: Inventory Health Dataset.sql #DPD.
    -- Buy/source-dependent demand is identified by MBX='X' and rolled to dinSource1.
    -- Collapse fiscal-month inventory rows to one mapping row per ItemSku + WarehouseCode + AsOfDate.
    -- Assumption: MakeBuyCode and SourceWarehouseCode are stable across the 3 fiscal months in scope.
    SELECT
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate,
        CAST(MAX(NULLIF(TRIM(isw.MakeBuyCode), '')) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(MAX(NULLIF(TRIM(isw.SourceWarehouseCode), '')) AS VARCHAR(50)) AS SourceWarehouseCode
    FROM inventory_source src
    JOIN InventoryHistory_Enh.InventorySnapshotWeekly isw
         ON isw.ItemSku = src.ItemSku
        AND isw.WarehouseCode = src.WarehouseCode
        AND isw.SnapshotWeekEndingDate = src.LatestInventorySnapshotDate
    GROUP BY
        src.ItemSku,
        src.WarehouseCode,
        src.AsOfDate
),
forecast_components AS (
    -- Direct forecast demand stays at the forecast warehouse.
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
        AND f.FiscalMonthDate <  a.HorizonEndDate
    GROUP BY ls.ItemSku, ls.WarehouseCode, ls.AsOfDate

    UNION ALL

    -- Dependent demand rolls from buy/source-dependent warehouse to source warehouse.
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
        AND f.FiscalMonthDate <  a.HorizonEndDate
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
        TRIM(s.ItemSKU)      AS ItemSku,
        TRIM(s.WarehouseCode) AS WarehouseCode,
        a.AsOfDate,
        SUM(CAST(s.QtyShipped AS DECIMAL(18,4))) AS Hist13WQty
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel s
    JOIN asof a
        ON s.InvoiceDate > DATEADD(WEEK, -13, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    WHERE s.ItemSKU IS NOT NULL
      AND s.WarehouseCode IS NOT NULL
      AND TRIM(s.ItemSKU) <> ''
      AND TRIM(s.WarehouseCode) <> ''
      AND s.InvoiceDate IS NOT NULL
    GROUP BY
        TRIM(s.ItemSKU),
        TRIM(s.WarehouseCode),
        a.AsOfDate
)
SELECT
    CAST(iw.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(iw.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate        AS DATE)          AS AsOfDate,
    CAST(a.HorizonStartDate AS DATE)         AS HorizonStartDate,
    CAST(a.HorizonEndDate   AS DATE)         AS HorizonEndDate,
    CAST(a.HorizonDays      AS INT)          AS HorizonDays,
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
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / 13.0 AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 13.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
        THEN CAST(d.ThreeMoTotalDemandQty / NULLIF(a.HorizonDays, 0) AS DECIMAL(18,4))
        ELSE CAST(ISNULL(h.Hist13WQty, 0) / 91.0 AS DECIMAL(18,4))
    END AS DECIMAL(18,4))                     AS AwdDailyQty,
    CAST(CASE
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0
             AND ISNULL(d.ThreeMoDependentDemandQty, 0) > 0 THEN 'Forecast+Dependent'
        WHEN ISNULL(d.ThreeMoTotalDemandQty, 0) > 0 THEN 'Forecast'
        ELSE 'HistoricalFallback'
    END AS VARCHAR(20))                       AS AwdSource
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
WHERE COALESCE(d.ThreeMoTotalDemandQty, h.Hist13WQty) IS NOT NULL
GO
```

## `InventoryHistory_Enh.v_ForecastSnapshotWeekly`

```sql
CREATE   VIEW InventoryHistory_Enh.v_ForecastSnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   SnapshotDate is the capture date; FiscalMonthDate is the forecast period.
--   Weekly reporting uses Saturday captures from the daily staging source.
--   Forecast demand is consumed downstream as next 3 fiscal months, not a single week.
--   Reference: Inventory Health Dataset.sql uses ResultantForecast + PromotionalLift for demand.
-- 2026-05-20 FIX (Giang #2+#3):
--   dfcSnapshot is CAPTURE DATE, not week-ending → renamed alias WeekEndingDate → SnapshotDate
--   Added FiscalMonth + FiscalMonthDate dimensions (36 forward months per snapshot)
-- Grain: (ItemSku, WarehouseCode, SnapshotDate, FiscalMonth)
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
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS PermComptQty, --Giang: hiện ko sử dụng
    -- CAST(SUM(CAST(dfcPermComptQty      AS DECIMAL(18,4))) AS DECIMAL(18,4)) AS DependentForecastQty, --Giang: sai
    CAST('Staging_Wrk'                    AS VARCHAR(64))  AS SourceSystem,
    CAST('DemandForecastSnapshotDaily'    AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.DemandForecastSnapshotDaily
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
    dfcFiscalMonth
GO
```

## `InventoryHistory_Enh.v_HoldingTransferSnapshotDaily`

```sql
-- ---- InventoryHistory_Enh.v_HoldingTransferSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_HoldingTransferSnapshotDaily AS
WITH _HoldingTransfer AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.HoldingTransfer
    -- Reference: etl/Holding Transfers.sql.
    -- Business signal: same-warehouse transfer (HFHOUS = HTHOUS) is an on-hold candidate.
    -- Current metric keeps active/non-cancelled transfers for OnHoldQty compatibility.
    SELECT
        TransferNumber, ItemSku, WarehouseCode, SourceWarehouseCode, ReceivingWarehouseCode,
        ShipDateKey, ShipDate, ShipWeekEndingDate, DueDateKey, DueDate, DueWeekEndingDate,
        HeaderComment, DetailComment, TransferQty, ShippedQty, TotalShippedQty,
        ExpediteCode, FirmCode, TransferCube, HeaderStatus, CancelFlag
    FROM (
        SELECT
            TRIM(d.DTFRNO)                       AS TransferNumber,
            TRIM(d.DITNBR)                       AS ItemSku,
            TRIM(h.HFHOUS)                       AS WarehouseCode,
            TRIM(h.HFHOUS)                       AS SourceWarehouseCode,
            TRIM(h.HTHOUS)                       AS ReceivingWarehouseCode,
            CAST(h.HSHDTE AS INT)                AS ShipDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112) AS ShipDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) AS DATE) AS ShipWeekEndingDate,
            CAST(h.HDLDTE AS INT)                AS DueDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112) AS DueDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) AS DATE) AS DueWeekEndingDate,
            CAST(h.HTRCMT AS VARCHAR(200))       AS HeaderComment,
            CAST(d.DCOMNT AS VARCHAR(200))       AS DetailComment,
            CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
            CAST(d.DTSHPQ AS DECIMAL(18,4))      AS TotalShippedQty,
            CAST(d.DEXPED AS VARCHAR(20))        AS ExpediteCode,
            CAST(d.DFIRMC AS VARCHAR(20))        AS FirmCode,
            CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
            TRIM(h.HSTATS)                       AS HeaderStatus,
            TRIM(h.HCANCL)                       AS CancelFlag,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
                ORDER BY h.HDLDTE DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
        --   AND TRIM(h.HCANCL) = 'N' 
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)        AS SnapshotDate,
    CAST(TransferNumber                  AS VARCHAR(50)) AS TransferNumber,
    CAST(ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS INT) AS TransferLine,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(SourceWarehouseCode             AS VARCHAR(50))  AS SourceWarehouseCode,
    CAST(ReceivingWarehouseCode          AS VARCHAR(50))  AS ReceivingWarehouseCode,
    CAST(ShipDateKey                     AS INT)          AS ShipDateKey,
    CAST(ShipDate                        AS DATE)         AS ShipDate,
    CAST(ShipWeekEndingDate              AS DATE)         AS ShipWeekEndingDate,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(DueWeekEndingDate               AS DATE)         AS DueWeekEndingDate,
    CAST(HeaderComment                   AS VARCHAR(200)) AS HeaderComment,
    CAST(DetailComment                   AS VARCHAR(200)) AS DetailComment,
    CAST(TransferQty                     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty                      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TotalShippedQty                 AS DECIMAL(18,4)) AS TotalShippedQty,
    CAST(ExpediteCode                    AS VARCHAR(20)) AS ExpediteCode,
    CAST(FirmCode                        AS VARCHAR(20)) AS FirmCode,
    CAST(TransferCube                    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus                    AS VARCHAR(10))  AS HeaderStatus,
    CAST(CancelFlag                      AS VARCHAR(10))  AS CancelFlag,
    CAST('Manufacturing_Inventory_AFI'   AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                 AS VARCHAR(128)) AS SourceTable
FROM _HoldingTransfer
GO
```

## `InventoryHistory_Enh.v_InventorySnapshotWeekly`

```sql
CREATE   VIEW InventoryHistory_Enh.v_InventorySnapshotWeekly AS
-- CORE CONCEPT UPDATE 2026-05-27:
--   DemandInventorySnapshotWeekly captures Monday snapshots, while Inventory Health needs Saturday snapshots.
--   Use DemandInventorySnapshotDaily and filter to Saturday captures.
--   SnapshotWeekEndingDate is now the actual Saturday capture date.
--   FiscalMonth/FiscalMonthDate describe the inventory forecast period.
--   Grain: (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth).
--   Do not use InventoryHistory_Enh.ItemBalanceHistorical as backup/backfill information.
WITH source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(dinSnapshot AS DATE) AS SnapshotWeekEndingDate,
        CAST(dinFiscalMonth AS INT) AS FiscalMonth,
        CAST(DATEFROMPARTS(CAST(dinFiscalMonth / 100 AS INT), CAST(dinFiscalMonth % 100 AS INT), 1) AS DATE) AS FiscalMonthDate,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(dinIOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
        CAST(dinOrderQuantity AS DECIMAL(18,4)) AS OrderQty,
        CAST(dinBuildQuantity AS DECIMAL(18,4)) AS BuildQty,
        CAST(TRIM(dinMakeBuyCode) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(TRIM(dinSource1) AS VARCHAR(50))  AS SourceWarehouseCode,
        CAST('DemandInventorySnapshotDaily' AS VARCHAR(50)) AS SourceLabel,
        CAST('SupplyChain_Enh_1' AS VARCHAR(64)) AS SourceSystem,
        CAST('DemandInventorySnapshotDaily (Sat dedupe)' AS VARCHAR(128)) AS SourceTable,
        dtec,
        dtea
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandInventorySnapshotDaily]
    WHERE dinItem IS NOT NULL AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> '' AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND CAST(dinFiscalMonth AS INT) BETWEEN 190001 AND 209912
      AND CAST(dinFiscalMonth AS INT) % 100 BETWEEN 1 AND 12
      AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
), ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM source_rows
)
SELECT 
    ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth, FiscalMonthDate, MakeBuyCode, SourceWarehouseCode,
    OnHandQty, SafetyStockTarget, IOSafetyStock, OrderQty, BuildQty,
    SourceLabel, SourceSystem, SourceTable
FROM ranked WHERE rn = 1
GO
```

## `InventoryHistory_Enh.v_ItemBalanceHistorical`

```sql
CREATE   VIEW InventoryHistory_Enh.v_ItemBalanceHistorical AS
-- Source: SC_LH.dbo.itembalance loaded via df_brz_ItemBalance (DF2 workaround pending EL.Inventory_Enh_History.ItemBalance promote)
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate); 107 dups detected → ROW_NUMBER dedupe by latest OnHandQty
-- History: 2021-03-06 → 2026-05-16 (5 years); not used as backup/backfill for v_InventorySnapshotWeekly
-- Future: when Dhivya promotes Enterprise.Inventory_Enh_History.ItemBalance, swap source_objects in registry
WITH ranked AS (
    SELECT
        TRIM(ItemNumber)                  AS ItemSku,
        TRIM(Warehouse)                   AS WarehouseCode,
        CAST(DateWeekEnding AS DATE)      AS WeekEndingDate,
        CAST(OnHandQty AS DECIMAL(18,4))  AS OnHandQty,
        TRIM(ItemStatus)                  AS ItemStatus,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(ItemNumber), TRIM(Warehouse), CAST(DateWeekEnding AS DATE)
            ORDER BY OnHandQty DESC, ItemStatus
        ) AS rn
    FROM [SupplyChain_Lakehouse].[dbo].[itembalance]
    WHERE ItemNumber IS NOT NULL AND Warehouse IS NOT NULL
      AND TRIM(ItemNumber) <> '' AND TRIM(Warehouse) <> ''
)
SELECT
    CAST(ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(WeekEndingDate     AS DATE)          AS WeekEndingDate,
    CAST(OnHandQty          AS DECIMAL(18,4)) AS OnHandQty,
    CAST(ItemStatus         AS VARCHAR(10))   AS ItemStatus,
    CAST('SupplyChain_Lakehouse'    AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.itembalance (DF2)'    AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1
GO
```

## `InventoryHistory_Enh.v_LastInvoiceHelper`

```sql
-- ---- InventoryHistory_Enh.v_LastInvoiceHelper ----
-- MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
CREATE   VIEW InventoryHistory_Enh.v_LastInvoiceHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    CAST(s.ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(s.WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(a.AsOfDate          AS DATE)          AS AsOfDate,
    CAST(MAX(s.InvoiceDate)  AS DATE)          AS LastInvoiceDate,
    CAST(DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate) AS INT) AS WeeksSinceLastInvoice
FROM (
    SELECT
        CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InvoiceDate         AS DATE)        AS InvoiceDate
    FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
    WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
      AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
      AND InvoiceDate IS NOT NULL
) s
JOIN asof a ON s.InvoiceDate <= a.AsOfDate
GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
GO
```

## `InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly`

```sql
-- ---- InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly ----
-- WEEKLY — Saturday only (cron '0 6 * * 6' in registry).
-- Captures latest WeekEndingDate snapshot per (ItemSku, WarehouseCode).
CREATE   VIEW InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly AS
WITH _LogilityItemStatus AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.LogilityItemStatus
    SELECT ItemSku, WarehouseCode, WeekEndingDate, ItemStatus, FutureStatus, StatusChangeDate,
           OnHandQty, SafetyStockQty, ShippableInvQty, MonthsOfSupply, Price,
           ItemClass, Vendor, HoldBuyCode, IsCertified
    FROM (
        SELECT
            TRIM(Item)                            AS ItemSku,
            TRIM(Whse)                            AS WarehouseCode,
            CAST(WeekEnding AS DATE)              AS WeekEndingDate,
            TRIM(ItemStatus)                      AS ItemStatus,
            TRIM(FutureStatus)                    AS FutureStatus,
            CAST(StatusChngDate AS DATE)          AS StatusChangeDate,
            CAST(OnHandQty AS DECIMAL(18,4))      AS OnHandQty,
            CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
            CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
            CAST(MosofSupply AS DECIMAL(18,4))    AS MonthsOfSupply,
            CAST(Price AS DECIMAL(18,4))          AS Price,
            TRIM(ItemClass)                       AS ItemClass,
            TRIM(Vendor)                          AS Vendor,
            TRIM(HoldBuy)                         AS HoldBuyCode,
            CAST(1 AS BIT)                        AS IsCertified,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
                ORDER BY
                    CASE WHEN COALESCE(ShippableInvQty,0) = 0
                          AND COALESCE(FirmDemand,0) = 0 THEN 1 ELSE 0 END ASC,
                    StatusChngDate DESC,
                    COALESCE(OnHandAmt,0) DESC,
                    CAST(FileDate AS DATETIME2) DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandFulfillmentCommonContainer_Logility]
        WHERE Item IS NOT NULL AND Whse IS NOT NULL
          AND TRIM(Item) <> '' AND TRIM(Whse) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(DATEADD(day, (7 - DATEPART(weekday, SYSUTCDATETIME())) % 7,
                 CAST(SYSUTCDATETIME() AS DATE))  AS DATE)         AS WeekEndingDate,
    CAST(ItemSku                                  AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                            AS VARCHAR(50))  AS WarehouseCode,
    CAST(ItemStatus                               AS VARCHAR(20))  AS ItemStatus,
    CAST(FutureStatus                             AS VARCHAR(20))  AS FutureStatus,
    CAST(StatusChangeDate                         AS DATE)         AS StatusChangeDate,
    CAST(IsCertified                              AS BIT)          AS IsCertified,
    CAST('Enterprise_Lakehouse'                   AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility' AS VARCHAR(128)) AS SourceTable
FROM _LogilityItemStatus
WHERE WeekEndingDate = (
    SELECT MAX(WeekEndingDate) FROM _LogilityItemStatus
)
GO
```

## `InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily`

```sql
-- ---- InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_ManufacturingOrderSnapshotDaily AS
WITH _ManufacturingOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.ManufacturingOrder
    SELECT
        CAST(TRIM(ORDNO)                  AS VARCHAR(50))    AS MoNumber,
        CAST(TRIM(FITEM)                  AS VARCHAR(50))    AS ItemSku,
        CAST(TRIM(FITWH)                  AS VARCHAR(50))    AS WarehouseCode,
        CAST(TRIM(OSTAT)                  AS VARCHAR(10))    AS StatusCode,
        CAST(ORQTY                        AS DECIMAL(18,4))  AS OrderQty,
        CAST(QTYRC                        AS DECIMAL(18,4))  AS ReceivedQty,
        CAST(CASE WHEN TRIM(OSTAT) IN ('10','40','45')
                  THEN CAST(ORQTY - QTYRC AS DECIMAL(18,4))
                  ELSE 0 END              AS DECIMAL(18,4))  AS MOOnOrderQty, --Giang: Confirm logic với Robert. 
        CAST(ODUDT                        AS INT)            AS DueDateKey
    FROM [Enterprise_Lakehouse].[Manufacturing_ProductionPlanning_AFI].[MOMAST]
    WHERE FITEM IS NOT NULL AND FITWH IS NOT NULL
      AND TRIM(FITEM) <> '' AND TRIM(FITWH) <> ''
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(MoNumber                        AS VARCHAR(50))  AS MoNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(OrderQty                        AS DECIMAL(18,4)) AS OrderQty,
    CAST(ReceivedQty                     AS DECIMAL(18,4)) AS ReceivedQty,
    CAST(MOOnOrderQty                    AS DECIMAL(18,4)) AS MOOnOrderQty,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST('Manufacturing_ProductionPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('MOMAST'                                AS VARCHAR(128)) AS SourceTable
FROM _ManufacturingOrder
GO
```

## `InventoryHistory_Enh.v_MovementFlagHelper`

```sql
-- ---- InventoryHistory_Enh.v_MovementFlagHelper ----
-- HasMovementLast17W: InvoiceDetail as movement signal per BRD §6 (only sales count for SLOB).
CREATE   VIEW InventoryHistory_Enh.v_MovementFlagHelper AS
WITH asof AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotWeekEndingDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
),
moves AS (
    SELECT
        s.ItemSku, s.WarehouseCode, a.AsOfDate,
        MAX(CASE WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                  AND s.InvoiceDate <= a.AsOfDate
                 THEN 1 ELSE 0 END) AS HasMovementLast17W,
        COUNT(*)                    AS MovementCountLast17W
    FROM (
        SELECT
            CAST(TRIM(ItemSKU)       AS VARCHAR(50)) AS ItemSku,
            CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode,
            CAST(InvoiceDate         AS DATE)        AS InvoiceDate
        FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
        WHERE ItemSKU IS NOT NULL AND WarehouseCode IS NOT NULL
          AND TRIM(ItemSKU) <> '' AND TRIM(WarehouseCode) <> ''
          AND InvoiceDate IS NOT NULL
    ) s
    JOIN asof a
         ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
        AND s.InvoiceDate <= a.AsOfDate
    GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
)
SELECT
    CAST(ItemSku                AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode          AS VARCHAR(50)) AS WarehouseCode,
    CAST(AsOfDate               AS DATE)        AS AsOfDate,
    CAST(HasMovementLast17W     AS BIT)         AS HasMovementLast17W,
    CAST(MovementCountLast17W   AS INT)         AS MovementCountLast17W
FROM moves
GO
```

## `InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily`

```sql
-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ---- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily AS
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    WHERE r.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(PoNumber                        AS VARCHAR(50))  AS PoNumber,
    CAST(PoLine                          AS INT)          AS PoLine,
    CAST(VendorNumber                    AS VARCHAR(50))  AS VendorNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(StockQty                        AS DECIMAL(18,4)) AS StockQty,
    CAST(OrderedQty                      AS DECIMAL(18,4)) AS OrderedQty,
    CAST(InTransitQtySource              AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(POOnOrderQty                    AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(POInTransitQty                  AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(TotalOpenPOQty                  AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(EstimatedArrivalDate            AS DATE)         AS EstimatedArrivalDate,
    CAST(EstimatedDepartureDate          AS DATE)         AS EstimatedDepartureDate,
    CAST(SourceSystem                    AS VARCHAR(64))  AS SourceSystem,
    CAST(SourceTable                     AS VARCHAR(128)) AS SourceTable
FROM _PurchaseOrder
GO
```

## `InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical`

```sql
CREATE   VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical AS
-- Source: SC_LH.dbo.purchaseordersnapshot loaded via df_brz_PurchaseOrderSnapshot (DF2 workaround, 2B rows ⚠️)
-- Grain: (SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode)
-- Phase 2 PO-as-of feature: capture historical PO state by SnapshotDate
-- posDueDt is AS/400 CYYMMDD decimal (e.g., 1230130 = 2023-01-30)
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    WHERE r.rn = 1
)
SELECT
    CAST(posSnapshot AS DATE)                                 AS SnapshotDate,
    CAST(TRIM(posItNbr)             AS VARCHAR(50))           AS ItemSku,
    CAST(TRIM(posWhse)              AS VARCHAR(50))           AS WarehouseCode,
    CAST(TRIM(posVndnr)             AS VARCHAR(50))           AS VendorNumber,
    CAST(posQtyOr                   AS DECIMAL(18,4))         AS OrderedQty,
    CAST(TRIM(posPstts)             AS VARCHAR(10))           AS StatusCode,
    CAST(
        TRY_CAST(
            DATEFROMPARTS(
                1900 + 100 * (TRY_CAST(posDueDt AS INT) / 1000000) + ((TRY_CAST(posDueDt AS INT) % 1000000) / 10000),
                (TRY_CAST(posDueDt AS INT) % 10000) / 100,
                TRY_CAST(posDueDt AS INT) % 100
            ) AS DATE)                                        AS DATE)              AS DueDate,
    CAST(posUUD1PM                  AS DECIMAL(18,4))         AS UnitCost,
    CAST('SupplyChain_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.purchaseordersnapshot (DF2)'        AS VARCHAR(128)) AS SourceTable
FROM [SupplyChain_Lakehouse].[dbo].[purchaseordersnapshot]
WHERE posItNbr IS NOT NULL AND posWhse IS NOT NULL
  AND TRIM(posItNbr) <> '' AND TRIM(posWhse) <> ''
GO
```

## `InventoryHistory_Enh.v_SafetyStockHelper`

```sql
CREATE   VIEW InventoryHistory_Enh.v_SafetyStockHelper AS
-- CORE CONCEPT UPDATE 2026-05-22:
--   Safety stock target is normalized across the next 3 fiscal months.
--   Fallback to prior 13-week average only when fiscal-period safety stock is unavailable.
-- 2026-05-20 FIX (Giang #6): BRD says '13-week AVERAGE safety stock target', not latest.
-- Replaced ROW_NUMBER picking latest snapshot → AVG() across 13 weekly snapshots prior to AsOfDate.
-- Grain: (ItemSku, WarehouseCode, AsOfDate)
WITH asof_dates AS (
    SELECT CAST(SYSUTCDATETIME() AS DATE) AS AsOfDate
    UNION
    SELECT DISTINCT SnapshotWeekEndingDate FROM InventoryHistory_Enh.InventorySnapshotWeekly
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
        MAX(isw.SnapshotWeekEndingDate) AS LatestSnapshotDate
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate > DATEADD(week, -13, a.AsOfDate)
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
    JOIN InventoryHistory_Enh.InventorySnapshotWeekly isw
         ON isw.ItemSku = ls.ItemSku
        AND isw.WarehouseCode = ls.WarehouseCode
        AND isw.SnapshotWeekEndingDate = ls.LatestSnapshotDate
        AND isw.FiscalMonthDate >= a.HorizonStartDate
        AND isw.FiscalMonthDate <  a.HorizonEndDate
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
    FROM InventoryHistory_Enh.InventorySnapshotWeekly isw
    JOIN asof a
         ON isw.SnapshotWeekEndingDate <= a.AsOfDate
        AND isw.SnapshotWeekEndingDate > DATEADD(week, -13, a.AsOfDate)
    WHERE isw.SafetyStockTarget IS NOT NULL
    GROUP BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
),
keys AS (
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fiscal_ss
    UNION
    SELECT ItemSku, WarehouseCode, AsOfDate FROM fallback_ss
)
SELECT
    CAST(k.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(k.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(k.AsOfDate       AS DATE)          AS AsOfDate,
    CAST(COALESCE(f.SafetyStockTarget, fb.SafetyStockTarget) AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(COALESCE(f.SnapshotCount, fb.SnapshotCount) AS INT) AS SnapshotCount,
    CAST(CASE WHEN f.SafetyStockTarget IS NOT NULL
              THEN 'Next3FiscalMonths'
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
      AND fb.AsOfDate = k.AsOfDate
GO
```

