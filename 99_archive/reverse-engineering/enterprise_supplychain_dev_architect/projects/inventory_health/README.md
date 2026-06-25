# inventory_health — Inventory Health Mart

> **Status (updated 2026-06-01):** LIVE · DA SQL export applied local + Fabric · Silver/Gold materialization complete · shared `DimProduct`/`DimWarehouse`/`DimCalendar` cutover complete · semantic DAX smoke passed · **Gold schema:** `InventoryHealth_DW` + shared `Shared_DW` dims
> Source: deliverable v1 (`_source_v1/`, archived gitignored). Standardized into v10 v_* views following "1 SP + N views" pattern. Current QC: data/04_semantic/DQ/pipeline evidence is green for manual/on-demand operation; physical backup/probe tables from the DA-first rebuild were cleaned after approval. Remaining stability gap is schedule auto-run confirmation plus explicit cleanup decision for legacy stale objects.

> Latest cross-mart audit: [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). That file is the source-of-truth for live row counts, shared dim contracts, pipeline run state, and residual cleanup candidates.
>
> **2026-06-15 drift note:** the current live v10 core-stack audit is now [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md). Live workspace semantic state is no longer represented by a separate deployed `sc_inventory_health_control_tower` item, and no active control-plane row now uses `project='inventoryHistory_Enh'`.

## What

End-to-end Inventory Health analytics mart on Microsoft Fabric. Combines current + weekly inventory snapshots, supply plans, purchase/manufacturing orders, sales movement history, allocated demand, and forward risk into a unified Gold serving layer for Power BI Direct Lake reporting via the `InventoryHealth` semantic model. ATP forward-looking logic was removed from the active DA-first Gold/semantic contract on 2026-06-01.

2026-05-28 DA-first update: Mart B no longer materializes or consumes `InventoryHistory_Enh.SalesShipment`. Sales history consumers read `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly. `InventorySnapshotWeekly` and `ForecastSnapshotWeekly` now follow Giang's SQL export from the DA feedback file in [artifacts/source_inputs/](artifacts/source_inputs/), with old `*Sat` candidate paths deactivated in the registry.

Phase 1 scope: 26 of 30 KPIs from BRD v1 (rest are Phase 2 — storage cube physical, warehouse-physical). 14 Track A fixes applied during 2-person QC review (2026-05-17); fixes preserved through view-conversion.

## Live infrastructure snapshot

| Item | Value |
|------|-------|
| Workspace DEV | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Processing WH | `c0262cef-b8a7-495f-bccc-53b098c7948c` (`SupplyChain_Processing_Warehouse`) |
| Gold WH | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` (`SupplyChain_Gold_Warehouse`) |
| SQL Endpoint | `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com` |
| New Schemas | Processing: `InventoryHistory_Enh` + `ProcessingSeed` reuse + existing `ReferenceMaster_Enh`; Gold: `InventoryHealth_DW` + shared `Shared_DW` |
| Views live in explorer export | **55** total warehouse views exported from live Processing + Gold metadata on 2026-06-01 |
| Active registry rows | **46** workspace-wide active rows; `inventory_health` now owns 1 active ReferenceMaster + 11 active DomainSilver + 4 active Gold rows |
| Lineage edges | **132** active registry-derived edges in `lineage_explorer/data/lineage.csv` (89 direct + 43 derived) |
| Semantic model | Historical inventory-only semantic docs remain in this folder, but current live workspace semantic state should be read from [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md) |
| Naming convention | Enterprise ETL-aligned per ADR-008: `_Enh` (Silver) / `_DW` (Gold), `v_*` view prefix |
| Control plane reuse | `Meta.AssetRegistry`, `Meta.DQRule`, `Meta.LineageEdge` (no project-specific procs) |
| Pipelines reused | 7 v10 pipelines; after the 2026-06-15 cleanup, `pl_sc_master` runs `shared` -> `forecast_accuracy` -> `inventory_health`, `pl_sc_staging` is project-filtered for ReferenceMaster, and `pl_sc_gold` is project-filtered for Gold publish |

## Live row counts

Measured 2026-06-01 from live warehouses:

| Table | Rows |
|---|---:|
| `InventoryHealth_DW.FactInventoryHealthSnapshot` | 2,739,398 |
| `InventoryHealth_DW.FactInventoryRiskForward` | 3,778,995 |
| `InventoryHealth_DW.CogsRollingHelper` | 3,092,173 |
| `Shared_DW.DimProduct` | 383,883 |
| `InventoryHealth_DW.DimItem` | 383,371 (legacy/stale physical table, semantic no longer binds here) |
| `InventoryHealth_DW.DimVendor` | 86,620 |
| `Shared_DW.DimWarehouse` | 53 |
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

## Quick links

| Section | Doc |
|---------|-----|
| Workspace + IDs | [00_workspace.md](00_workspace.md) |
| Bronze layer (32 sources: 30 Enterprise ready + 2 SC_LH workaround) | [10_bronze.md](10_bronze.md) |
| Silver layer (live active topology: 11 DomainSilver rows in physical schema `InventoryHistory_Enh`) | [20_silver.md](20_silver.md) |
| Gold layer (live active topology: 4 `InventoryHealth_DW` rows + 3 `Shared_DW` rows) | [30_gold.md](30_gold.md) |
| Pipelines (reuses existing 7) | [40_pipelines.md](40_pipelines.md) |
| Semantic model + 30 DAX | [50_semantic.md](50_semantic.md) |
| Lineage | [60_lineage.md](60_lineage.md) |
| Operational QC snapshot | [70_operational_qc_2026-05-28.md](70_operational_qc_2026-05-28.md) |
| Supporting docs and notes | [01_docs/](01_docs/) |
| Source status brief | [01_docs/mart_b_inventory_source_status_for_ai_team_2026-06-03.md](01_docs/mart_b_inventory_source_status_for_ai_team_2026-06-03.md) |
| ETL views + registry | [etl/](etl/) |
| Semantic TMDL/DAX | [04_semantic/](04_semantic/) |
| DA source input artifacts | [artifacts/source_inputs/](artifacts/source_inputs/) |
| Open questions (3 Robert + 2 DE US workaround pending + Enterprise ETL Q) | [01_docs/open_questions_for_enterprise_etl.md](01_docs/open_questions_for_enterprise_etl.md) |
| Source deliverable v1 (gitignored) | [_source_v1/](_source_v1/) |
| Dataflow setup, drafts, templates | [dataflows/](dataflows/) |

## Known operational state

| Item | Status |
|------|--------|
| ETL views authored | ✅ DONE; 12 DA SQL export view blocks applied to local + Fabric on 2026-05-28 |
| Registry rows authored | ✅ DONE; live inventory_health active rows verified 2026-05-28 |
| DQ rules authored | ✅ DONE; `Meta.usp_CheckDqSingle` threshold conversion + `Meta.usp_CheckDq` no-temp runner fixed live 2026-05-28; active DQ rules passed 29/29 manual QC |
| Semantic model TMDL ported (`gold.` → `InventoryHealth_DW.`) | ✅ DONE; `relationships.tmdl` deployed live 2026-05-28 |
| Deploy to Fabric | ✅ DONE for live DA views, Silver/Gold table rebuild, semantic refresh/smoke, registry updates, and lineage docs; latest full `pl_sc_master` success recorded 2026-05-29. |
| Bronze sources (5 originally stale/missing) | ✅ 3 EL loads (PoDetail 21.95M + PoMaster 5.69M + Logility 38.36M, Dhivya 2026-05-18, verified pyodbc 2026-05-19) + 2 SC_LH workarounds (`df_brz_ItemBalance` 48.97M + `df_brz_PurchaseOrderSnapshot` ~2B) |
| Column-deprecation finding (5 cols) | ✅ Verified zero on EDW source: ITBEXT.CRHLD/DLHLD/TOHLD/ATPQT + ITEMBL.PHYOH → planned `expected_zero` DQ rule + delete 2 reload dataflows |
| Dup classification (Rakeshbalaji Slack 2026-05-09) | ✅ Verified 2026-05-19: PoDetail = TRUE row dup (1 pair, all 53 cols identical) → ROW_NUMBER drops safely; Logility = GRAIN CONFLICT (9,128 pairs, 6 metrics differ) → view ORDER BY rewritten to prefer non-zero metrics row |
| ETL Silver source-path migration (2026-05-19) | ✅ DONE: `v_PurchaseOrder` LEFT JOIN switched to EL.PoMaster; `v_LogilityItemStatus` switched to EL.DemandFulfillmentCommonContainer_Logility + new grain-conflict ORDER BY |
| 3 Robert sign-offs (H1/H5/M3) | ⏳ email pending (see `01_docs/open_questions_for_enterprise_etl.md`) |
| PO/MO DimItemMaster coverage | ⏳ pending DE US upstream data coverage update |
| Pipeline schedule | [Need-verify] latest proof is manual completed job history; do not claim cron auto-run active until Fabric item schedule state is rechecked/enabled. |
| Alerting / CI / Schedule trigger | BLOCKED/Need-enable — same IT permission pattern as forecast |

## Track A fixes preserved through v10 port (deliverable v1 → views)

| # | Code | Where in v10 | Robert sign-off |
|---|------|--------------|---|
| 1 | H1 ItemAllocationFlag=2 | [silver_views.sql:v_AllocatedDemandCandidate](etl/silver_views.sql) | ⏳ |
| 2 | H2 ATPSUM UNPIVOT APAT01-43 | [silver_views.sql:v_AtpWeekEnding](etl/silver_views.sql) | Retired from active Gold/semantic contract 2026-06-01 after DA removed ATP forward-looking logic |
| 3 | H3 FG-only + WH exclusion | [silver_views.sql:v_InventoryCurrent](etl/silver_views.sql) | n/a (matches sếp) |
| 4 | H4 ORDER BY FiscalMonthYear | [gold_views.sql:v_CogsRollingHelper](etl/gold_views.sql) | n/a (math) |
| 5 | H5 WeekFourFlag exact week | [gold_views.sql:v_FactInventoryRiskForward](etl/gold_views.sql) | ⏳ |
| 6 | M1 Saturday DATENAME | N/A in v10 (cron handled by `Meta.ufn_should_run` + registry `cron_expression`) | n/a |
| 7 | M2 Walrus removed | N/A (no procedural SQL in v10 views) | n/a |
| 8 | M3 Cogs52W → Cogs52M | [gold_views.sql:v_CogsRollingHelper](etl/gold_views.sql) + TMDL + DAX | ⏳ |
| 9 | M4 SLOB NULL guard | [gold_views.sql:v_FactInventoryHealthSnapshot](etl/gold_views.sql) | n/a (defensive) |
| 10 | M5 AWD COUNTROWS SUMMARIZE | [04_semantic/Measures_DAX.dax](04_semantic/Measures_DAX.dax) verbatim | n/a (math) |
| 11 | B1 PoDetail Enterprise source | [silver_views.sql:v_PurchaseOrder](etl/silver_views.sql) | n/a (data switch) |
| 12 | B2 DemandForecast source | ~~v_ForecastCurrent~~ **DROPPED 2026-05-22 (orphan in Option B refactor; KPI #7 served via ForecastSnapshotWeekly history). B2 fix preserved in git history.** | n/a |
| 13 | B3 Warehouse exclusion flags | [silver_views.sql:v_WarehouseExt](etl/silver_views.sql) + v_InventoryCurrent + v_PurchaseOrder | n/a |
| 14 | M3 doc trail | inline comments in views + TMDL/DAX | n/a |

## Migration deltas vs deliverable v1

| Aspect | Deliverable v1 | v10 (this folder) |
|---|---|---|
| Silver schema | `silver` (lowercase, flat 35 tables) | `InventoryHistory_Enh` (**22 active tables post-2026-05-22 cleanup**: was 24, -2 dropped MovementHistory + ForecastCurrent, -1 deactivated LogilityItemStatusSnapshotWeekly) + `ReferenceMaster_Enh.Vendor` (NEW) |
| Gold schema | `gold` (lowercase, flat 8 tables) | `InventoryHealth_DW` (**6 active inv_health-only post-2026-05-22**: was 8, -1 dropped DimRuleVersion + -1 dropped DimDate) + 1 shared dim `Shared_DW.DimCalendar` (cross-mart) |
| Warehouse refs | `SupplyChain Processing Warehouse` (space) | `SupplyChain_Processing_Warehouse` (underscore) |
| Load orchestration | 14 custom `usp_Build_*` procs + 1 `usp_RefreshAll` | 1 generic `Meta.usp_GenericLoad` + 34 views + 33 registry rows |
| Control plane | None | Full `Meta.*` integration (registry + DQ + lineage + audit) |
| Pipeline | Manual exec | Registry-driven multi-mart via `pl_sc_master` |
| Watermark | `silver.EtlWatermark` table (5 rows) | `Meta.AssetRegistry.last_watermark_value` column |
| TMDL bind | `schemaName: gold` | `schemaName: InventoryHealth_DW` |
