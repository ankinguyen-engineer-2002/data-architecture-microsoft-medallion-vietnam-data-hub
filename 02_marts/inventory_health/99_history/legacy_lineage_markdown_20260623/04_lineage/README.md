# 60 — Lineage

> **Status (updated 2026-06-01):** live DA-first registry/view state plus shared dimension consolidation audited. `SalesShipment` and `DimAFIWarehouses` are not part of the active Mart B flow. Registry/lineage for `FactInventoryRiskForward` and `CogsRollingHelper` was aligned to the live inlined Gold view sources on 2026-06-01 without rerunning the full pipeline. Physical backup/probe tables were cleaned after approval; residual inactive/legacy objects are documented in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md).

## How lineage works in v10

Each row in `Meta.AssetRegistry` carries a `source_objects` JSON array listing upstream entities. `Meta.usp_BuildLineage` runs `STRING_SPLIT` on each row to produce direct lineage edges in `Meta.LineageEdge`:

```sql
INSERT INTO Meta.LineageEdge (source_asset, target_asset, edge_type, transform_type, ...)
SELECT TRIM(src.value), r.asset_id, 'direct', r.load_type, ...
FROM Meta.AssetRegistry r
CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(r.source_objects,'[',''),']',''), ',') src
WHERE r.source_objects IS NOT NULL
```

## Live lineage snapshot (2026-06-01)

| Check | Result |
|---|---|
| Active registry-derived CSV edges | 132 total: 89 direct + 43 derived |
| `Meta.LineageEdge` / CSV snapshots | [Need-verify] snapshots can contain inactive/legacy compatibility edges; use `Meta.AssetRegistry.is_active` and the 2026-06-01 audit before interpreting old targets like `InventoryHealth_DW.DimItem` |
| Semantic edges | managed separately by semantic lineage tooling |
| Synthetic edges | 0 |
| Active registry rows exported | [Verified] 46 active rows exported from live `Meta.v_sp_registry` |
| View definitions exported | 55 |
| Successful run-history rows exported | 50 |
| Bad old refs | 0 references to `SalesShipment` or `DimAFIWarehouses` |

CSV refresh read live `Meta.v_sp_registry`, derived active direct and same-schema dependency edges from registry metadata, read `sys.sql_modules`, and read `Meta.RunLog`, then wrote:
- `03_operations/apps/lineage_explorer/data/lineage.csv`
- `03_operations/apps/lineage_explorer/data/registry.csv`
- `03_operations/apps/lineage_explorer/data/views.csv`
- `03_operations/apps/lineage_explorer/data/run_history.csv`

## Cross-mart edges

Lineage shows inventory_health depends on shared infrastructure and Mart A invoice silver:
- `ReferenceMaster_Enh.*` shared masters where the registry declares reuse.
- `SalesHistory_Enh.v_InvoiceDetailLineLevel` for helper/COGS invoice history.
- `Shared_DW.DimCalendar` in 04_semantic/Gold calendar usage.
- `Shared_DW.DimProduct` in 04_semantic/Gold product usage; both Forecast Accuracy and Inventory Health now bind to the same physical product dimension. Inventory semantic table name is `DimProduct`, not `DimItem`.
- `Staging.DemandForecastSnapshotDaily` for DA-first `ForecastSnapshotWeekly`.
- `Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily` for DA-first `InventorySnapshotWeekly`.
- `Enterprise_Lakehouse.SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` for `SupplyPlanDetail`; active SQL code and active `Meta.AssetRegistry.source_objects` now use the non-`_1` schema. Registry-derived lineage was not rebuilt in this step.
- `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance` for `ItemBalanceHistorical_WithInTransit`; the old SupplyChain Lakehouse/Dataflow Gen2 source is no longer active.

This is intentional — `ReferenceMaster_Enh` is shared infrastructure.

No active DA-first flow should depend on Mart B `InventoryHistory_Enh.SalesShipment`.

## Residual lineage/metadata caveats

| Item | Status | Why documented |
|---|---|---|
| `InventoryHealth_DW.DimItem` | Inactive registry row + stale physical table remain | Semantic now binds `DimProduct` to `Shared_DW.DimProduct`; old object is cleanup candidate. |
| `InventoryHealth_DW.DimWarehouse` | Inactive registry row remains; physical table absent | Semantic now binds `DimWarehouse` to `Shared_DW.DimWarehouse`. |
| `ForecastAccuracy_DW.DimProduct` | Inactive legacy physical table remains | Forecast semantic uses `Shared_DW.DimProduct` through `v_DimProduct`. |
| `FactInventoryRiskForward` source lineage | Fixed 2026-06-01 | Registry and direct lineage edges now point to live inlined sources: `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail`, `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail`, `Shared_DW.DimProduct`, `Shared_DW.DimCalendar`. `ATPSUM`/`AtpWeekEnding` is retired from the active Gold/semantic contract after DA removed ATP forward-looking logic. |
| `CogsRollingHelper` source lineage | Fixed 2026-06-01 | Registry and direct lineage edges now point to `SalesHistory_Enh.v_InvoiceDetailLineLevel`, `Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA`, and `Shared_DW.DimCalendar`. |

## Visualization

Lineage edges are consumed by the Streamlit app at `03_operations/apps/lineage_explorer/`. Current CSVs were refreshed from live active registry/view/run metadata on 2026-06-01 after the DA-first Gold rebuild and backup cleanup. Open the app and toggle the `project='inventory_health'` filter.

## Rebuild trigger

`usp_BuildLineage` runs automatically at end of `pl_sc_master` (in `usp_FinalizePipeline`). Manual rebuild:
```sql
EXEC Meta.usp_BuildLineage;
```

This deletes all `edge_type IN ('direct','derived')` rows and recomputes from registry. `edge_type='semantic'` rows (TMDL-derived) are preserved (managed by `build_semantic_model_lineage.py`). Do not run the rebuild in production without confirming the current registry state and expected blast radius.
