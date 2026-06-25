# Inventory Health Mart

Project tag: `inventory_health`  
Serving schema: `SupplyChain_Gold_Warehouse.InventoryHealth_DW`  
Shared dimensions: `SupplyChain_Gold_Warehouse.Shared_DW`

## Purpose

Inventory Health measures current and forward-looking inventory risk using DA-first SupplyChain inputs, weekly snapshots, purchase/manufacturing/holding transfer signals, and shared product/warehouse/date dimensions.

## Layer Map

| Layer | Location | Notes |
|---|---|---|
| Source/Bronze | `Enterprise_Lakehouse` | Active code uses `Enterprise_Lakehouse` for current source domains, including selected `Inventory_Enh_History` and `SupplyChain_Enh` paths. No active Inventory source currently uses `SupplyChain_Lakehouse`. |
| Silver | `SupplyChain_Processing_Warehouse.InventoryHistory_Enh` | Final tables live in base schema; work/source views live in `InventoryHistory_Enh_Wrk`. |
| Gold | `SupplyChain_Gold_Warehouse.InventoryHealth_DW` | Final serving tables live in base schema; work/source views live in `InventoryHealth_DW_Wrk`. |
| Shared Gold | `SupplyChain_Gold_Warehouse.Shared_DW` | Final shared dimensions live in base schema; work/source views live in `Shared_DW_Wrk`. |
| Semantic | `sc_control_tower` direction | Semantic/report objects are shared; older per-mart semantic docs are preserved as history. |

## Key Business Outputs

| Object | Role |
|---|---|
| `InventoryHealth_DW.FactInventoryHealthSnapshot` | Main inventory health fact. |
| `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding` | Future week-ending inventory health fact. |
| `InventoryHealth_DW.ProjectedInventoryHealthSubStatus` | Projected inventory health sub-status output. |
| `InventoryHealth_DW.InventoryClassificationQtyWeekly` | Weekly classification quantity output. |
| `InventoryHealth_DW.InventoryHealthSubStatusWeekly` | Weekly inventory health sub-status output. |
| `InventoryHealth_DW.DimVendor` | Inventory vendor dimension. |
| `Shared_DW.DimCalendar` | Shared date dimension. |
| `Shared_DW.DimProduct` | Shared product dimension. |
| `Shared_DW.DimWarehouse` | Shared warehouse dimension. |

## Source Reality Check

[Verified] Live code scan on 2026-06-23 found no active Inventory Health SQL module calling `Enterprise_Lakehouse.*_1.*` or `SupplyChain_Lakehouse`.

Current active source replacements:

- `InventoryHistory_Enh.v_AFIStatusSnapshotWeekly` reads `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`; the old Dataflow Gen2 path is history only.
- `InventoryHistory_Enh.v_SupplyPlanDetail` reads `Enterprise_Lakehouse.SupplyChain_Enh.SupplyPlanDetailSnapshotDaily`; live registry metadata was aligned to the same non-`_1` source on 2026-06-23.
- No active Silver module calls the old purchase-order Dataflow Gen2 path.
- `InventoryHistory_Enh.v_ItemBalanceHistorical_WithInTransit` reads `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance`; the old Dataflow Gen2 path is history only.
- `InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical` reads `Enterprise_Lakehouse.SupplyChain_Enh.PurchaseOrderSnapshot`; the old purchase-order Dataflow Gen2 path is history only.
- `Enterprise_Lakehouse.Wholesale_ProductSourcing.NonPkItems` is active because `ReferenceMaster_Enh.v_ItemMaster` uses `npkFutureStatus` for product `FutureStatus`; Inventory Gold consumes this through shared `Shared_DW.v_DimProduct`.

Known drift:

- None for active Inventory Health source routing after the 2026-06-23 source sync. Lineage tables were not rebuilt in this step.

## Operational Run Order

Do not run alphabetically. Use the manifest in `03_operations/orchestration/inventory_health/`.

Logical order:

1. Shared/reference inputs:
   - product
   - warehouse
   - calendar
   - vendor
2. Silver snapshot/helper dependencies:
   - `ForecastSnapshotWeekly`
   - `InventorySnapshotWeekly`
   - `ManufacturingOrderSnapshotDaily`
   - `HoldingTransferSnapshotDaily`
   - `SupplyPlanDetail`
   - `ItemBalanceHistorical_WithInTransit`
   - helper outputs such as `AwdHelper`, `LastInvoiceWeekly`, `SafetyStockHelper`, `Cogs52WWeekly`
3. Gold dimensions/helpers:
   - `DimVendor`
4. Gold facts:
   - `FactInventoryHealthSnapshot`
   - `FactInventoryHealthFutureWeekEnding`
   - `InventoryClassificationQtyWeekly`
   - `InventoryHealthSubStatusWeekly`
   - `ProjectedInventoryHealthSubStatus`
5. Smoke:
   - row count/freshness
   - grain duplicate checks
   - 04_semantic/DAX smoke after report-facing changes

## Folder Contract

Current mart SQL is split by operational layer and follows ADR-009.

- [00_source_wrk/](00_source_wrk/) — `Staging_Wrk` wrappers and source-side notes.
- [01_bronze/01_enterprise_lakehouse/](01_bronze/01_enterprise_lakehouse/) — active Enterprise Lakehouse shortcut/source objects.
- [01_bronze/02_supplychain_lakehouse/](01_bronze/02_supplychain_lakehouse/) — empty marker for source separation; no active Inventory source currently uses `SupplyChain_Lakehouse`.
- [02_silver/](02_silver/) — active Silver final table contracts and `_Wrk.v_<TableName>` source views.
- [03_gold/](03_gold/) — active Gold/shared final table contracts and `_Wrk.v_<TableName>` source views.
- [04_dq/](04_dq/) — Bronze DQ contracts, exceptions, latest run summary, source evidence, and rerun SQL.
- [05_catalog/](05_catalog/) — machine-readable asset registry, lineage edges, run order, and semantic bindings.
- [99_history/aggregate_sql_pre_layer_split/](99_history/aggregate_sql_pre_layer_split/) — old aggregate SQL, registry inserts, DQ inserts, and special historical candidates.

## History

- [99_history/source_project_readme_pre_restructure.md](99_history/source_project_readme_pre_restructure.md) preserves the previous project README.
- The full pre-restructure working set remains under `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/projects/inventory_health/` until final link audit/removal approval.
