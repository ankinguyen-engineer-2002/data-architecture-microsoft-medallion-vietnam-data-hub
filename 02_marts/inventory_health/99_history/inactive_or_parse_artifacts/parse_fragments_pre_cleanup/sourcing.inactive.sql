-- ---- InventoryHistory_Enh.v_ForecastCurrent ---- [DROPPED 2026-05-22]
-- Reason: Tagged orphan in Option B inline refactor 2026-05-21. KPI #7 Forecast
-- Demand Qty served via ForecastSnapshotWeekly (history) + DAX aggregations; the
-- "current overlay" path via SupplyForecast/DemandForecast was scaffolded but never
-- wired into FactInventoryHealthSnapshot or DAX measures.
-- To restore for Phase 2 current overlay: see git history pre-2026-05-22 for full
-- CREATE VIEW sourcing Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.DemandForecast.

GO


-- ============================================================
-- §D. InventoryHistory_Enh — Tier 2 snapshot history (2 views, incremental)
-- ============================================================
