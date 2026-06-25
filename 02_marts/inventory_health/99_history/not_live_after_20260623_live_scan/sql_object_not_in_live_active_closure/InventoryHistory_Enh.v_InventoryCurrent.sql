-- ---- InventoryHistory_Enh.v_InventoryCurrent ----
-- ITEMBL on-hand snapshot. Daily reload via datekey load_type (registry).
-- H3 FIX (2026-05-17): FG-only filter (ItemClassCode like Z%K) — 99.98% match vs 32% w/o
-- B3 FIX (2026-05-17): exclude direct-to-customer/RP warehouses
-- BLOCKED: Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL needs full DE US load — flag in registry is_active=0 initially.
CREATE VIEW InventoryHistory_Enh.v_InventoryCurrent AS
SELECT
    CAST(TRIM(b.ITNBR)              AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(b.HOUSE)              AS VARCHAR(50))   AS WarehouseCode,
    CAST(b.MOHTQ                    AS DECIMAL(18,4)) AS OnHandQty,
    CAST(TRIM(b.ITCLS)              AS VARCHAR(50))   AS ItemClassCode,
    CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATE)      AS SnapshotDate,
    CAST('ItemMaster_AFI'           AS VARCHAR(64))   AS SourceSystem,
    CAST('ITEMBL'                   AS VARCHAR(128))  AS SourceTable
FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITEMBL] b
WHERE b.ITNBR IS NOT NULL AND b.HOUSE IS NOT NULL
  AND TRIM(b.ITNBR) <> '' AND TRIM(b.HOUSE) <> ''
  -- H3 FIX: FG-only per BRD §6.5 / sheet R21
  AND LEFT(TRIM(b.ITCLS), 1) = 'Z'
  AND RIGHT(TRIM(b.ITCLS), 1) = 'K'
  -- B3 FIX: WH exclusion list (direct-to-customer / RP)
  AND TRIM(b.HOUSE) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')

GO
