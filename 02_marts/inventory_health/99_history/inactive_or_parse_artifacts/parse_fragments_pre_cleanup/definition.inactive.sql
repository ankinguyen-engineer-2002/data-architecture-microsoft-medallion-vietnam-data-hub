-- ---- InventoryHistory_Enh.v_MovementHistory ---- [DROPPED 2026-05-22]
-- Reason: Tagged orphan in Option B inline refactor 2026-05-21 + watermark bug
-- (future-date 2026-11-10 → 0 rows loaded). KPI #26 Obsolete Ratio served via
-- LastInvoiceHelper (no-movement check); KPI #30 Total Commitment not wired in Phase 1.
-- To restore for Phase 2: see git history pre-2026-05-22 for full CREATE VIEW definition
-- sourcing Enterprise_Lakehouse.Manufacturing_Inventory_AFI.IMHIST via CYYMMDD date conv.


-- ---- InventoryHistory_Enh.v_AllocatedDemandCandidate ----
-- H1 FIX (2026-05-17): ItemAllocationFlag = 2 (not 1). Probe: {0:16,802; 2:901,411 rows}.
-- Robert sign-off pending — see 01_docs/open_questions_for_enterprise_etl.md.
