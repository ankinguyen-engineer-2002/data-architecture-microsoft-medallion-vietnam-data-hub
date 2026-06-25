-- ---- InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly ----
-- WEEKLY — Saturday only (cron '0 6 * * 6' in registry).
-- Full history output (one row per ItemSku + WarehouseCode + WeekEndingDate, after dedupe).
CREATE OR ALTER VIEW InventoryHistory_Enh.v_LogilityItemStatusSnapshotWeekly AS
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
    CAST(WeekEndingDate                             AS DATE)         AS WeekEndingDate,
    CAST(ItemSku                                  AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                            AS VARCHAR(50))  AS WarehouseCode,
    CAST(ItemStatus                               AS VARCHAR(20))  AS ItemStatus,
    CAST(FutureStatus                             AS VARCHAR(20))  AS FutureStatus,
    CAST(StatusChangeDate                         AS DATE)         AS StatusChangeDate,
    CAST(IsCertified                              AS BIT)          AS IsCertified,
    CAST('Enterprise_Lakehouse'                   AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility' AS VARCHAR(128)) AS SourceTable
FROM _LogilityItemStatus

GO
