# Missing table candidates search — SupplyChain_Enh (2026-06-17)

Queries ran against: `SupplyChain_Processing_Warehouse` → `Enterprise_Lakehouse`.

## Schemas existence
- Present: `SupplyChain_Enh`, `SupplyChain_DW`
- Missing (not found in Enterprise_Lakehouse): `SupplyChain_Enh_1`, `SupplyChain_DW_1`

## SupplyChain_Enh candidates
- DemandForecastSnapshotDaily-like:
  - `SupplyChain_Enh.DemandForecastSnapshotDaily` (max `dfcSnapshot` = 2026-06-02)
  - `SupplyChain_Enh.DemandForecastSnapshotDaily_1` (max `dfcSnapshot` = 2025-10-31)
- SupplyPlanDetailSnapshotDaily-like:
  - `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` (exists; no `_1` variant)
- PurchaseOrderSnapshot-like:
  - `SupplyChain_Enh.PurchaseOrderSnapshot` (exists)
- ATPWeekEnding-like:
  - `SupplyChain_Enh.ATPWeekEnding` (exists)

## ItemBalance search (global)
- No tables found where `TABLE_NAME` contains `ItemBalance` or `Balance` anywhere under `Enterprise_Lakehouse`.
