/*============================================================
  08_gold_facts.sql — Gold facts (2 facts only, per Aric)
  Run on: SupplyChain Gold Warehouse
  Prerequisite: all silver tables + all gold dims + CogsRollingHelper.

  2 facts (the only ones exposed to Power BI semantic model):
    gold.FactInventoryHealthSnapshot   — current + weekly historical
    gold.FactInventoryRiskForward      — supply plan forward projection
============================================================*/


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_FactInventoryHealthSnapshot
--   Grain: (ItemSku, WarehouseCode, SnapshotDate, SnapshotType)
--   SnapshotType ∈ ('Current', 'Weekly')
--   UNION of:
--     - silver.InventoryCurrent (rolling 7d daily)
--     - silver.InventorySnapshotWeekly (history)
--   JOIN helpers (Awd, LastInvoice, MovementFlag, SafetyStock)
--   JOIN dims (DimItem, DimDate)
--   Snapshot-aware PO/MO pull (from snapshot tables when SnapshotType='Weekly')
--   Pass 1: base + classification + financial direct
--   Pass 2 (in this proc): rolling COGS / 52W / 12M avg via UPDATE
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_FactInventoryHealthSnapshot AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.FactInventoryHealthSnapshot_stg') IS NOT NULL
            DROP TABLE gold.FactInventoryHealthSnapshot_stg;

        ----------------------------------------------------------------
        -- PASS 1: base build
        ----------------------------------------------------------------
        CREATE TABLE gold.FactInventoryHealthSnapshot_stg AS
        WITH base AS (
            -- Current daily rows
            SELECT
                'Current'                              AS SnapshotType,
                ic.SnapshotDate                        AS SnapshotDate,
                ic.ItemSku, ic.WarehouseCode,
                ic.OnHandQty,
                CAST('ItemMaster_AFI' AS VARCHAR(64))   AS SourceSystem,
                CAST('ITEMBL'         AS VARCHAR(128))  AS SourceTable
            FROM [silver].[InventoryCurrent] ic
            WHERE ic.SnapshotDate >= DATEADD(day, -7, CAST(SYSUTCDATETIME() AS DATE))

            UNION ALL

            -- Weekly history rows
            SELECT
                'Weekly',
                iw.SnapshotDate,
                iw.ItemSku, iw.WarehouseCode,
                iw.OnHandQty,
                CAST('SupplyChain_Enh_1' AS VARCHAR(64)),
                CAST('DemandInventorySnapshotWeekly' AS VARCHAR(128))
            FROM [silver].[InventorySnapshotWeekly] iw
        ),
        latest_current_date AS (
            SELECT MAX(SnapshotDate) AS MaxDate FROM [silver].[InventoryCurrent]
        ),
        -- PO aggregated to (ItemSku, WarehouseCode) — current state
        po_curr AS (
            SELECT
                ItemSku, WarehouseCode,
                SUM(POOnOrderQty)   AS POOnOrderQty,
                SUM(POInTransitQty) AS POInTransitQty
            FROM [silver].[PurchaseOrder]
            GROUP BY ItemSku, WarehouseCode
        ),
        -- PO snapshot-aware: per SnapshotDate
        po_snap AS (
            SELECT
                SnapshotDate, ItemSku, WarehouseCode,
                SUM(POOnOrderQty)   AS POOnOrderQty,
                SUM(POInTransitQty) AS POInTransitQty
            FROM [silver].[PurchaseOrderSnapshotDaily]
            GROUP BY SnapshotDate, ItemSku, WarehouseCode
        ),
        -- MO aggregated current
        mo_curr AS (
            SELECT
                ItemSku, WarehouseCode,
                SUM(MOOnOrderQty) AS MOOnOrderQty
            FROM [silver].[ManufacturingOrder]
            GROUP BY ItemSku, WarehouseCode
        ),
        -- MO snapshot-aware
        mo_snap AS (
            SELECT
                SnapshotDate, ItemSku, WarehouseCode,
                SUM(MOOnOrderQty) AS MOOnOrderQty
            FROM [silver].[ManufacturingOrderSnapshotDaily]
            GROUP BY SnapshotDate, ItemSku, WarehouseCode
        ),
        -- Hold snapshot-aware
        hold_snap AS (
            SELECT
                SnapshotDate, ItemSku, WarehouseCode,
                SUM(TransferQty) AS OnHoldQty,
                SUM(TransferCube) AS OnHoldCube
            FROM [silver].[HoldingTransferSnapshotDaily]
            GROUP BY SnapshotDate, ItemSku, WarehouseCode
        ),
        -- Hold current (today's view)
        hold_curr AS (
            SELECT
                ItemSku, WarehouseCode,
                SUM(TransferQty) AS OnHoldQty,
                SUM(TransferCube) AS OnHoldCube
            FROM [silver].[HoldingTransfer]
            GROUP BY ItemSku, WarehouseCode
        ),
        -- Transfer InTransit current (paired in-transit warehouse)
        ti_curr AS (
            SELECT
                LTRIM(RTRIM(b.ITNBR))         AS ItemSku,
                LTRIM(RTRIM(w.WarehouseCode)) AS WarehouseCode,
                SUM(CAST(b.MOHTQ AS DECIMAL(18,4)))   AS TransferInInTransitQty
            FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
            JOIN [silver].[Warehouse] w
                 ON LTRIM(RTRIM(w.IntransitWarehouseCode)) = LTRIM(RTRIM(b.HOUSE))
            WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
              AND LTRIM(RTRIM(b.ITNBR)) <> '' AND LTRIM(RTRIM(b.HOUSE)) <> ''
            GROUP BY LTRIM(RTRIM(b.ITNBR)), LTRIM(RTRIM(w.WarehouseCode))
        )
        SELECT
            -- Grain
            b.ItemSku, b.WarehouseCode, b.SnapshotDate, b.SnapshotType,
            d.WeekEndingDate, d.DateKey, d.FiscalMonth, d.FiscalMonthYear,
            CASE WHEN b.SnapshotType = 'Current'
                  AND b.SnapshotDate = (SELECT MaxDate FROM latest_current_date)
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END        AS IsLatestSnapshot,
            b.SourceSystem, b.SourceTable,
            SYSUTCDATETIME()                                         AS EtlLoadDate,
            CAST(1 AS BIGINT)                                        AS RuleVersionKey,

            -- Base supply qty
            ISNULL(b.OnHandQty, 0)                                   AS OnHandQty,
            ISNULL(ti.TransferInInTransitQty, 0)                     AS TransferInInTransitQty,

            -- Snapshot-aware PO / MO / Hold pull
            CASE WHEN b.SnapshotType = 'Current'
                 THEN ISNULL(pc.POInTransitQty, 0)
                 ELSE ISNULL(ps.POInTransitQty, 0)
            END                                                      AS POInTransitQty,
            CASE WHEN b.SnapshotType = 'Current'
                 THEN ISNULL(pc.POOnOrderQty, 0)
                 ELSE ISNULL(ps.POOnOrderQty, 0)
            END                                                      AS POOnOrderQty,
            CASE WHEN b.SnapshotType = 'Current'
                 THEN ISNULL(mc.MOOnOrderQty, 0)
                 ELSE ISNULL(ms.MOOnOrderQty, 0)
            END                                                      AS MOOnOrderQty,

            -- Derived totals
            ISNULL(ti.TransferInInTransitQty,0) +
                CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POInTransitQty,0)
                     ELSE ISNULL(ps.POInTransitQty,0) END             AS InTransitQty,
            CASE WHEN b.SnapshotType='Current'
                 THEN ISNULL(pc.POOnOrderQty,0) + ISNULL(mc.MOOnOrderQty,0)
                 ELSE ISNULL(ps.POOnOrderQty,0) + ISNULL(ms.MOOnOrderQty,0)
            END                                                      AS OnOrderQty,

            -- Demand & coverage
            awd.AwdQty, awd.AwdSource,
            CASE WHEN awd.AwdQty > 0
                 THEN CAST(b.OnHandQty / awd.AwdQty AS DECIMAL(18,4)) END  AS WeeksOfSupply,
            ss.SafetyStockTarget                                          AS SafetyStockTargetQty,
            CASE WHEN ss.SafetyStockTarget > 0
                 THEN CAST(b.OnHandQty / ss.SafetyStockTarget AS DECIMAL(18,4)) END AS SafetyStockMultiple,

            -- Inventory classification (BRD v1)
            CASE
                WHEN dim.AfiItemStatus IN ('D','R')
                 AND (ISNULL(b.OnHandQty,0)
                    + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
                    + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
                    THEN 'Inactive'
                WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 0.5 * ss.SafetyStockTarget THEN 'Below Target'
                WHEN ss.SafetyStockTarget > 0 AND b.OnHandQty <= 1.5 * ss.SafetyStockTarget THEN 'Sweet Spot'
                WHEN awd.AwdQty > 0 AND b.OnHandQty <= 17  * awd.AwdQty THEN 'Over Target'
                WHEN awd.AwdQty > 0 AND b.OnHandQty <= 52  * awd.AwdQty THEN 'Excess'
                WHEN awd.AwdQty > 0 AND b.OnHandQty <= 104 * awd.AwdQty THEN 'Aggressive Excess'
                ELSE 'TB Inventory'
            END                                                      AS InventoryClassification,

            -- Financial
            cc.StandardCost,
            dim.FobArcPrice,
            dim.Cubes,
            ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0)        AS InventoryValueAtCost,
            ISNULL(b.OnHandQty,0) * ISNULL(dim.FobArcPrice,0)        AS InventoryValueAtRevenue,
            ISNULL(b.OnHandQty,0) * ISNULL(dim.Cubes,0)              AS UsedStorageCube,

            -- Placeholders for rolling COGS (Pass 2)
            CAST(NULL AS DECIMAL(18,4))                              AS PeriodCogs,
            CAST(NULL AS DECIMAL(18,4))                              AS Cogs52M,
            CAST(NULL AS DECIMAL(18,4))                              AS Cogs12M,
            CAST(NULL AS DECIMAL(18,4))                              AS AverageInventoryValueAtCost,

            -- Status flags
            lh.LastInvoiceDate,
            dim.LifecycleStatus,
            CASE WHEN dim.AfiItemStatus IN ('D','R')
                  AND (ISNULL(b.OnHandQty,0)
                     + CASE WHEN b.SnapshotType='Current' THEN ISNULL(pc.POOnOrderQty,0) ELSE ISNULL(ps.POOnOrderQty,0) END
                     + CASE WHEN b.SnapshotType='Current' THEN ISNULL(mc.MOOnOrderQty,0) ELSE ISNULL(ms.MOOnOrderQty,0) END) = 0
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
            END                                                      AS InactiveFlag,
            -- M4 FIX (2026-05-17): require LastInvoiceDate IS NOT NULL.
            -- Without this fix, new items (never invoiced) would be SLOB-flagged because
            -- ISNULL(LastInvoice, '1900-01-01') < anycutoff = TRUE. Wrong semantic.
            CASE WHEN dim.AfiItemStatus <> 'N'
                  AND lh.LastInvoiceDate IS NOT NULL
                  AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
            END                                                      AS SlobFlag,
            CASE WHEN ISNULL(mf.HasMovementLast17W, 0) = 0
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
            END                                                      AS NoMovementFlag,
            dim.UnavailableFlag,

            -- Hold (snapshot-aware)
            CASE WHEN b.SnapshotType='Current'
                 THEN ISNULL(hc.OnHoldQty, 0)
                 ELSE ISNULL(hs.OnHoldQty, 0)
            END                                                      AS OnHoldQty,
            CASE WHEN (CASE WHEN b.SnapshotType='Current' THEN ISNULL(hc.OnHoldQty,0) ELSE ISNULL(hs.OnHoldQty,0) END) > 0
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
            END                                                      AS OnHoldFlag,

            -- Obsolete (SLOB-flagged inventory value at cost)
            -- M4 FIX (2026-05-17): same NULL handling as SlobFlag for consistency
            CASE WHEN dim.AfiItemStatus <> 'N'
                  AND lh.LastInvoiceDate IS NOT NULL
                  AND lh.LastInvoiceDate < DATEADD(week, -17, b.SnapshotDate)
                 THEN ISNULL(b.OnHandQty,0) * ISNULL(cc.StandardCost,0)
                 ELSE 0
            END                                                      AS ObsoleteValue
        FROM base b
        LEFT JOIN [gold].[DimDate] d         ON d.CalendarDate = b.SnapshotDate
        LEFT JOIN [gold].[DimItem] dim       ON dim.ItemSku    = b.ItemSku
        LEFT JOIN [silver].[CostCurrent] cc  ON cc.ItemSku     = b.ItemSku
        LEFT JOIN ti_curr ti                  ON ti.ItemSku=b.ItemSku AND ti.WarehouseCode=b.WarehouseCode
        LEFT JOIN po_curr pc                  ON pc.ItemSku=b.ItemSku AND pc.WarehouseCode=b.WarehouseCode
        LEFT JOIN po_snap ps                  ON ps.ItemSku=b.ItemSku AND ps.WarehouseCode=b.WarehouseCode AND ps.SnapshotDate=b.SnapshotDate
        LEFT JOIN mo_curr mc                  ON mc.ItemSku=b.ItemSku AND mc.WarehouseCode=b.WarehouseCode
        LEFT JOIN mo_snap ms                  ON ms.ItemSku=b.ItemSku AND ms.WarehouseCode=b.WarehouseCode AND ms.SnapshotDate=b.SnapshotDate
        LEFT JOIN hold_curr hc                ON hc.ItemSku=b.ItemSku AND hc.WarehouseCode=b.WarehouseCode
        LEFT JOIN hold_snap hs                ON hs.ItemSku=b.ItemSku AND hs.WarehouseCode=b.WarehouseCode AND hs.SnapshotDate=b.SnapshotDate
        LEFT JOIN [silver].[AwdHelper] awd    ON awd.ItemSku=b.ItemSku AND awd.WarehouseCode=b.WarehouseCode AND awd.AsOfDate=b.SnapshotDate
        LEFT JOIN [silver].[LastInvoiceHelper] lh
                                              ON lh.ItemSku=b.ItemSku AND lh.WarehouseCode=b.WarehouseCode AND lh.AsOfDate=b.SnapshotDate
        LEFT JOIN [silver].[MovementFlagHelper] mf
                                              ON mf.ItemSku=b.ItemSku AND mf.WarehouseCode=b.WarehouseCode AND mf.AsOfDate=b.SnapshotDate
        LEFT JOIN [silver].[SafetyStockHelper] ss
                                              ON ss.ItemSku=b.ItemSku AND ss.WarehouseCode=b.WarehouseCode AND ss.AsOfDate=b.SnapshotDate;

        IF OBJECT_ID('gold.FactInventoryHealthSnapshot') IS NOT NULL
            DROP TABLE gold.FactInventoryHealthSnapshot;
        EXEC sp_rename 'gold.FactInventoryHealthSnapshot_stg', 'FactInventoryHealthSnapshot';

        ALTER TABLE gold.FactInventoryHealthSnapshot
            ADD CONSTRAINT PK_gold_FactInventoryHealthSnapshot
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, SnapshotDate, SnapshotType) NOT ENFORCED;

        ----------------------------------------------------------------
        -- PASS 2: fill rolling COGS / 52W / 12M avg via UPDATE
        --   Only month-end rows get filled (where DimDate.IsMonthEnd=1)
        ----------------------------------------------------------------
        UPDATE f
        SET PeriodCogs   = c.PeriodCogs,
            Cogs12M      = c.Cogs12M,
            Cogs52M      = c.Cogs52M
        FROM gold.FactInventoryHealthSnapshot f
        JOIN gold.DimDate d
             ON d.CalendarDate = f.SnapshotDate
        JOIN gold.CogsRollingHelper c
             ON c.ItemSku        = f.ItemSku
            AND c.WarehouseCode  = f.WarehouseCode
            AND c.FiscalMonthYear = f.FiscalMonthYear
        WHERE d.IsMonthEnd = 1;

        -- Average inventory value at cost = AVG(IVC) trailing 12 months by item-wh
        ;WITH avgivc AS (
            SELECT
                ItemSku, WarehouseCode, FiscalMonthYear,
                AVG(InventoryValueAtCost) OVER (
                    PARTITION BY ItemSku, WarehouseCode
                    ORDER BY FiscalMonth
                    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
                ) AS AvgInvValue12M
            FROM (
                SELECT DISTINCT
                    f.ItemSku, f.WarehouseCode, f.FiscalMonthYear, f.InventoryValueAtCost,
                    d.FiscalMonth
                FROM gold.FactInventoryHealthSnapshot f
                JOIN gold.DimDate d ON d.CalendarDate = f.SnapshotDate
                WHERE d.IsMonthEnd = 1
            ) m
        )
        UPDATE f
        SET AverageInventoryValueAtCost = a.AvgInvValue12M
        FROM gold.FactInventoryHealthSnapshot f
        JOIN gold.DimDate d ON d.CalendarDate = f.SnapshotDate
        JOIN avgivc a
             ON a.ItemSku = f.ItemSku
            AND a.WarehouseCode = f.WarehouseCode
            AND a.FiscalMonthYear = f.FiscalMonthYear
        WHERE d.IsMonthEnd = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_FactInventoryRiskForward
--   Grain: (ItemSku, WarehouseCode, WeekEndingDate)
--   Source: silver.SupplyPlan (latest snapshot) + AtpWeekEnding + AllocatedDemand
--   + DimItem (FobArcPrice for Revenue at Risk)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_FactInventoryRiskForward AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.FactInventoryRiskForward_stg') IS NOT NULL
            DROP TABLE gold.FactInventoryRiskForward_stg;

        CREATE TABLE gold.FactInventoryRiskForward_stg AS
        WITH latest_plan AS (
            -- Take latest snapshot per (Item, Wh, WeekEnding)
            SELECT
                ItemSku, WarehouseCode, WeekEndingDate,
                BeginningBalanceQty, FirmDemandQty, NetForecastQty,
                FirmPurchaseOrderQty, PlannedPurchaseOrderQty,
                OnOrderTransferInQty, ShippableInventoryQty,
                SafetyStockTargetQty, MonthsOfSupply, SINegQty,
                ROW_NUMBER() OVER (
                    PARTITION BY ItemSku, WarehouseCode, WeekEndingDate
                    ORDER BY SnapshotDate DESC
                ) AS rn
            FROM [silver].[SupplyPlan]
        ),
        atp_w2 AS (
            -- ATP Week2 per business rule
            SELECT ItemSku, WarehouseCode, AtpQty
            FROM [silver].[AtpWeekEnding]
            WHERE WeekNumber = 2
        ),
        alloc AS (
            SELECT
                ItemSku, WarehouseCode,
                SUM(AllocatedDemandQty) AS AllocatedDemandQty
            FROM [silver].[AllocatedDemandCandidate]
            GROUP BY ItemSku, WarehouseCode
        )
        SELECT
            lp.ItemSku, lp.WarehouseCode, lp.WeekEndingDate,
            d.DateKey,
            lp.BeginningBalanceQty, lp.FirmDemandQty, lp.NetForecastQty,
            lp.FirmPurchaseOrderQty, lp.PlannedPurchaseOrderQty,
            lp.OnOrderTransferInQty, lp.ShippableInventoryQty,
            lp.SafetyStockTargetQty, lp.MonthsOfSupply,
            -- 14-day demand/inbound derived
            CAST(lp.FirmDemandQty * (14.0/7.0) AS DECIMAL(18,4))           AS ExpectedDemand14DQty,
            CAST((lp.FirmPurchaseOrderQty + lp.OnOrderTransferInQty) * (14.0/7.0) AS DECIMAL(18,4))
                                                                          AS Inbound14DQty,
            ISNULL(al.AllocatedDemandQty, 0)                              AS AllocatedDemandQty,
            ISNULL(at.AtpQty, 0)                                          AS ATPQty,
            CASE WHEN ISNULL(at.AtpQty, 0) > 0
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS ATPInStockFlag,
            CASE WHEN lp.ShippableInventoryQty > 0
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS ShippableInStockFlag,
            lp.SINegQty,
            CAST(lp.SINegQty * ISNULL(dim.FobArcPrice, 0) AS DECIMAL(18,4)) AS RevenueAtRiskValue,
            -- H5 FIX (2026-05-17): BRD §6.3 "At Week Four Ending" = exact week-4 ending only.
            -- Old logic BETWEEN today AND today+4w included 5 weeks (over-aggregate).
            -- New: only WeekEnding of week-4 (i.e., next Saturday + 4*7 days).
            -- Robert sign-off pending: "Week 4 ending" semantic (from today vs fiscal week N).
            CASE WHEN lp.WeekEndingDate = (
                    -- Saturday of (current week + 4)
                    DATEADD(day,
                            ((7 - DATEPART(weekday, SYSUTCDATETIME()) + 7) % 7) + 28,
                            CAST(SYSUTCDATETIME() AS DATE))
                 )
                 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS WeekFourFlag,
            dim.FobArcPrice,
            CAST(1 AS BIGINT)                                             AS RuleVersionKey,
            SYSUTCDATETIME()                                              AS EtlLoadDate
        FROM latest_plan lp
        LEFT JOIN [gold].[DimDate] d  ON d.CalendarDate = lp.WeekEndingDate
        LEFT JOIN [gold].[DimItem] dim ON dim.ItemSku    = lp.ItemSku
        LEFT JOIN atp_w2 at            ON at.ItemSku=lp.ItemSku AND at.WarehouseCode=lp.WarehouseCode
        LEFT JOIN alloc al             ON al.ItemSku=lp.ItemSku AND al.WarehouseCode=lp.WarehouseCode
        WHERE lp.rn = 1;

        IF OBJECT_ID('gold.FactInventoryRiskForward') IS NOT NULL
            DROP TABLE gold.FactInventoryRiskForward;
        EXEC sp_rename 'gold.FactInventoryRiskForward_stg', 'FactInventoryRiskForward';

        ALTER TABLE gold.FactInventoryRiskForward
            ADD CONSTRAINT PK_gold_FactInventoryRiskForward
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, WeekEndingDate) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '08_gold_facts.sql complete: 2 fact procs compiled.';
GO
