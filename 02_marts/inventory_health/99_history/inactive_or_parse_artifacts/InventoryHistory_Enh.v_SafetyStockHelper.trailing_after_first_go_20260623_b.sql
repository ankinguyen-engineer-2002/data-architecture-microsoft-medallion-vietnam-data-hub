-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ---- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily ----
