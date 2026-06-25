/*============================================================
  07_gold_helpers.sql — Gold helper
  Run on: SupplyChain Gold Warehouse

  1 helper:
    gold.CogsRollingHelper   — month-level COGS + 52M rolling + 12M avg inv value

  FIXES applied 2026-05-17:
    • H4: ORDER BY FiscalMonth (1-12 cycle) → ORDER BY FiscalMonthYear (chronological YYYYMM)
    • M3: Renamed Cogs52W → Cogs52M (helper grain is monthly, NOT weekly)
          BRD says "52 weeks" — current implementation is "52 months" for Phase 1 simplicity.
          To match BRD strict: rewrite helper at weekly grain (Saturday week-ending).
          Robert sign-off pending re: weekly vs monthly grain.
============================================================*/


-- ════════════════════════════════════════════════════════
-- gold.usp_Build_CogsRollingHelper
--   Compute COGS per fiscal month + 52M/12M rolling for Turns KPI #22.
--   Inputs: silver.SalesShipment + silver.CostCurrent + gold.DimDate
--   Grain: (ItemSku, WarehouseCode, FiscalMonthYear)
-- ════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE gold.usp_Build_CogsRollingHelper AS
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('gold.CogsRollingHelper_stg') IS NOT NULL DROP TABLE gold.CogsRollingHelper_stg;

        CREATE TABLE gold.CogsRollingHelper_stg AS
        WITH monthly AS (
            -- Aggregate COGS per Item-Wh-FiscalMonthYear
            SELECT
                s.ItemSku,
                s.WarehouseCode,
                d.FiscalMonthYear,
                SUM(s.QuantityShipped * ISNULL(c.StandardCost, 0))  AS PeriodCogs,
                SUM(s.QuantityShipped)                              AS PeriodShippedQty
            FROM [silver].[SalesShipment] s
            JOIN [gold].[DimDate] d
                 ON d.CalendarDate = s.InvoiceDate
            LEFT JOIN [silver].[CostCurrent] c
                 ON c.ItemSku = s.ItemSku
            GROUP BY s.ItemSku, s.WarehouseCode, d.FiscalMonthYear
        )
        SELECT
            ItemSku, WarehouseCode, FiscalMonthYear,
            PeriodCogs,
            PeriodShippedQty,
            -- H4 FIX (2026-05-17): ORDER BY FiscalMonthYear chronological (YYYYMM),
            -- NOT FiscalMonth (1-12 cycle which wraps across years incorrectly).
            SUM(PeriodCogs) OVER (
                PARTITION BY ItemSku, WarehouseCode
                ORDER BY FiscalMonthYear
                ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
            )                                                       AS Cogs12M,
            -- M3 FIX (2026-05-17): renamed Cogs52W → Cogs52M (monthly grain)
            SUM(PeriodCogs) OVER (
                PARTITION BY ItemSku, WarehouseCode
                ORDER BY FiscalMonthYear
                ROWS BETWEEN 51 PRECEDING AND CURRENT ROW
            )                                                       AS Cogs52M,
            SYSUTCDATETIME()                                        AS EtlLoadDate
        FROM monthly;

        IF OBJECT_ID('gold.CogsRollingHelper') IS NOT NULL DROP TABLE gold.CogsRollingHelper;
        EXEC sp_rename 'gold.CogsRollingHelper_stg', 'CogsRollingHelper';

        ALTER TABLE gold.CogsRollingHelper
            ADD CONSTRAINT PK_gold_CogsRollingHelper
            PRIMARY KEY NONCLUSTERED (ItemSku, WarehouseCode, FiscalMonthYear) NOT ENFORCED;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;
END;
GO


PRINT '07_gold_helpers.sql complete: CogsRollingHelper proc compiled (H4 + M3 applied).';
GO
