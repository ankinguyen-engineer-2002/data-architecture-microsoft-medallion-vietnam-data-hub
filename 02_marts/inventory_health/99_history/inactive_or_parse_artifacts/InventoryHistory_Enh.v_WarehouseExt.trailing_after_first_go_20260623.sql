-- ============================================================
-- §C. InventoryHistory_Enh — Tier 1 base tables (12 views)
-- ============================================================

-- ---- InventoryHistory_Enh.v_CostCurrent ----
-- ITMRVA dedupe (STID+ITNBR, STID='000'). Pick latest by ITRV DESC.
