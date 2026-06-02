# Live Audit — 2026-06-01

> Scope: workspace `SupplyChain Dev` (`c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`), `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse`, Forecast Accuracy mart, Inventory Health mart, shared Gold dimensions, pipelines, registry, lineage, DQ, and Direct Lake semantic models.
>
> Evidence was collected on 2026-06-01 via Fabric REST item/job scan, Warehouse SQL endpoint queries through Azure token, and Power BI `executeQueries` smoke tests against the two live semantic models.

## Executive Verdict

| Area | Status | Evidence |
|---|---|---|
| Forecast semantic | [Verified] healthy | `sc_forecast_control_tower` DAX smoke passes; counts match live Gold/shared tables. |
| Inventory semantic | [Verified] healthy | `sc_inventory_health_control_tower` DAX smoke passes after shared `DimProduct` / `DimWarehouse` / `DimCalendar` consolidation. |
| Shared dimensions | [Verified] live | `Shared_DW.DimCalendar`, `Shared_DW.DimProduct`, `Shared_DW.DimWarehouse` exist and are used by both semantic models. |
| Mart A reference seed cleanup | [Verified] live | `ForecastCycle` and `ForecastHorizon` now source from `ProcessingSeed`, not SupplyChain Lakehouse/manual seed split. |
| Mart B DA-first refactor | [Verified] live | DA SQL export paths are live; `SalesShipment` is not active; PO/MO/daily snapshot paths are materialized. |
| Full pipeline orchestration | [Verified] last full master success on 2026-05-29 | Fabric job and `Meta.PipelineRunLog` show `pl_sc_master` completed 2026-05-29 16:15:29 -> 17:27:22 UTC, 12 succeeded / 0 failed. |
| Schedule auto-run | [Need-verify] not proven active | No `Meta` schedule table exists. Fabric job history confirms manual successes; item schedule state must be checked from Fabric UI/API before claiming cron is active. |
| Residual cleanup | [Verified] backup/probe cleaned; stale candidates remain | Physical backup/probe tables from the DA-first rebuild were dropped after explicit approval on 2026-06-01. Remaining candidates are legacy/stale functional objects listed below. |

## Live Fabric Items

| Item | Live ID | Notes |
|---|---|---|
| `SupplyChain_Processing_Warehouse` | `c0262cef-b8a7-495f-bccc-53b098c7948c` | Processing/control-plane warehouse. |
| `SupplyChain_Gold_Warehouse` | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` | Gold serving warehouse for Direct Lake. |
| `Enterprise_Lakehouse` | `584e7d2c-46ca-49dc-bb6c-68df6ef4f424` | Lakehouse item. |
| `Enterprise_Lakehouse` SQL endpoint | `22bf1a2c-6810-4228-b69b-7a0f7853cd73` | SQL endpoint item. |
| `sc_forecast_control_tower` | `f06a2361-15fd-4f91-9d37-941fefe62aaf` | Forecast Direct Lake semantic model. |
| `sc_inventory_health_control_tower` | `88c3fccd-698d-4175-b7b9-ea377e0f5afc` | Inventory Health Direct Lake semantic model. |
| `df_ref_forecast_cycle` | `880eb520-7e27-4250-9392-b37e691c0555` | Dataflow patched to write `ProcessingSeed.ForecastCycle`. Latest manual refresh completed 2026-06-01. |

## Pipeline Inventory

| Pipeline | Live ID | Latest observed state |
|---|---|---|
| `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | [Verified] latest jobs include Completed runs; `Meta.PipelineRunLog` has success on 2026-05-29. |
| `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | [Verified] latest jobs Completed. |
| `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | [Verified] latest jobs Completed. |
| `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | [Verified] latest jobs Completed. |
| `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | [Verified] latest jobs Completed. |
| `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | [Verified] latest jobs Completed. |
| `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | [Verified] latest jobs Completed; older failures remain in history. |

`Meta.PipelineRunLog` latest full master evidence:

| Run | Status | UTC window | Message |
|---|---|---|---|
| `24942a8b-1750-4f96-9bfc-23fecac90952` | success | 2026-05-29 16:15:29 -> 17:27:22 | `12 succeeded, 0 failed` |
| `34fc6f12-9027-4437-9aae-6ed0b604115b` | success | 2026-05-28 12:35:01 -> 13:48:02 | `12 succeeded, 0 failed` |
| `771c140c-7fc1-46ad-bff0-fd372a68da9c` | cancelled | 2026-05-28 03:48:10 -> 03:58:10 | Cancelled by operator during live apply. |
| `3393c7a3-bfc6-49d3-b203-ec0467f400dc` | failed | 2026-05-27 17:09:26 -> 18:10:15 | Old `DimAFIWarehouses` issue before later fixes. |

## Mart A — Forecast Accuracy

### Processing / Silver

| Object | Rows | Notes |
|---|---:|---|
| `ProcessingSeed.ForecastCycle` | 43 | [Verified] seed now lives in Processing Warehouse. |
| `ProcessingSeed.ForecastHorizon` | 8 | [Verified] manual seed now lives in Processing Warehouse. |
| `ReferenceMaster_Enh.ForecastCycle` | 43 | [Verified] loaded from `ReferenceMaster_Enh.v_ForecastCycle`; view maps seed to business contract. |
| `ReferenceMaster_Enh.ForecastHorizon` | 8 | [Verified] loaded from `ReferenceMaster_Enh.v_ForecastHorizon`. |
| `ReferenceMaster_Enh.Warehouse` | 53 | [Verified] rebuilt from current warehouse source. |
| `ForecastHistory_Enh.ForecastDemandMonthly` | 138,004,165 | [Verified] latest successful `RunLog` 2026-05-29. |
| `ForecastHistory_Enh.NaiveForecastMonthly` | 208,492 | [Verified] latest successful `RunLog` 2026-05-29. |
| `SalesHistory_Enh.InvoiceDetailLineLevel` | 128,572,413 | [Verified] latest successful `RunLog` 2026-05-29. |
| `SalesHistory_Enh.ActualDemandMonthly` | 297,257 | [Verified] latest successful `RunLog` 2026-05-29. |
| `SalesHistory_Enh.ActualDemandWeekly` | 616,274 | [Verified] latest successful `RunLog` 2026-05-29. |
| `SalesHistory_Enh.InvoiceWeekly` | 15,644,636 | [Verified] latest successful `RunLog` 2026-05-29. |

### Gold / Semantic

| Object | Rows | Columns | Notes |
|---|---:|---:|---|
| `ForecastAccuracy_DW.FactForecastActual` | 138,509,914 | 10 | [Verified] physical fact live. |
| `ForecastAccuracy_DW.FactForecastKpi` | 115,757,696 | 19 | [Verified] physical fact live. |
| `ForecastAccuracy_DW.DimCustomerGrouping` | 35,617 | 3 | [Verified] mart-specific dim. |
| `ForecastAccuracy_DW.DimForecastHorizon` | 8 | 3 | [Verified] mart-specific dim. |
| `ForecastAccuracy_DW.DimProduct` | 381,163 | 207 | [Verified] legacy physical table remains inactive/stale candidate. |
| `ForecastAccuracy_DW.v_DimProduct` | 383,883 | 218 | [Verified] compatibility view reads `Shared_DW.DimProduct`. |
| `Shared_DW.DimProduct` | 383,883 | 218 | [Verified] canonical shared product dimension. |
| `Shared_DW.DimWarehouse` | 53 | 20 | [Verified] shared warehouse dimension; semantic display contract restored. |
| `Shared_DW.DimCalendar` | 21,551 | 75 | [Verified] shared calendar dimension. |

Forecast semantic DAX smoke:

```text
DimProductRows   = 383,883
DimWarehouseRows = 53
DimCalendarRows  = 21,551
FactKpiRows      = 115,757,696
FactActualRows   = 138,509,914
```

## Mart B — Inventory Health

### DA-First Silver Paths

| Object | Rows | Columns | Status |
|---|---:|---:|---|
| `InventoryHistory_Enh.ForecastSnapshotWeekly` | 465,306,850 | 11 | [Verified] active DA-first weekly forecast path from daily Saturday snapshots. |
| `InventoryHistory_Enh.InventorySnapshotWeekly` | 97,190,388 | 16 | [Verified] active DA-first weekly inventory path from daily Saturday snapshots. |
| `InventoryHistory_Enh.InventorySnapshotWeeklyFactBase` | 60,823,881 | 15 | [Verified] active fact base. |
| `InventoryHistory_Enh.ItemBalanceHistorical` | 48,968,402 | 8 | [Verified] active SC_LH workaround until EL history is promoted. |
| `InventoryHistory_Enh.PurchaseOrderSnapshotDaily` | 66,092,083 | 19 | [Verified] active datekey snapshot; includes `VendorNumber`. |
| `InventoryHistory_Enh.ManufacturingOrderSnapshotDaily` | 1,463,617 | 12 | [Verified] active datekey snapshot. |
| `InventoryHistory_Enh.HoldingTransferSnapshotDaily` | 3,634 | 26 | [Verified] active datekey snapshot; DA residual filter fixed. |
| `InventoryHistory_Enh.AwdHelper` | 2,027,989 | 19 | [Verified] direct invoice silver reuse. |
| `InventoryHistory_Enh.LastInvoiceHelper` | 4,826,943 | 6 | [Verified] direct invoice silver reuse. |
| `InventoryHistory_Enh.MovementFlagHelper` | 1,280,109 | 6 | [Verified] direct invoice silver reuse. |
| `InventoryHistory_Enh.SafetyStockHelper` | 3,011,057 | 7 | [Verified] active helper. |

### Gold / Semantic

| Object | Rows | Columns | Notes |
|---|---:|---:|---|
| `InventoryHealth_DW.FactInventoryHealthSnapshot` | 2,739,398 | 53 | [Verified] active Gold fact rebuilt 2026-06-01 from DA-first view. |
| `InventoryHealth_DW.FactInventoryRiskForward` | 3,778,995 | 22 | [Verified] active Gold fact rebuilt 2026-06-01; ATP output columns removed per DA. |
| `InventoryHealth_DW.CogsRollingHelper` | 3,092,173 | 7 | [Verified] hidden semantic helper rebuilt 2026-06-01; reads Mart A invoice silver path. |
| `InventoryHealth_DW.DimVendor` | 86,620 | 2 | [Verified] active inventory-specific dim. |
| `InventoryHealth_DW.DimItem` | 383,371 | 20 | [Verified] stale legacy physical table; semantic no longer binds to it. |
| `InventoryHealth_DW.v_DimItem` | 383,883 | 20 | [Verified] compatibility view from `Shared_DW.DimProduct`. |
| `Shared_DW.DimProduct` | 383,883 | 218 | [Verified] semantic table name is `DimProduct`; replaces old Inventory `DimItem`. |
| `Shared_DW.DimWarehouse` | 53 | 20 | [Verified] shared warehouse dim used by Inventory and Forecast. |
| `Shared_DW.DimCalendar` | 21,551 | 75 | [Verified] shared calendar dim used by Inventory and Forecast. |

Inventory semantic DAX smoke:

```text
DimProductRows   = 383,883
DimWarehouseRows = 53
DimCalendarRows  = 21,551
CogsRows         = 3,092,173
FactRows         = 2,739,398
RiskRows         = 3,778,995
ShippableRows    = 1,996,512
```

## Shared Dimension Contracts

### `Shared_DW.DimProduct`

```text
Enterprise_Lakehouse.MasterData_DW.DimItemMaster
  + Enterprise_Lakehouse.Purchasing_AFI.VendorMaster
  + Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT
      -> Shared_DW.v_DimProduct
      -> Shared_DW.DimProduct
      -> Forecast semantic table DimProduct
      -> Inventory semantic table DimProduct
```

[Verified] `Shared_DW.DimProduct` is the canonical shared item/product dimension: 383,883 rows / 218 columns. It expands the old inventory `DimItem` contract from 20 columns while preserving forecast compatibility. Inventory-specific fields verified live include `Cubes`, `UnavailableFlag`, `FOBArcPrice`, `PrimaryVendorName`, and `PrimaryVendorDisplayName`.

Column-level smoke:

| Column | Live type | Null status |
|---|---|---|
| `ItemSKU` | varchar | used as canonical key. |
| `Cubes` | decimal | 1 null row out of 383,883. |
| `FOBArcPrice` | decimal | available for Inventory risk/value logic. |
| `UnavailableFlag` | bit | 0 null rows. |
| `PrimaryVendorDisplayName` | varchar(200) | populated where vendor join covers source. |

### `Shared_DW.DimWarehouse`

```text
ReferenceMaster_Enh.Warehouse
  + Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster
      -> Shared_DW.v_DimWarehouse
      -> Shared_DW.DimWarehouse
      -> Forecast semantic DimWarehouse
      -> Inventory semantic DimWarehouse
```

[Verified] `WarehouseLocation` is the report display label and is no longer collapsed to a single `D` bucket. `WarehouseType` remains a separate source/type field.

### `Shared_DW.DimCalendar`

```text
Enterprise_Lakehouse.MasterData_DW.DimDate
  -> ReferenceMaster_Enh.Calendar
  -> Shared_DW.v_DimCalendar
  -> Shared_DW.DimCalendar
  -> Forecast semantic DimCalendar
  -> Inventory semantic DimCalendar
```

[Verified] shared calendar exists in Explorer and query surface as `Shared_DW.DimCalendar`. The earlier Explorer visibility issue was Fabric UI metadata refresh/cache, not object absence.

## Control Plane / Registry

`Meta.AssetRegistry` is live in `SupplyChain_Processing_Warehouse`, not Gold. The schema currently uses v10 column names:

```text
asset_id, legacy_target_schema, legacy_target_table, legacy_view_name,
canonical_layer, physical_item, physical_schema, physical_object,
project, frequency, cron_expression, load_type, depends_on,
source_objects, is_enterprise_reusable, is_active, last_load_date, rows_loaded
```

Important current rows:

| Asset | Active | Rows loaded / last load | Notes |
|---|---:|---|---|
| `Shared_DW.DimProduct` | 1 | 383,883 / 2026-05-29 08:33 UTC | Shared product canonical. |
| `Shared_DW.DimWarehouse` | 1 | 53 / 2026-05-29 10:59 UTC | Shared warehouse canonical. |
| `Shared_DW.DimCalendar` | 1 | 21,551 / 2026-05-29 04:32 UTC | Shared calendar canonical. |
| `InventoryHealth_DW.DimItem` | 0 | null | Stale legacy physical table remains, but registry inactive. |
| `InventoryHealth_DW.DimWarehouse` | 0 | 53 / 2026-05-27 | Stale legacy registry row inactive after shared dim cutover. |
| `ForecastAccuracy_DW.DimProduct` | 0 | 999 / 2026-05-10 | Stale legacy physical table remains, registry inactive. |
| `ForecastAccuracy_DW.DimWarehouse` | 0 | 53 / 2026-05-27 | Stale legacy registry row inactive after shared dim cutover. |

## DQ State

Latest `Meta.DQGateRun` rows show:

- [Verified] Reference checks passed on 2026-05-28 for `Calendar`, `ItemMaster`, `ForecastHorizon`, `Vendor`, and staging checks.
- [Verified] Inventory and Forecast manual QC rows passed after DA cleanup on 2026-05-28.
- [Verified] `pl_dq_check` latest Fabric job instances include Completed runs.
- [Need-verify] Older failed DQ job instances remain in Fabric history (`varchar` to numeric conversion and snapshot isolation conflict). Treat history as fixed-but-auditable, not absent.

## Residual / Cleanup Candidates

These are live objects that are not part of the intended current active flow. Backup/probe tables from the DA-first rebuild were dropped after explicit approval on 2026-06-01; rollback now relies on local view/semantic backups under `projects/inventory_health/artifacts/backups/`.

| Object | Rows | Why it remains | Recommended action |
|---|---:|---|---|
| `InventoryHealth_DW.DimItem` | 383,371 | Stale physical table from pre-shared `DimProduct` flow. | Drop candidate after semantic/report review; semantic now uses `DimProduct`. |
| `ForecastAccuracy_DW.DimProduct` | 381,163 | Stale physical table from pre-shared `DimProduct` flow. | Drop candidate after ensuring no report binds directly to physical table outside semantic. |
| `InventoryHistory_Enh.LogilityItemStatusSnapshotWeekly` | 100,227 | Inactive Phase 2 conditional path. | Keep unless Robert/DA confirms no past item-status tracking. |
| `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical` | 0 | Inactive Phase 2 historical path. | Drop candidate or keep as placeholder; destructive approval required. |

## Metadata / Lineage Residuals

[Verified] Current active flow works. On 2026-06-01, registry/source metadata for `FactInventoryRiskForward` and `CogsRollingHelper` was fixed in `Meta.AssetRegistry` without rerunning `pl_sc_master`. `lineage_explorer/data/*.csv` was refreshed from live active registry/view/run metadata after the DA-first rebuild and backup cleanup.

| Metadata item | Current state | Impact |
|---|---|---|
| `InventoryHealth_DW.DimItem` registry row | inactive, still present | Harmless for pipeline execution; confusing in docs if not called legacy. |
| `ForecastAccuracy_DW.DimProduct` registry row | inactive, still present | Harmless for pipeline execution; confusing because `v_DimProduct` now reads shared dim. |
| `FactInventoryRiskForward.source_objects` | fixed 2026-06-01 | Now points to live inlined sources: `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail`, `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail`, `Shared_DW.DimProduct`, `Shared_DW.DimCalendar`. `ATPSUM`/`AtpWeekEnding` retired from active Gold/semantic contract. |
| `CogsRollingHelper.source_objects` | fixed 2026-06-01 | Now points to live inlined COGS source `Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA`, plus `SalesHistory_Enh.v_InvoiceDetailLineLevel` and `Shared_DW.DimCalendar`. |
| `InventoryHealth_DW.DimWarehouse` lineage row | inactive target still exists in registry metadata history | Should be marked legacy/shared-cutover in docs; do not treat as semantic dependency. |
| `lineage_explorer/data/*.csv` | refreshed 2026-06-01 from live active registry/view/run metadata | Local lineage explorer now reflects the DA-first rebuild, ATP retirement, and dropped backup/Sat objects. |
| Inventory local `SemanticModel.tmdl` | fixed 2026-06-01 | Local source file now contains hidden `table CogsRollingHelper` block matching the live semantic contract. |

## DA Feedback Mapping

| DA / review item | Current status |
|---|---|
| Replace DA SQL blocks for Inventory Silver | [Verified] applied to live Fabric views and local SQL files. |
| Remove Mart B `SalesShipment` active path | [Verified] active helpers use `SalesHistory_Enh.v_InvoiceDetailLineLevel`. |
| Forecast weekly from daily Saturday path | [Verified] `ForecastSnapshotWeekly` active; old `ForecastSnapshotWeeklySat` dropped 2026-06-01. |
| Inventory weekly from daily Saturday path | [Verified] `InventorySnapshotWeekly` active; old `InventorySnapshotWeeklySat` dropped 2026-06-01. |
| PO snapshot with `VendorNumber` and DA join/filter corrections | [Verified] `PurchaseOrderSnapshotDaily` active with 66,092,083 rows. |
| MO daily snapshot history | [Verified] `ManufacturingOrderSnapshotDaily` active with 1,463,617 rows. |
| Holding transfer DA residual filter | [Verified] active daily snapshot rebuilt; row count 3,634. |
| Shared `DimProduct` instead of Mart B `DimItem` | [Verified] inventory semantic table is `DimProduct`, sourced from `Shared_DW.DimProduct`. |
| Shared `DimWarehouse` instead of mart-specific duplicate dims | [Verified] both semantic models use `Shared_DW.DimWarehouse`. |
| Shared `DimCalendar` instead of duplicate date/calendar dims | [Verified] both semantic models use `Shared_DW.DimCalendar`. |

## Data Flow Diagram

```text
Enterprise_Lakehouse
  |-- MasterData_DW.DimDate ---------------------> ReferenceMaster_Enh.Calendar
  |                                                  -> Shared_DW.DimCalendar
  |
  |-- MasterData_DW.DimItemMaster ----------------\
  |-- Purchasing_AFI.VendorMaster -----------------+-> Shared_DW.DimProduct
  |-- ItemMaster_AFI.ITBEXT ----------------------/
  |
  |-- CustomerOrders_AFI.WarehouseMaster ---------> ReferenceMaster_Enh.Warehouse
  |-- Wholesale_Codis_AFI.AshleyWarehouseMaster --/
                                                     -> Shared_DW.DimWarehouse

ProcessingSeed.ForecastCycle --------------------> ReferenceMaster_Enh.ForecastCycle
ProcessingSeed.ForecastHorizon ------------------> ReferenceMaster_Enh.ForecastHorizon

SalesHistory_Enh / ForecastHistory_Enh ----------> ForecastAccuracy_DW facts
InventoryHistory_Enh DA-first snapshots/helpers --> InventoryHealth_DW facts/helpers

Shared_DW dims + mart facts ---------------------> Direct Lake semantic models
```

## Next Cleanup Gate

Before dropping any remaining residual objects:

1. Confirm exact object list.
2. Export definitions and row counts to a dated backup folder.
3. Confirm no semantic model, report, view, registry active row, or lineage active edge depends on the object.
4. Drop only after explicit approval in the same conversation.
5. Refresh lineage CSVs and run both semantic smoke tests again.
