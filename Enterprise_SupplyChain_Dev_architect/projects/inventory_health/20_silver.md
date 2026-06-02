# 20 — Silver Layer

> **Status (updated 2026-06-01):** LIVE + DA-first Mart B cleanup applied + shared dim cutover audited + latest full master run green. See [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md) for current row counts and residual cleanup candidates.
>
> **2026-05-22 cleanup**:
> - **DROPPED 2 view-only Silvers** tagged orphan in Option B refactor 2026-05-21:
>   - `v_MovementHistory` (KPI #26 Obsolete Ratio served via `LastInvoiceHelper` no-movement check; KPI #30 not in Phase 1)
>   - `v_ForecastCurrent` (KPI #7 Forecast Demand Qty served via `ForecastSnapshotWeekly` history)
> - **DEACTIVATED Phase 2** `LogilityItemStatusSnapshotWeekly` (is_active=0) — KPI #17/#18/#20a past-tracking conditional pending Robert sign-off; current item status path via `DimItemMaster.AFIItemStatus`.
>
> **2026-05-28 DA-first refactor**: all 12 SQL blocks from `InventoryHistory_Enh_silver_view_sql_export 2.md` were applied to local source and live Fabric views. `InventoryHistory_Enh.SalesShipment` is removed from the active Mart B flow; helpers reuse `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly per DA `Silver_Check` feedback.
>
> **2026-05-19 source switches preserved**: `v_PurchaseOrder` main/join paths read EL `PoDetail` + `PoMaster`; `v_LogilityItemStatus` reads EL `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` with deterministic grain-conflict dedupe.
>
> **DA residual cleanup 2026-05-28:** live snapshot views remove `HCANCL='N'`, remove PO direct/RP warehouse exclusion, and remove `PoMaster` vendor join condition. `InventorySnapshotWeekly` now uses `DemandInventorySnapshotDaily` Saturday rows with `SnapshotWeekEndingDate`, `MakeBuyCode`, and `SourceWarehouseCode`; `ForecastSnapshotWeekly` now uses `Staging_Wrk.DemandForecastSnapshotDaily` Saturday rows. Active Silver tables were manually materialized after the view replacement.

## Schemas

| Schema | Layer | New for inventory_health? | Active count |
|---|---|---|---:|
| `ReferenceMaster_Enh` | ReferenceMaster | +1 NEW (Vendor) | 1 |
| `InventoryHistory_Enh` | DomainSilver | NEW SCHEMA | 22 active (was 24; -2 dropped 2026-05-22) |

Total: 23 active Silver assets (was 25 pre-cleanup).

## §A. ReferenceMaster_Enh — 1 NEW

| Asset | View | Load type | Source |
|---|---|---|---|
| `Vendor` | `v_Vendor` | overwrite (monthly) | `Enterprise_Lakehouse.Purchasing_AFI.VendorMaster` (51 cols, 86.6K rows) |

REUSED from existing ReferenceMaster_Enh (do NOT recreate):
- `ItemMaster` (sources `MasterData_DW.DimItemMaster`)
- `Warehouse` (sources `CustomerOrders_AFI.WarehouseMaster`)
- `Calendar` (sources `MasterData_DW.DimDate`)

## §B. InventoryHistory_Enh — Master extensions (2 NEW views over existing reuses)

| Asset | View | Load type | Base reuse | Extensions added |
|---|---|---|---|---|
| `ItemMasterExt` | `v_ItemMasterExt` | overwrite (monthly) | `ReferenceMaster_Enh.ItemMaster` | `PrimaryVendorName` (JOIN VendorMaster) + `UnavailableFlag` (MAX MFPUS='U' from ITBEXT) |
| `WarehouseExt` | `v_WarehouseExt` | overwrite (monthly) | `ReferenceMaster_Enh.Warehouse` | B3 fix flags: `IsExcludedDirectCustomerRP`, `IsNetworkInventoryWarehouse`, `TotalAvailableWarehouseCube` |

## §C. InventoryHistory_Enh — Tier 1 base (12 views)

| Asset | View | Load type | Watermark / Key | Source(s) | Track A fix |
|---|---|---|---|---|---|
| `CostCurrent` | `v_CostCurrent` | overwrite (daily) | PK: ItemSku | ITMRVA (STID='000') | — |
| `InventoryCurrent` | `v_InventoryCurrent` | datekey (daily) | PK: (ItemSku,WarehouseCode,SnapshotDate) | ITEMBL | **H3** (FG-only) + **B3** (WH exclusion) |
| `SupplyPlan` | `v_SupplyPlan` | overwrite (daily) | PK: composite | SupplyPlanDetail | — |
| ~~`SalesShipment`~~ | — | **REMOVED 2026-05-28** | — | Reuse `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly | DA-first removal of duplicate Mart B materialization |
| `PurchaseOrder` | `v_PurchaseOrder` | overwrite (daily) | PK: (PoNumber,PoLine,**VendorNumber**) | EL.PoDetail (21.95M) + EL.PoMaster (5.69M) | **B1** (EL PoDetail) + **B1.2** (EL PoMaster, switched 2026-05-19); DA 2026-05-28 removes direct/RP warehouse exclusion and removes `PoMaster` vendor join condition; 1 true-row-dup handled by ROW_NUMBER; PK still includes VendorNumber because PoDetail reuses `(PoNumber,PoLine)` across vendors |
| `ManufacturingOrder` | `v_ManufacturingOrder` | overwrite (daily) | PK: (MoNumber,ItemSku,WarehouseCode) | MOMAST | — (L3 pending Robert) |
| `LogilityItemStatus` | `v_LogilityItemStatus` | overwrite (weekly) | PK: composite | EL.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility (38.36M, switched 2026-05-19) | **A3** RESOLVED + **D1** dedupe (9,128 grain-conflict groups handled by demand-bearing prefer heuristic) |
| `HoldingTransfer` | `v_HoldingTransfer` | overwrite (daily) | PK: (TransferNumber,ItemSku) | TFRDTL + TFRHDR | DA 2026-05-28 keeps cancelled rows and exposes `CancelFlag` for downstream logic |
| ~~`AtpWeekEnding`~~ | `v_AtpWeekEnding` | inactive / retired | PK: (ItemSku,WarehouseCode,WeekNumber) | ATPSUM (UNPIVOT APAT01-43) | Retired from active Gold/semantic contract 2026-06-01 after DA removed ATP forward-looking logic |
| ~~`MovementHistory`~~ | ~~`v_MovementHistory`~~ | **DROPPED 2026-05-22** (orphan; KPI #26 via LastInvoiceHelper) | — | — | — |
| `AllocatedDemandCandidate` | `v_AllocatedDemandCandidate` | overwrite (daily) | PK: (OrderNumber,OrderLine) | OpenOrderDetail + OpenOrderHeader | **H1** (Robert pending) |
| ~~`ForecastCurrent`~~ | ~~`v_ForecastCurrent`~~ | **DROPPED 2026-05-22** (orphan; KPI #7 via ForecastSnapshotWeekly) | — | — | B2 fix preserved in git |

## §D. InventoryHistory_Enh — Tier 2 snapshot history (2 views, incremental)

| Asset | View | Watermark | Source |
|---|---|---|---|
| `InventorySnapshotWeekly` | `v_InventorySnapshotWeekly` | overwrite | `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotDaily` Saturday rows; no `ItemBalanceHistorical` backup/backfill |
| `ForecastSnapshotWeekly` | `v_ForecastSnapshotWeekly` | overwrite | `Staging_Wrk.DemandForecastSnapshotDaily` Saturday rows; `ForecastQty = ResultantForecast + PromotionalLift` |
| `InventorySnapshotWeeklyFactBase` | `v_InventorySnapshotWeeklyFactBase` | SnapshotDate | compatibility adapter over DA `InventorySnapshotWeekly` for Gold fact grain |
| ~~`ForecastSnapshotWeeklySat`~~ | — | dropped 2026-06-01 | DA export made `ForecastSnapshotWeekly` the active Saturday path; local deploy script no longer recreates the old candidate |
| ~~`InventorySnapshotWeeklySat`~~ | — | dropped 2026-06-01 | DA export made `InventorySnapshotWeekly` the active Saturday path |

## §E. InventoryHistory_Enh — Tier 3 helpers (4 views, overwrite daily)

Grain: `(ItemSku, WarehouseCode, AsOfDate)` where current AsOfDate uses `CAST(SYSUTCDATETIME() AS DATE)` and weekly history uses DA `InventorySnapshotWeekly`.

| Asset | View | Purpose | Depends on |
|---|---|---|---|
| `AwdHelper` | `v_AwdHelper` | AWD = 3 fiscal months forecast + dependent demand; fallback historical 13W shipped | ITEMBL inline, InventorySnapshotWeekly, ForecastSnapshotWeekly, SalesHistory_Enh.v_InvoiceDetailLineLevel |
| `LastInvoiceHelper` | `v_LastInvoiceHelper` | MAX(InvoiceDate) ≤ AsOfDate | InventorySnapshotWeekly, SalesHistory_Enh.v_InvoiceDetailLineLevel |
| `MovementFlagHelper` | `v_MovementFlagHelper` | HasMovementLast17W boolean | InventorySnapshotWeekly, SalesHistory_Enh.v_InvoiceDetailLineLevel |
| `SafetyStockHelper` | `v_SafetyStockHelper` | Carry SafetyStockTarget at AsOfDate | InventorySnapshotWeekly |

## §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)

| Asset | View | Date key | Cron / registry frequency | Notes |
|---|---|---|---|---|
| `PurchaseOrderSnapshotDaily` | `v_PurchaseOrderSnapshotDaily` | SnapshotDate | daily datekey | depends on PurchaseOrder; includes `VendorNumber` in snapshot grain |
| `ManufacturingOrderSnapshotDaily` | `v_ManufacturingOrderSnapshotDaily` | SnapshotDate | daily datekey | depends on ManufacturingOrder |
| `HoldingTransferSnapshotDaily` | `v_HoldingTransferSnapshotDaily` | SnapshotDate | daily datekey | depends on HoldingTransfer |
| `LogilityItemStatusSnapshotWeekly` ⏸ | `v_LogilityItemStatusSnapshotWeekly` | WeekEndingDate | weekly Sat 06:00 | **DEACTIVATED 2026-05-22** (Phase 2 conditional — KPI #17/#18/#20a past-tracking pending Robert) — depends on LogilityItemStatus |

## DAG (Silver) — wave computation

After registry insert, run `EXEC Meta.usp_ComputeSilverWaves`. Expected waves (computed from `depends_on`):

- **Wave 0** — active source-independent snapshot/base assets, including DA `ForecastSnapshotWeekly`
- **Wave 1** — DA `InventorySnapshotWeekly`
- **Wave 2** — `InventorySnapshotWeeklyFactBase` + DA helpers
- **Wave 3+** — active self-snapshot and Gold-dependent assets per live `Meta.v_sp_registry`

Live `Meta.SilverDagWaveRuntime` was recomputed 2026-05-28 after DA dependency updates.

2026-06-01 live materialization evidence after DA SQL export apply:
- `InventorySnapshotWeekly`: 97,190,388 rows.
- `ForecastSnapshotWeekly`: 465,306,850 rows.
- `InventorySnapshotWeeklyFactBase`: 60,823,881 rows.
- `AwdHelper`: 2,027,989 rows; `LastInvoiceHelper`: 4,826,943; `MovementFlagHelper`: 1,280,109; `SafetyStockHelper`: 3,011,057.
- `HoldingTransferSnapshotDaily`: 3,634 rows.
- `PurchaseOrderSnapshotDaily`: 66,092,083 rows.
- `ManufacturingOrderSnapshotDaily`: 1,463,617 rows.

Each wave runs sequentially; assets within a wave run in parallel (batch=8).

## Track A fix carry-over

All Silver-side Track A fixes preserved as inline comments in `etl/silver_views.sql`. Search the file for `H[0-9] FIX`, `M[0-9] FIX`, or `B[0-9] FIX` to verify.

## File reference

- [etl/silver_views.sql](etl/silver_views.sql) — 25 CREATE VIEW statements
- [etl/registry_inserts.sql](etl/registry_inserts.sql) — 25 Silver registry rows
- [etl/dq_rules_inserts.sql](etl/dq_rules_inserts.sql) — 20+ Silver DQ rules
