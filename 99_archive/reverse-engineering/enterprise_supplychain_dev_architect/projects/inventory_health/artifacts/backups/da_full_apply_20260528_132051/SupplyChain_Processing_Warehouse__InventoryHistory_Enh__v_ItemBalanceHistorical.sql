
CREATE   VIEW InventoryHistory_Enh.v_ItemBalanceHistorical AS
-- Source: SC_LH.dbo.itembalance loaded via df_brz_ItemBalance (DF2 workaround pending EL.Inventory_Enh_History.ItemBalance promote)
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate); 107 dups detected → ROW_NUMBER dedupe by latest OnHandQty
-- History: 2021-03-06 → 2026-05-16 (5 years; replaces stale EL.DemandInventorySnapshotWeekly for historical)
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
