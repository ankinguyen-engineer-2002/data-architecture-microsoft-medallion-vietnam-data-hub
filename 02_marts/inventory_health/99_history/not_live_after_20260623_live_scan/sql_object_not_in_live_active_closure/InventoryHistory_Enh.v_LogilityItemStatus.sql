CREATE VIEW InventoryHistory_Enh.v_LogilityItemStatus AS
WITH ranked AS (
    SELECT
        TRIM(Item)                            AS ItemSku,
        TRIM(Whse)                            AS WarehouseCode,
        CAST(WeekEnding AS DATE)              AS WeekEndingDate,
        NULLIF(TRIM(ItemStatus), '')          AS ItemStatus,
        NULLIF(TRIM(FutureStatus), '')        AS FutureStatus,
        CAST(StatusChngDate AS DATE)          AS StatusChangeDate,
        CAST(OnHandQty AS DECIMAL(18,4))      AS OnHandQty,
        CAST(SafetyStockQty AS DECIMAL(18,4)) AS SafetyStockQty,
        CAST(ShippableInvQty AS DECIMAL(18,4)) AS ShippableInvQty,
        CAST(MosofSupply AS DECIMAL(18,4))    AS MonthsOfSupply,
        CAST(Price AS DECIMAL(18,4))          AS Price,
        TRIM(ItemClass)                       AS ItemClass,
        TRIM(Vendor)                          AS Vendor,
        TRIM(HoldBuy)                         AS HoldBuyCode,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(Item), TRIM(Whse), CAST(WeekEnding AS DATE)
            ORDER BY
                -- D1 FIX 2026-05-19 (v2): identify placeholder rows by demand-side metrics ONLY.
                -- OnHandQty đã EXCLUDED khỏi CASE vì là identity-attribute (luôn ≠ 0 trên cả 2 row dup, không phân biệt được).
                -- Verified pattern: 74.3% (6,786/9,128) groups có 1 data-row + 1 placeholder zero-row;
                --                   19.6% (1,791) both zero (drop any); 6.0% (551) both have data (tiebreaker = OnHandAmt).
                CASE WHEN COALESCE(ShippableInvQty,0) = 0
                      AND COALESCE(FirmDemand,0) = 0 THEN 1 ELSE 0 END ASC,
                StatusChngDate DESC,                       -- legacy tiebreaker (usually identical within group)
                COALESCE(OnHandAmt,0) DESC,                -- for "both have data" 6% case — pick higher inventory value
                CAST(FileDate AS DATETIME2) DESC           -- absolute last resort
        ) AS rn
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandFulfillmentCommonContainer_Logility]  -- A3 FIX 2026-05-19: was SC_LH.dbo.logility_demandfulfillment
    WHERE Item IS NOT NULL AND Whse IS NOT NULL
      AND TRIM(Item) <> '' AND TRIM(Whse) <> ''
)
SELECT
    CAST(ItemSku           AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode     AS VARCHAR(50))   AS WarehouseCode,
    CAST(WeekEndingDate    AS DATE)          AS WeekEndingDate,
    CAST(ItemStatus        AS VARCHAR(20))   AS ItemStatus,
    CAST(FutureStatus      AS VARCHAR(20))   AS FutureStatus,
    CAST(StatusChangeDate  AS DATE)          AS StatusChangeDate,
    CAST(OnHandQty         AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockQty    AS DECIMAL(18,4)) AS SafetyStockQty,
    CAST(ShippableInvQty   AS DECIMAL(18,4)) AS ShippableInvQty,
    CAST(MonthsOfSupply    AS DECIMAL(18,4)) AS MonthsOfSupply,
    CAST(Price             AS DECIMAL(18,4)) AS Price,
    CAST(ItemClass         AS VARCHAR(50))   AS ItemClass,
    CAST(Vendor            AS VARCHAR(50))   AS Vendor,
    CAST(HoldBuyCode       AS VARCHAR(10))   AS HoldBuyCode,
    CAST(1                 AS BIT)           AS IsCertified,
    CAST('Enterprise_Lakehouse'        AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility'   AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO
