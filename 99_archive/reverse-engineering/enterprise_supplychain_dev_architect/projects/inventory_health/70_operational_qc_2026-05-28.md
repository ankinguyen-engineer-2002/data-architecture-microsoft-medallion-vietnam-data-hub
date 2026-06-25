# 70 — Operational QC Snapshot

> **Snapshot date:** 2026-05-28; refreshed addendum 2026-06-01  \
> **Scope:** Fabric workspace control plane, pipeline schedules/history, `Meta.*` registry, lineage explorer CSVs, Gold/Silver row counts, and live semantic model smoke tests.  \
> **Verdict:** DA SQL export applied to live + local Silver views, DA-first Silver/Gold materialization completed, semantic refresh/smoke passed, and lineage docs refreshed. 2026-06-01 addendum: latest `pl_sc_master` success is recorded for 2026-05-29 with `12 succeeded, 0 failed`; physical backup/probe tables from the DA-first rebuild were dropped after approval. Remaining gaps are schedule auto-run verification and explicit cleanup decisions for legacy stale objects.

## 2026-06-01 Addendum

| Check | Result |
|---|---|
| Full master pipeline | [Verified] `pl_sc_master` run `24942a8b-1750-4f96-9bfc-23fecac90952` succeeded on 2026-05-29 16:15:29→17:27:22 UTC with `12 succeeded, 0 failed`. |
| Forecast semantic | [Verified] `DimProduct=383,883`, `DimWarehouse=53`, `DimCalendar=21,551`, `FactForecastKpi=115,757,696`, `FactForecastActual=138,509,914`. |
| Inventory semantic | [Superseded 2026-06-01] After DA-first Gold rebuild: `CogsRollingHelper=3,092,173`, `FactInventoryHealthSnapshot=2,739,398`, `FactInventoryRiskForward=3,778,995`; `FactInventoryRiskForward` no longer exposes ATP columns. |
| Shared dims | [Verified] `Shared_DW.DimCalendar`, `Shared_DW.DimProduct`, and `Shared_DW.DimWarehouse` exist and are visible in live SQL/catalog. |
| Residual cleanup | [Verified] DA-first backup/probe tables dropped after approval on 2026-06-01; legacy stale candidates remain. See [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). |

## Evidence Sources

- [Verified] Fabric REST `items`, pipeline schedules, and job instances in workspace `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`.
- [Verified] Warehouse SQL endpoint via `pyodbc` + Azure token against `SupplyChain_Processing_Warehouse` and `SupplyChain_Gold_Warehouse`.
- [Verified] Power BI ExecuteQueries against semantic model `sc_inventory_health_control_tower` (`88c3fccd-698d-4175-b7b9-ea377e0f5afc`).
- [Verified] Lineage explorer CSVs refreshed from live active `Meta.v_sp_registry` / `Meta.AssetRegistry`, `sys.sql_modules`, and `Meta.RunLog`.
- [Verified] Microsoft Fabric docs: scheduler supports list/create/update/delete schedules and job instances; semantic model TMDL definitions use a `definition/relationships.tmdl` root file.

## Control Plane

| Area | Live state | QC result |
|---|---|---|
| Workspace item scan | 146 Fabric items, including 17 DataPipelines, 7 SemanticModels, 6 Warehouses, 3 Lakehouses | [Verified] Workspace reachable and item inventory current |
| Active Mart B pipeline set | `pl_sc_master`, `pl_sc_mart`, `pl_sc_staging`, `pl_sc_silver`, `pl_sc_silver_wave`, `pl_sc_gold`, `pl_dq_check` | [Verified] Current item IDs captured in [40_pipelines.md](40_pipelines.md) |
| `pl_sc_master` latest verified successful run | `24942a8b-1750-4f96-9bfc-23fecac90952`, `success`, 2026-05-29 16:15:29→17:27:22 UTC | [Verified] `12 succeeded, 0 failed`. Older cancelled/failed runs remain in history and are listed in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). |
| `pl_sc_staging` latest job samples | `Completed` | [Verified] Fabric REST job samples on 2026-06-01 show completed runs. |
| `pl_sc_silver` latest job samples | `Completed` | [Verified] Fabric REST job samples on 2026-06-01 show completed runs. |
| `pl_sc_silver_wave` latest job samples | `Completed` | [Verified] Fabric REST job samples on 2026-06-01 show completed runs. |
| `pl_sc_gold` latest job samples | `Completed` | [Verified] Fabric REST job samples on 2026-06-01 show completed runs. |
| `pl_dq_check` latest job samples | `Completed` | [Verified] Fabric REST job samples on 2026-06-01 show completed runs; older failed runs remain in history. |

## Scheduling

| Pipeline | Schedule state | QC result |
|---|---|---|
| `pl_sc_master` | [Need-verify] schedule state was not re-queried in the 2026-06-01 audit | Do not claim cron auto-run active until Fabric item schedule state is checked/enabled |
| `pl_sc_mart`, `pl_sc_staging`, `pl_sc_silver`, `pl_sc_silver_wave`, `pl_sc_gold`, `pl_dq_check` | No direct schedules | [Verified] Expected if master orchestrates |
| Legacy `pl_slv_daily` | 2 enabled schedules, latest scheduled run completed 2026-05-28 02:20 UTC | [Verified] Not the v10 `pl_sc_master` path; avoid treating it as Mart B proof |

## Registry And Frequencies

| Layer | Active rows | Frequency/load state | Last load state |
|---|---:|---|---|
| `ReferenceMaster_Enh` | 1 | monthly overwrite | `Vendor` last loaded 2026-05-19 |
| `InventoryHistory_Enh` | 12 active + 5 inactive | daily/weekly mix: datekey, overwrite, incremental, daterange | DA-first active Silver rows were manually rebuilt 2026-05-28 |
| `InventoryHealth_DW` | 6 active | daily overwrite facts/helpers + monthly dims | `FactInventoryHealthSnapshot` registry refreshed 2026-05-28 after targeted current-partition rebuild; actual Gold tables have data |

Known inactive inventory rows:
- [Verified] `PurchaseOrderSnapshotHistorical` is inactive Phase 2 because the SC_LH workaround is ~2B rows.
- [Verified] `LogilityItemStatusSnapshotWeekly` is inactive Phase 2 conditional.
- [Superseded 2026-06-01] `ForecastSnapshotWeeklySat` and `InventorySnapshotWeeklySat` were dropped after DA-first active path was confirmed on `ForecastSnapshotWeekly` and `InventorySnapshotWeekly`.

## Lineage

| Check | Result |
|---|---|
| Live registry-derived lineage export | [Verified] 132 active edges from current registry metadata: 89 direct + 43 derived |
| Lineage explorer CSV refresh | [Verified] `lineage.csv` 132 data rows, `registry.csv` 46 active rows, `views.csv` 55 view definitions, `run_history.csv` 50 rows |
| Bad references | [Verified] 0 live references to `SalesShipment` or `DimAFIWarehouses` in registry/lineage/view exports |
| Silver DAG runtime | [Verified] inventory_health waves recomputed 2026-05-28 after DA dependency updates; `ForecastSnapshotWeekly` is wave 0, `InventorySnapshotWeekly` wave 1, FactBase/helpers wave 2 |

## Row Count Smoke Test

| Table | Rows |
|---|---:|
| `InventoryHealth_DW.FactInventoryHealthSnapshot` | 2,739,398 after DA-first rebuild 2026-06-01 |
| `InventoryHealth_DW.FactInventoryRiskForward` | 3,778,995 after DA-first rebuild 2026-06-01 |
| `InventoryHealth_DW.CogsRollingHelper` | 3,092,173 after DA-first rebuild 2026-06-01 |
| `Shared_DW.DimProduct` | 383,883 |
| `InventoryHealth_DW.DimItem` | 383,371 legacy/stale physical |
| `InventoryHealth_DW.DimVendor` | 86,620 |
| `InventoryHealth_DW.DimWarehouse` | 53 |
| `InventoryHistory_Enh.InventorySnapshotWeekly` | 97,190,388 |
| `InventoryHistory_Enh.ForecastSnapshotWeekly` | 465,306,850 |
| `InventoryHistory_Enh.InventorySnapshotWeeklyFactBase` | 60,823,881 |
| `InventoryHistory_Enh.AwdHelper` | 2,027,989 |
| `InventoryHistory_Enh.LastInvoiceHelper` | 4,826,943 |
| `InventoryHistory_Enh.MovementFlagHelper` | 1,280,109 |
| `InventoryHistory_Enh.SafetyStockHelper` | 3,011,057 |
| `InventoryHistory_Enh.PurchaseOrderSnapshotDaily` | 66,092,083 |
| `InventoryHistory_Enh.HoldingTransferSnapshotDaily` | 3,634 |
| `InventoryHistory_Enh.ManufacturingOrderSnapshotDaily` | 1,463,617 |
| `SalesHistory_Enh.InvoiceDetailLineLevel` | 128,572,413 |

## Semantic Smoke Test

| DAX check | Result |
|---|---:|
| `COUNTROWS(FactInventoryHealthSnapshot)` | 2,739,398 after DA-first rebuild 2026-06-01 |
| `COUNTROWS(FactInventoryRiskForward)` | 3,778,995 after DA-first rebuild 2026-06-01 |
| `COUNTROWS(DimProduct)` | 383,883 |
| `COUNTROWS(DimWarehouse)` | 53 |
| `COUNTROWS(DimCalendar)` | 21,551 |
| `COUNTROWS(CogsRollingHelper)` | 3,092,173 after DA-first rebuild 2026-06-01 |

[Verified] The live semantic model has active relationships after deploying `definition/relationships.tmdl`. 2026-06-01 smoke confirms the semantic table is `DimProduct` sourced from `Shared_DW.DimProduct`, not old `InventoryHealth_DW.DimItem`.

## DQ Smoke Test

| Layer | Result |
|---|---:|
| `ReferenceMaster` | PASS |
| `DomainSilver` | PASS |
| `Gold` | PASS |
| Active DQ rules | 29/29 PASS |

[Verified] Manual run id `manual_qc_20260528_after_dq_cleanup` passed after disabling stale DomainSilver rules for view-only/non-materialized objects and correcting DA schema checks (`ForecastSnapshotWeekly.SnapshotWeekEndingDate`, `ItemBalanceHistorical` composite grain).

## DA Feedback Mapping

| DA feedback item | Live result | Status |
|---|---|---|
| Remove Mart B `SalesShipment`; use `SalesHistory_Enh.v_InvoiceDetailLineLevel` | Helpers and COGS use `v_InvoiceDetailLineLevel`; registry/lineage/view exports have no active `SalesShipment` reference | [Verified] Done |
| `AwdHelper` as-of current date + DA forecast/source mapping | Uses `CAST(SYSUTCDATETIME() AS DATE)`, `ForecastSnapshotWeekly`, `InventorySnapshotWeekly` make/buy/source mapping, and invoice silver fallback | [Verified] Done |
| `LastInvoiceHelper` and `MovementFlagHelper` use invoice silver directly | Both read `SalesHistory_Enh.v_InvoiceDetailLineLevel` | [Verified] Done |
| `ForecastSnapshotWeekly` old weekly source stale | Live/local `v_ForecastSnapshotWeekly` now reads `Staging.DemandForecastSnapshotDaily` Saturday snapshots; `ForecastSnapshotWeeklySat` dropped 2026-06-01 | [Verified] Done |
| `InventorySnapshotWeekly` should use daily Saturday snapshots, not ItemBalance backup/backfill | Live/local `v_InventorySnapshotWeekly` now reads `DemandInventorySnapshotDaily`, outputs `SnapshotWeekEndingDate`, `MakeBuyCode`, `SourceWarehouseCode`; table rebuilt | [Verified] Done |
| PO dedupe and PK includes `VendorNumber` | `PurchaseOrderSnapshotDaily` includes `VendorNumber`; table has 66,092,083 rows as of 2026-06-01 audit | [Verified] Done |
| Manufacturing daily snapshot history | `ManufacturingOrderSnapshotDaily` active datekey snapshot has 1,463,617 total rows as of 2026-06-01 audit | [Verified] Done |
| `HoldingTransferSnapshotDaily`: DA sheet says remove `HCANCL = 'N'` | Live `v_HoldingTransferSnapshotDaily` has no `HCANCL='N'` filter; physical table has 3,634 rows as of 2026-06-01 audit | [Verified] View fixed and table materialized |
| `PurchaseOrderSnapshotDaily`: DA sheet says remove direct/RP warehouse exclusion and remove PoMaster vendor join condition | Live `v_PurchaseOrderSnapshotDaily` has no `podwarehouse NOT IN (...)` and joins `PoMaster` by `PoNumber` only; physical table has 66,092,083 rows as of 2026-06-01 audit | [Verified] View fixed and table materialized |
| PO/MO supply values missing because DimItemMaster lacks some item/location keys | Logic preserved; upstream DE US item master coverage still pending | [Need-verify] External blocker |

## Final Blockers Before Calling The Whole System Stable

1. [Need-verify] Enable/switch the intended v10 master schedule only after Fabric item schedule ownership/state is confirmed.
2. [Need-verify] Reconcile local semantic source-control drift: live semantic has `CogsRollingHelper`; local `04_semantic/SemanticModel.tmdl` currently does not include that table block.
3. [Need-verify] DE US still needs to improve DimItemMaster coverage for PO/MO item/location keys; current logic intentionally preserves source behavior and exposes the data gap.
4. [Verified] Deprecated candidate physical tables/views `ForecastSnapshotWeeklySat` and `InventorySnapshotWeeklySat` were dropped on 2026-06-01 after exact approval; active DA-first flow uses `ForecastSnapshotWeekly` and `InventorySnapshotWeekly`.
