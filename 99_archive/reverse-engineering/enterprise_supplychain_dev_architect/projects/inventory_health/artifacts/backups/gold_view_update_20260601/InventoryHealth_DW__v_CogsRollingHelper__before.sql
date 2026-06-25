-- ---- InventoryHealth_DW.v_CogsRollingHelper ----
-- Hidden helper. Monthly COGS + 52M/12M rolling.
-- H4 FIX (2026-05-17): ORDER BY FiscalMonthYear (chronological YYYYMM), NOT FiscalMonth (1-12 cycle).
-- M3 FIX (2026-05-17): renamed Cogs52W → Cogs52M (monthly grain).
--   Robert sign-off pending: keep 52M (current) or rewrite weekly grain.
CREATE   VIEW InventoryHealth_DW.v_CogsRollingHelper AS
WITH _CostCurrent AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.CostCurrent
    SELECT ItemSku, CostId, StandardCost, ItemRevision
    FROM (
        SELECT
            TRIM(ITNBR)                          AS ItemSku,
            TRIM(STID)                           AS CostId,
            CAST(UCDEF AS DECIMAL(18,4))         AS StandardCost,
            CAST(ITRV  AS VARCHAR(20))           AS ItemRevision,
            ROW_NUMBER() OVER (PARTITION BY TRIM(STID), TRIM(ITNBR) ORDER BY ITRV DESC) AS rn
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
        WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
          AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
monthly AS (
    SELECT
        CAST(TRIM(s.ItemSKU) AS VARCHAR(50)) AS ItemSku,
        s.WarehouseCode,
        d.FSCMonthYearNum                                                  AS FiscalMonthYear,
        SUM(s.QtyShipped * ISNULL(c.StandardCost, 0))                 AS PeriodCogs,
        SUM(s.QtyShipped)                                             AS PeriodShippedQty
    FROM [SupplyChain_Processing_Warehouse].[SalesHistory_Enh].[v_InvoiceDetailLineLevel] s
    JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
         ON d.[Date] = s.InvoiceDate
    LEFT JOIN _CostCurrent c
         ON c.ItemSku = s.ItemSKU
    GROUP BY s.ItemSKU, s.WarehouseCode, d.FSCMonthYearNum
)
SELECT
    CAST(ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(FiscalMonthYear   AS INT)           AS FiscalMonthYear,
    CAST(PeriodCogs        AS DECIMAL(18,4)) AS PeriodCogs,
    CAST(PeriodShippedQty  AS DECIMAL(18,4)) AS PeriodShippedQty,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear  -- H4 FIX: chronological YYYYMM, not 1-12 cycle
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4))                      AS Cogs12M,
    CAST(SUM(PeriodCogs) OVER (
        PARTITION BY ItemSku, WarehouseCode
        ORDER BY FiscalMonthYear  -- H4 FIX
        ROWS BETWEEN 51 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(18,4))                      AS Cogs52M   -- M3 FIX: renamed from Cogs52W
FROM monthly