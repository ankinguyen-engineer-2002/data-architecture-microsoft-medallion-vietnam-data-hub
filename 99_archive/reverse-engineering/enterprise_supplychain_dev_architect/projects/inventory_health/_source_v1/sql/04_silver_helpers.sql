/*============================================================
  04_silver_helpers.sql — Silver helpers (Tier 3)
  Run on: SupplyChain Processing Warehouse
  Run AFTER Tier 2 (InventorySnapshotWeekly + ForecastSnapshotWeekly).

  4 helpers (one row per ItemSku × WarehouseCode × AsOfDate):
    silver.AwdHelper            — 13W forward forecast / fallback 13W historical
    silver.LastInvoiceHelper    — MAX(InvoiceDate) ≤ AsOfDate
    silver.MovementFlagHelper   — HasMovementLast17W (sales-type TCodes)
    silver.SafetyStockHelper    — current SS for AsOfDate from snapshot

  AsOfDate set = union of:
    - silver.InventoryCurrent.SnapshotDate (rolling 7d)
    - silver.InventorySnapshotWeekly.SnapshotDate (weekly history, last 104 weeks)
============================================================*/


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_AwdHelper
--   AWD rule (BRD): SUM(forecast next 13W) / 13;
--   if forecast == 0 → fallback SUM(shipped last 13W) / 13.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_AwdHelper AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.AwdHelper_stg') IS NOT NULL DROP TABLE silver.AwdHelper_stg;

        CREATE TABLE silver.AwdHelper_stg AS
        WITH asof AS (
            -- Set of AsOf dates we compute AWD for
            SELECT DISTINCT SnapshotDate AS AsOfDate
            FROM silver.InventoryCurrent
            WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))

            UNION

            SELECT DISTINCT SnapshotDate
            FROM silver.InventorySnapshotWeekly
            WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
        ),
        -- Item × Warehouse universe (active SKU-WH from current + weekly)
        item_wh AS (
            SELECT DISTINCT ItemSku, WarehouseCode FROM silver.InventoryCurrent
            UNION
            SELECT DISTINCT ItemSku, WarehouseCode FROM silver.InventorySnapshotWeekly
        ),
        forward13w AS (
            SELECT
                f.ItemSku, f.WarehouseCode, a.AsOfDate,
                SUM(f.ForecastQty) AS Fwd13WQty
            FROM silver.ForecastSnapshotWeekly f
            JOIN asof a
                 ON f.WeekEndingDate >  a.AsOfDate
                AND f.WeekEndingDate <= DATEADD(week, 13, a.AsOfDate)
            GROUP BY f.ItemSku, f.WarehouseCode, a.AsOfDate
        ),
        hist13w AS (
            SELECT
                s.ItemSku, s.WarehouseCode, a.AsOfDate,
                SUM(s.QuantityShipped) AS Hist13WQty
            FROM silver.SalesShipment s
            JOIN asof a
                 ON s.InvoiceDate >  DATEADD(week, -13, a.AsOfDate)
                AND s.InvoiceDate <= a.AsOfDate
            GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
        )
        SELECT
            iw.ItemSku, iw.WarehouseCode, a.AsOfDate,
            ISNULL(f.Fwd13WQty, 0)                                  AS Fwd13WForecastQty,
            ISNULL(h.Hist13WQty, 0)                                 AS Hist13WShippedQty,
            CASE
                WHEN ISNULL(f.Fwd13WQty, 0) > 0
                THEN CAST(f.Fwd13WQty / 13.0 AS DECIMAL(18,4))
                ELSE CAST(ISNULL(h.Hist13WQty, 0) / 13.0 AS DECIMAL(18,4))
            END                                                     AS AwdQty,
            CASE
                WHEN ISNULL(f.Fwd13WQty, 0) > 0 THEN 'Forecast'
                ELSE 'HistoricalFallback'
            END                                                     AS AwdSource,
            SYSUTCDATETIME()                                        AS EtlLoadDate
        FROM item_wh iw
        CROSS JOIN asof a
        LEFT JOIN forward13w f
               ON f.ItemSku = iw.ItemSku
              AND f.WarehouseCode = iw.WarehouseCode
              AND f.AsOfDate = a.AsOfDate
        LEFT JOIN hist13w h
               ON h.ItemSku = iw.ItemSku
              AND h.WarehouseCode = iw.WarehouseCode
              AND h.AsOfDate = a.AsOfDate
        WHERE COALESCE(f.Fwd13WQty, h.Hist13WQty) IS NOT NULL;

        IF OBJECT_ID('silver.AwdHelper') IS NOT NULL DROP TABLE silver.AwdHelper;
        EXEC sp_rename 'silver.AwdHelper_stg', 'AwdHelper';

        ALTER TABLE silver.AwdHelper
            ADD CONSTRAINT PK_silver_AwdHelper
            PRIMARY KEY NONCLUSTERED (AsOfDate, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_LastInvoiceHelper
--   MAX(InvoiceDate) <= AsOfDate per ItemSku × WarehouseCode
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_LastInvoiceHelper AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.LastInvoiceHelper_stg') IS NOT NULL DROP TABLE silver.LastInvoiceHelper_stg;

        CREATE TABLE silver.LastInvoiceHelper_stg AS
        WITH asof AS (
            SELECT DISTINCT SnapshotDate AS AsOfDate
            FROM silver.InventoryCurrent
            WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
            UNION
            SELECT DISTINCT SnapshotDate
            FROM silver.InventorySnapshotWeekly
            WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
        )
        SELECT
            s.ItemSku, s.WarehouseCode, a.AsOfDate,
            MAX(s.InvoiceDate)        AS LastInvoiceDate,
            DATEDIFF(week, MAX(s.InvoiceDate), a.AsOfDate)  AS WeeksSinceLastInvoice,
            SYSUTCDATETIME()          AS EtlLoadDate
        FROM silver.SalesShipment s
        JOIN asof a
             ON s.InvoiceDate <= a.AsOfDate
        GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate;

        IF OBJECT_ID('silver.LastInvoiceHelper') IS NOT NULL DROP TABLE silver.LastInvoiceHelper;
        EXEC sp_rename 'silver.LastInvoiceHelper_stg', 'LastInvoiceHelper';

        ALTER TABLE silver.LastInvoiceHelper
            ADD CONSTRAINT PK_silver_LastInvoiceHelper
            PRIMARY KEY NONCLUSTERED (AsOfDate, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_MovementFlagHelper
--   HasMovementLast17W = 1 if any sales-type movement in last 17 weeks.
--   Sales TCodes (assumed by IMHIST convention): 'SO', 'SC', 'SI', 'WO'
--   ADJUST list once Aric confirms which TCode values represent customer sales.
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_MovementFlagHelper AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.MovementFlagHelper_stg') IS NOT NULL DROP TABLE silver.MovementFlagHelper_stg;

        CREATE TABLE silver.MovementFlagHelper_stg AS
        WITH asof AS (
            SELECT DISTINCT SnapshotDate AS AsOfDate
            FROM silver.InventoryCurrent
            WHERE SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))
            UNION
            SELECT DISTINCT SnapshotDate
            FROM silver.InventorySnapshotWeekly
            WHERE SnapshotDate >= DATEADD(week, -104, CAST(SYSUTCDATETIME() AS DATE))
        ),
        moves AS (
            -- Use SalesShipment as movement signal (BRD rule: only sales count for SLOB)
            SELECT
                s.ItemSku, s.WarehouseCode, a.AsOfDate,
                MAX(CASE WHEN s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                          AND s.InvoiceDate <= a.AsOfDate
                         THEN 1 ELSE 0 END)  AS HasMovementLast17W,
                COUNT(*)                     AS MovementCountLast17W
            FROM silver.SalesShipment s
            JOIN asof a
                 ON s.InvoiceDate > DATEADD(week, -17, a.AsOfDate)
                AND s.InvoiceDate <= a.AsOfDate
            GROUP BY s.ItemSku, s.WarehouseCode, a.AsOfDate
        )
        SELECT
            m.ItemSku, m.WarehouseCode, m.AsOfDate,
            CAST(m.HasMovementLast17W AS BIT)  AS HasMovementLast17W,
            m.MovementCountLast17W,
            SYSUTCDATETIME()                   AS EtlLoadDate
        FROM moves m;

        IF OBJECT_ID('silver.MovementFlagHelper') IS NOT NULL DROP TABLE silver.MovementFlagHelper;
        EXEC sp_rename 'silver.MovementFlagHelper_stg', 'MovementFlagHelper';

        ALTER TABLE silver.MovementFlagHelper
            ADD CONSTRAINT PK_silver_MovementFlagHelper
            PRIMARY KEY NONCLUSTERED (AsOfDate, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- silver.usp_Build_SafetyStockHelper
--   Carries Safety Stock target at AsOfDate from latest InventorySnapshotWeekly ≤ AsOfDate
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE silver.usp_Build_SafetyStockHelper AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('silver.SafetyStockHelper_stg') IS NOT NULL DROP TABLE silver.SafetyStockHelper_stg;

        CREATE TABLE silver.SafetyStockHelper_stg AS
        WITH asof AS (
            SELECT DISTINCT SnapshotDate AS AsOfDate FROM silver.InventoryCurrent
            UNION
            SELECT DISTINCT SnapshotDate FROM silver.InventorySnapshotWeekly
        ),
        ranked AS (
            SELECT
                isw.ItemSku, isw.WarehouseCode, a.AsOfDate,
                isw.SafetyStockTarget,
                ROW_NUMBER() OVER (
                    PARTITION BY isw.ItemSku, isw.WarehouseCode, a.AsOfDate
                    ORDER BY isw.SnapshotDate DESC
                ) AS rn
            FROM silver.InventorySnapshotWeekly isw
            JOIN asof a
                 ON isw.SnapshotDate <= a.AsOfDate
                AND isw.SnapshotDate > DATEADD(week, -13, a.AsOfDate)
        )
        SELECT
            ItemSku, WarehouseCode, AsOfDate,
            SafetyStockTarget,
            SYSUTCDATETIME() AS EtlLoadDate
        FROM ranked WHERE rn = 1;

        IF OBJECT_ID('silver.SafetyStockHelper') IS NOT NULL DROP TABLE silver.SafetyStockHelper;
        EXEC sp_rename 'silver.SafetyStockHelper_stg', 'SafetyStockHelper';

        ALTER TABLE silver.SafetyStockHelper
            ADD CONSTRAINT PK_silver_SafetyStockHelper
            PRIMARY KEY NONCLUSTERED (AsOfDate, ItemSku, WarehouseCode) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '04_silver_helpers.sql complete: 4 helper procs compiled.';
GO
