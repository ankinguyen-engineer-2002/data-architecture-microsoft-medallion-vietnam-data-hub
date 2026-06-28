-- InventoryHistory_Enh_Wrk.v_AFIStatusSnapshotWeekly
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_AFIStatusSnapshotWeekly] AS
WITH
_BaseFactInventory AS (
    SELECT DISTINCT
        CAST(SnapshotDate AS DATE)               AS WeekEndingDate,
        CAST(TRIM(ItemSku) AS VARCHAR(50))       AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50)) AS WarehouseCode
    FROM InventoryHistory_Enh.InventorySnapshotWeekly
    WHERE SnapshotDate IS NOT NULL
      AND ItemSku IS NOT NULL AND TRIM(ItemSku) <> ''
      AND WarehouseCode IS NOT NULL AND TRIM(WarehouseCode) <> ''
),
_LatestInventoryWeek AS (
    SELECT
        MAX(inv.WeekEndingDate) AS LatestInventorySnapshotDate
    FROM _BaseFactInventory inv
),
_LatestInventoryItemWh AS (
    SELECT
        inv.ItemSku,
        inv.WarehouseCode
    FROM _BaseFactInventory inv
    INNER JOIN _LatestInventoryWeek liw
        ON liw.LatestInventorySnapshotDate = inv.WeekEndingDate
),
_LogilityItemStatus AS (
    -- Inline raw Logility status from Enterprise source with deterministic dedupe.
    SELECT
        ItemSku,
        WarehouseCode,
        WeekEndingDate,
        ItemStatus
    FROM (
        SELECT
            TRIM(Item)               AS ItemSku,
            TRIM(Whse)               AS WarehouseCode,
            CAST(WeekEnding AS DATE) AS WeekEndingDate,
            NULLIF(TRIM(ItemStatus), '') AS ItemStatus,
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
        WHERE WeekEnding IS NOT NULL
          AND Item IS NOT NULL AND TRIM(Item) <> ''
          AND Whse IS NOT NULL AND TRIM(Whse) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
_LogilityWeekly AS (
    SELECT
        CAST(WeekEndingDate AS DATE)               AS WeekEndingDate,
        CAST(TRIM(ItemSku) AS VARCHAR(50))         AS ItemSku,
        CAST(TRIM(WarehouseCode) AS VARCHAR(50))   AS WarehouseCode,
        NULLIF(TRIM(CAST(ItemStatus AS VARCHAR(20))), '') AS StatusFromLogility
    FROM _LogilityItemStatus
    WHERE WeekEndingDate IS NOT NULL
      AND ItemSku IS NOT NULL AND TRIM(ItemSku) <> ''
      AND WarehouseCode IS NOT NULL AND TRIM(WarehouseCode) <> ''
),
_LogilityLatestByWh AS (
    SELECT
        ItemSku,
        WarehouseCode,
        NULLIF(TRIM(CAST(ItemStatus AS VARCHAR(20))), '') AS StatusFromLogilityLatestWH
    FROM (
        SELECT
            CAST(TRIM(ItemSku) AS VARCHAR(50))         AS ItemSku,
            CAST(TRIM(WarehouseCode) AS VARCHAR(50))   AS WarehouseCode,
            ItemStatus,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(ItemSku), TRIM(WarehouseCode)
                ORDER BY CAST(WeekEndingDate AS DATE) DESC
            ) AS rn
        FROM _LogilityItemStatus
        CROSS JOIN _LatestInventoryWeek liw
        WHERE WeekEndingDate IS NOT NULL
          AND WeekEndingDate <= liw.LatestInventorySnapshotDate
          AND ItemSku IS NOT NULL AND TRIM(ItemSku) <> ''
          AND WarehouseCode IS NOT NULL AND TRIM(WarehouseCode) <> ''
    ) ranked
    WHERE ranked.rn = 1
),
_BaseFact AS (
    SELECT
        WeekEndingDate,
        ItemSku,
        WarehouseCode
    FROM _BaseFactInventory

    UNION

    SELECT
        liw.LatestInventorySnapshotDate AS WeekEndingDate,
        inv.ItemSku,
        inv.WarehouseCode
    FROM _LatestInventoryItemWh inv
    CROSS JOIN _LatestInventoryWeek liw
    WHERE liw.LatestInventorySnapshotDate IS NOT NULL
),
_ItemMaster AS (
    SELECT
        CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSku,
        NULLIF(TRIM(CAST(AFIItemStatus AS VARCHAR(20))), '') AS StatusFromItemMaster
    FROM ReferenceMaster_Enh.ItemMaster
    WHERE ItemSKU IS NOT NULL AND TRIM(ItemSKU) <> ''
)
SELECT
    b.WeekEndingDate,
    b.ItemSku,
    b.WarehouseCode,
    CAST(
        CASE
            WHEN b.WeekEndingDate = liw.LatestInventorySnapshotDate
                THEN im.StatusFromItemMaster
            ELSE COALESCE(lw.StatusFromLogility, ll.StatusFromLogilityLatestWH)
        END
        AS VARCHAR(20)
    ) AS AFIStatus,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM _BaseFact AS b
CROSS JOIN _LatestInventoryWeek AS liw
LEFT JOIN _LogilityWeekly AS lw
    ON lw.WeekEndingDate = b.WeekEndingDate
   AND lw.ItemSku = b.ItemSku
   AND lw.WarehouseCode = b.WarehouseCode
LEFT JOIN _LogilityLatestByWh AS ll
    ON ll.ItemSku = b.ItemSku
   AND ll.WarehouseCode = b.WarehouseCode
LEFT JOIN _ItemMaster AS im
    ON im.ItemSku = b.ItemSku;
