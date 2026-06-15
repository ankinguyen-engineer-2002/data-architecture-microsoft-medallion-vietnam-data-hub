## Short message — Slack/Teams to Dhivya / DE US team

---

Hi @Dhivya, flagging some data quality issues we found on EL tables. Sharing for your review.

- `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotWeekly`
  - **[DUPLICATED]** every bucket has exactly 2 identical rows → `SUM(dfcResultantForecast)` inflated 2× vs Daily.
  - **[LOAD FROZEN]** no new snapshot since 2024-03-25 (~14 months stale, frozen at 306M rows).
  - **[WRONG SNAPSHOT DAY]** snapshots are captured on Monday, but BRD requires week-ending Saturday. Any way to switch the upstream Logility export to Saturday cadence?

- `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotDaily`
  - **[DUPLICATED]** row-level dup started Q1 2025, peaking 27× in Q4 2025. Avg SUM inflated ~6.6× across 2025+ data.

- `Enterprise_Lakehouse.SalesHistory_AFI.InvoiceHeader`
  - **[HISTORY TRUNCATED]** only 6 months loaded (2025-11-17 → 2026-05-19, 4M rows). `SalesHistory_AFI.InvoiceDetail` counterpart has 9 years (2017-08 onwards, 88M rows). Result: ~96% LeadTime NULL downstream.

- `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` (consumed as `DimProduct` in Mart A)
  - **[MISSING COLUMNS]** 383K rows × 174 cols. Vs legacy v9 master (~373K rows × 89 cols): row count matches, but **30 cols from v9 don't exist in EL** (e.g. `SKProduct`, `ColorName`, `SeriesCode`, `ChildStyleName`, `MarketingStatusName`, `CexCode`). Filled with NULL stubs in `ForecastAccuracy_DW.v_DimProduct` for now.

Could you investigate root causes + let us know when fixes are expected? Happy to share probe SQL if helpful.

— Aric (VN SC DA team)
