# Final Enterprise ETL Runtime Architecture

> Scope: `Enterprise SupplyChain-Dev` current DEV operating architecture after Phase 1 Enterprise ETL migration closeout and 2026-06-24 full wrapper validation.

## Executive Summary

This repo now documents and operates a Microsoft Fabric SupplyChain value-stream platform that keeps the existing Bronze/Silver/Gold business product surface, but replaces the runtime/control-plane path with the Enterprise ETL Framework contract.

The short version:

```text
Sources / Enterprise lakehouse shortcuts
  -> Bronze/source projection
  -> Silver processing warehouse
  -> Gold serving warehouse
  -> shared 04_semantic/report layer

Operationally controlled by:
  Enterprise SupplyChain-Dev.ETL_Framework.DW_Developer
    -> TableDictionary
    -> AuditLog
    -> TableDictionary_UpdateLog
    -> Enterprise ETL loader/wrapper stored procedures
```

Final operational handoff:

```text
SQL Server Agent / external scheduler
  -> SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver
  -> SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold
  -> SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver
  -> SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold
```

## Non-Negotiable Design Boundary

The migration was not a business rewrite.

| Area | Decision |
|---|---|
| Business SQL logic | Preserve unless a future mart-specific requirement explicitly changes it. |
| Bronze/Silver/Gold layer shape | Preserve. |
| View/table names consumed by downstream logic | Preserve. |
| Semantic/report contracts | Preserve. |
| Runtime/control plane | Move to Enterprise ETL-aligned `ETL_Framework`. |
| VN `Meta.*` control plane | Fallback/evidence/extension surface; not the target primary runtime after Phase 1. |

## Workspace And Item Map

| Layer | Fabric item | Current role |
|---|---|---|
| Bronze/source | `Enterprise_Lakehouse` | Shortcut/source aggregation layer for enterprise data domains. |
| Framework | `ETL_Framework` | Enterprise ETL-aligned runtime/control-plane warehouse in `Enterprise SupplyChain-Dev`. |
| Silver/processing | `SupplyChain_Processing_Warehouse` | Current staging, reference, domain Silver, and legacy `Meta` evidence surface. |
| Gold/serving | `SupplyChain_Gold_Warehouse` | Direct Lake serving warehouse with mart-specific and shared schemas. |
| Analytics | `sc_control_tower` | Current shared semantic model direction for multiple marts. |

Known current workspace ID:

```text
Enterprise SupplyChain-Dev = c8d9fc83-18b6-4e1d-8264-0b49eed36fe0
```

## Enterprise ETL Framework Contract

Enterprise ETL's documentation describes `ETL_Framework` as a shared framework deployed across workspaces. The relevant concepts for this repo are:

| Enterprise ETL concept | Meaning in this repo |
|---|---|
| `DW_Developer.TableDictionary` | Registry of objects, refresh method, source/target, SLA/freshness, row count, and operational metadata. |
| `DW_Developer.AuditLog` | Procedure execution log. Every approved loader path should leave start/complete/error evidence here. |
| `DW_Developer.TableDictionary_UpdateLog` | Append/update trail for metadata changes and load freshness. |
| `_Wrk` schema | Working/source view surface. This is where source projection lives before loader materializes final tables. |
| `_LOAD` table | Transient loader work table used by Enterprise ETL refresh patterns. It is not a business table. |
| final table | Stable physical business table name consumed by downstream views/Gold/semantic. |

The important naming correction from Phase 1:

```text
Wrong / deprecated:
  Staging_Wrk_Wrk.v_DemandForecastSnapshotDaily

Canonical:
  Staging_Wrk.v_DemandForecastSnapshotDaily   -- source wrapper
  Staging.DemandForecastSnapshotDaily         -- target table
```

The canonical incremental contract for that large staging table is:

```text
Target       = SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
Source       = SupplyChain_Processing_Warehouse.Staging_Wrk.v_DemandForecastSnapshotDaily
Procedure    = ETL_Framework.DW_Developer.usp_IncrementalTableLoad
UpdateMethod = DateRange
DateKey      = dfcSnapshot
Window       = 30 days
```

## Current Medallion Shape

### Bronze / Source

Bronze is not a rewrite target. It remains the source/shortcut layer exposed through `Enterprise_Lakehouse`.

Current enterprise source domains used by active mart lineage include:

- `CustomerOrders_AFI`
- `Customers`
- `DemandPlanning_AFI`
- `ItemMaster_AFI`
- `MasterData_DW`
- `Purchasing_AFI`
- `SalesHistory_AFI`
- `SupplyChain_DW`
- `SupplyChain_Enh`
- `Wholesale_Codis_AFI`
- `Wholesale_DemandPlanning_AFI`
- `Wholesale_ProductSourcing_AFI`
- `Wholesale_Purchasing_AFI`
- `Wholesale_SalesHistory_AFI`

Forecast Accuracy source clarification from the 2026-06-23 live check:

- active Forecast runtime does not read `SupplyChain_Lakehouse`;
- `ReferenceMaster_Enh.ForecastCycle` and `ReferenceMaster_Enh.ForecastHorizon` read Processing-owned seed tables under `ProcessingSeed`;
- post-cleanup `ETL_Framework.DW_Developer.TableDictionary` active curated rows point to `_Wrk.v_*` source views with no active error rows.

### Silver / Processing

Silver lives in `SupplyChain_Processing_Warehouse`.

Current processing schemas:

| Schema | Role |
|---|---|
| `Staging_Wrk` | Enterprise ETL working/source views and exception source wrappers. |
| `Staging` | Canonical staging target tables where needed. |
| `ReferenceMaster_Enh` | Reference/master-data conformance. |
| `SalesHistory_Enh` | Sales/invoice/open demand Silver outputs. |
| `ForecastHistory_Enh` | Forecast Silver outputs. |
| `OpenOrderHistory_Enh` | Open-order Silver outputs. |
| `InventoryHistory_Enh` | Inventory Health Silver outputs and helpers. |
| `ProcessingSeed` | Controlled seed/reference inputs now owned by Processing. |
| `Meta` | Legacy VN control plane, fallback, lineage/DQ evidence, and Phase 2 extension candidate. |

### Gold / Serving

Gold lives in `SupplyChain_Gold_Warehouse`.

Current serving schemas:

| Schema | Role |
|---|---|
| `ForecastAccuracy_DW` | Forecast Accuracy mart facts/dimensions. |
| `InventoryHealth_DW` | Inventory Health mart facts/dimensions/helpers. |
| `Shared_DW` | Shared dimensions such as calendar, product, warehouse. |

Gold principle:

```text
Shared dimensions first
  -> mart dimensions
  -> mart facts
  -> semantic smoke
```

### Semantic / Analytics

The direction is a shared semantic model instead of one semantic model per mart.

Current reality from the latest live audit:

- `sc_control_tower` is the current v10 semantic focus.
- Some legacy report binding drift still exists and is documented in the live audit.
- Phase 1 did not mutate 04_semantic/report objects.
- A broader 04_semantic/report smoke gate is a Phase 2/backlog item.

## Mart Map

| Mart | Project tag | Current folder |
|---|---|---|
| Forecast Accuracy | `forecast_accuracy` | `02_marts/forecast_accuracy/` |
| Inventory Health | `inventory_health` | `02_marts/inventory_health/` |

`Shared_DW` is not a consumer mart. It is the dependency layer embedded inside each mart Gold wrapper as Wave 00:

- `Shared_DW.DimCalendar`
- `Shared_DW.DimProduct`
- `Shared_DW.DimWarehouse`

## Execution Order

The old VN control plane had rich dependency metadata. Phase 1 preserved the dependency order as wrapper procedure order while shifting primary runtime to Enterprise ETL.

High-level order:

```text
1. Forecast Accuracy Silver wrapper
2. Forecast Accuracy Gold wrapper
3. Inventory Health Silver wrapper
4. Inventory Health Gold wrapper
5. DQ / freshness / duplicate checks
6. 04_semantic/report smoke
```

Silver wrappers include `ReferenceMaster_Enh` Wave 00. Gold wrappers include `Shared_DW` Wave 00.

Manual/ad-hoc orchestration lives under:

```text
03_operations/orchestration/main/
03_operations/orchestration/forecast_accuracy/
03_operations/orchestration/inventory_health/
```

The rule is simple: never run alphabetical order. Use the manifest.

## Operational Safety

### What is safe by default

- Reading docs and manifests.
- Running dry-run scripts.
- Exporting metadata.
- Running read-only SQL audits.
- Running 04_semantic/DAX smoke queries.

### What requires explicit approval

- Live Fabric pipeline trigger.
- Live SQL execution that mutates data or metadata.
- Full refresh packs.
- Dropping orphan `_LOAD` tables.
- Dropping deprecated `_Wrk` views/schemas.
- Updating 04_semantic/report definitions.

## Phase 1 Completion Evidence

Use these files when someone asks whether Phase 1 really closed:

- `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
- `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1_done_handoff_20260623.md`
- `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1h_final_cleanup_audit_20260623.txt`

Final Phase 1 facts:

- `cleanup_objects_remaining count=0`
- canonical object refs are clean
- `Staging_Wrk_Wrk` deprecated path removed
- `DemandForecastSnapshotDaily` latest snapshot grain duplicate groups = `0`
- 2026-06-24 full wrapper run succeeded across all four wrapper procedures
- 2026-06-24 final audit passed: `49/49` live/local modules matched, `92/92` compile checks passed, `56` start/complete audit pairs, `0` queryinsights non-success entries
- 04_semantic/report layer was smoke-checked read-only; report/model definitions were not mutated in the final runtime validation
