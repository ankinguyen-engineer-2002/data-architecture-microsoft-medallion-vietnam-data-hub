# Mart B Inventory Health - Source Status Brief

> Date: 2026-06-03
> Scope: Mart B / Inventory Health / Inventory Control Tower
> Audience: leadership update, DE US follow-up, AI agent planning
> Note: This file focuses on Bronze/source readiness. Silver, Gold, and Semantic are already built as a working validation version.

## 1. Executive Summary

Mart B is the Inventory Health data mart used for the Inventory Control Tower.

The VN team has already built the technical flow end to end:

```text
Bronze source
  -> Silver clean/business logic
  -> Gold curated dataset
  -> Direct Lake semantic model
  -> Power BI Inventory Control Tower
```

The technical foundation is working, but the Bronze source layer is still mixed.
Some source tables have already been loaded or fixed by DE US. These items should not be called "pending" anymore. They are now in "VN validation pending" status.

Other source tables still have no latest update from DE US, so they remain pending.

## 2. Current Source Landscape

Inventory Health currently tracks 27 active source paths.

| Source type | Count | Share | Current meaning |
|---|---:|---:|---|
| Enterprise Lakehouse primary paths | 25 | ~93% | Main official source path |
| Temporary workaround paths | 2 | ~7% | Still using SupplyChain Lakehouse / Dataflow until Enterprise Lakehouse source is promoted |
| Total tracked source paths | 27 | 100% | Current Mart B source list |

High-level flow:

```text
US EnterpriseData Workspace
  -> Enterprise_Lakehouse via OneLake shortcuts
    -> SupplyChain_Processing_Warehouse
      -> InventoryHistory_Enh / ReferenceMaster_Enh
        -> SupplyChain_Gold_Warehouse
          -> InventoryHealth_DW + Shared_DW
            -> sc_inventory_health_control_tower semantic model
              -> Power BI Inventory Control Tower
```

## 3. Full Source Path Inventory For AI Team

The 27 source paths below are the current Mart B source tracking view for the AI team.

Important reading rule:

```text
Not every source below is equally ready.
Some are clean primary Enterprise Lakehouse sources.
Some have been loaded by DE US and now need VN validation.
Some are stale or Phase 2 sources and should not be treated as final.
Two paths are temporary workarounds outside Enterprise Lakehouse.
```

### 3.1 Enterprise Lakehouse / Shortcut Tracked Paths

These are the 25 Enterprise-side or shortcut-backed source paths currently tracked for Mart B source readiness.

| # | Source path | Main purpose in Mart B | Current note for AI team |
|---:|---|---|---|
| 1 | `Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL` | Current on-hand inventory by item/warehouse | Pending DE US freshness confirmation |
| 2 | `Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA` | Standard cost / cost current logic | Pending DE US freshness confirmation |
| 3 | `Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT` | Item extension; unavailable flag logic | Pending DE US freshness confirmation; deprecated hold/ATP columns are expected zero |
| 4 | `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` | Base product/item master for shared `DimProduct` | Pending DE US freshness confirmation |
| 5 | `Enterprise_Lakehouse.MasterData_DW.DimDate` | Calendar/date reference | Pending DE US freshness confirmation |
| 6 | `Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster` | Warehouse extension / warehouse flags | Loaded by DE US; VN validation pending |
| 7 | `Enterprise_Lakehouse.Wholesale_DemandPlanning_AFI.SupplyPlanDetail` | Forward supply plan / risk fact | Enterprise source path |
| 8 | `Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail` via `SalesHistory_Enh.v_InvoiceDetailLineLevel` | Sales shipment history, movement, COGS fallback | Reused from Mart A Silver; Mart B no longer materializes `SalesShipment` |
| 9 | `Enterprise_Lakehouse.Manufacturing_ProductionPlanning_AFI.MOMAST` | Manufacturing orders | Loaded by DE US; VN validation pending |
| 10 | `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.IMHIST` | Inventory movement history / validation tracking | Pending DE US future-date and completeness validation |
| 11 | `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRDTL` | Holding transfer detail | Loaded by DE US; VN validation pending |
| 12 | `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRHDR` | Holding transfer header | Loaded by DE US; VN validation pending |
| 13 | `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderDetail` | Allocated demand | Enterprise source path; H1 business sign-off still tracked |
| 14 | `Enterprise_Lakehouse.CustomerOrders_AFI.OpenOrderHeader` | Allocated demand header/context | Enterprise source path |
| 15 | `Enterprise_Lakehouse.Wholesale_Purchasing_AFI.ATPSUM` | ATP week-ending source / historical logic reference | Loaded by DE US; VN validation pending; active ATP forward-looking output was removed from Gold/Semantic |
| 16 | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail` | Purchase order detail | Loaded by DE US; VN validation pending for header/warehouse mismatch issue |
| 17 | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoMaster` | Purchase order header/vendor context | Loaded by DE US; VN validation pending |
| 18 | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.Container` | Container / Phase 2 purchasing context | Phase 2 tracked source |
| 19 | `Enterprise_Lakehouse.Purchasing_AFI.VendorMaster` | Vendor reference and product primary vendor enrichment | Enterprise source path |
| 20 | `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotDaily` | Active inventory weekly snapshot path via Saturday daily rows | Active DA-first path |
| 21 | `Staging.DemandForecastSnapshotDaily` | Active forecast weekly snapshot path via Saturday daily rows | Active DA-first path; canonical BOB target fed by staging wrapper view |
| 22 | `Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster` | Warehouse master reference | Enterprise source path |
| 23 | `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | Logility item status / supply-demand status | Loaded by DE US; upstream grain conflict still pending confirmation |
| 24 | `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotWeekly` | Legacy weekly forecast snapshot | Stale; bypassed by active daily Saturday-derived path |
| 25 | `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotWeekly` | Legacy weekly inventory snapshot | Stale; bypassed by active daily Saturday-derived path |

### 3.2 Temporary Workaround Paths

These 2 paths are still outside the official Enterprise Lakehouse target path.

| # | Missing official source | Current workaround source | Main purpose | Current note for AI team |
|---:|---|---|---|---|
| 26 | `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance` | `SupplyChain_Lakehouse.dbo.itembalance` via `df_brz_ItemBalance` | Historical item balance support | Temporary workaround; waiting for DE US Enterprise Lakehouse promotion |
| 27 | `Enterprise_Lakehouse.SupplyChain_Enh.PurchaseOrderSnapshot` | `SupplyChain_Lakehouse.dbo.purchaseordersnapshot` via `df_brz_PurchaseOrderSnapshot` | Phase 2 PO-as-of support | Temporary workaround; very large source, about 2B rows; waiting for DE US Enterprise Lakehouse promotion |

## 4. Correct Status Categories

The most important point is to separate "fixed by DE US" from "still pending DE US".

| Status | Meaning | Owner of next action |
|---|---|---|
| Fixed / loaded by DE US | DE US already loaded or fixed the table. No new update is expected from them right now. | VN team validates freshness, row coverage, and data quality |
| Pending DE US | DE US has not replied, has not refreshed, or has not confirmed the source yet. | DE US |
| VN ETL workaround | VN team has implemented a temporary ETL path to unblock Mart B. | VN maintains workaround until official source is available |
| Business validation pending | Technical data exists, but KPI/business meaning still needs confirmation. | DA / BU / Robert or relevant business owner |
| AI readiness pending | AI agent access and governance are not confirmed yet. | AI team + VN data team |

## 5. Fixed / Loaded By DE US - VN Validation Pending

These items are no longer pure DE US pending items. DE US has already reported "Data Loaded".
The remaining work is VN-side validation.

| Table / object | Previous finding | DE US response | Current status | VN validation needed |
|---|---|---|---|---|
| `Enterprise_Lakehouse.Manufacturing_ProductionPlanning_AFI.MOMAST` | Latest known date was `2025-12-02`; 169-day gap | Data Loaded | Fixed by DE US | Validate new max date after reload |
| `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRDTL` | Latest known date was `2025-12-10`; 161-day gap | Data Loaded | Fixed by DE US | Validate new max date after reload |
| `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRHDR` | Latest known date was `2025-12-10`; 161-day gap | Data Loaded | Fixed by DE US | Validate new max date after reload |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster` | Latest known date was `2026-02-11`; 98-day gap | Data Loaded | Fixed by DE US | Validate new max date after reload |
| `Enterprise_Lakehouse.Wholesale_Purchasing_AFI.ATPSUM` | Latest known date was `2026-02-11`; 98-day gap | Data Loaded | Fixed by DE US | Validate new max date and APWK01 logic |
| `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.PoDetail` vs `PoMaster` | 481 missing headers; 20 warehouse mismatches | Data Loaded | Fixed / latest from DE US | Confirm whether original integrity issue is fixed, not only reloaded |

Recommended wording:

```text
These tables have been loaded by DE US and are now the latest available source state.
They are not pending from DE US anymore.
The next step is VN validation: check max date, row coverage, and whether the original data issue is resolved.
```

## 6. Still Pending DE US

These items still have no latest fix or confirmation from DE US in the current update.

| Table / object | Current issue | DE US response | Current status | Needed from DE US |
|---|---|---|---|---|
| `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotWeekly` | `MAX(dfcSnapshot) = 2024-03-25`; 786-day gap | Not mentioned | Pending DE US | Refresh weekly forecast snapshot |
| `Enterprise_Lakehouse.MasterData_DW.DimDate` | Latest known date `2025-10-28`; 204-day gap | Not mentioned | Pending DE US | Refresh or confirm currency |
| `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` | Latest known date `2025-10-28`; 204-day gap | Not mentioned | Pending DE US | Refresh or confirm currency |
| `Enterprise_Lakehouse.SupplyChain_Enh_1.DemandInventorySnapshotWeekly` | `MAX(dinSnapshot) = 2026-03-02`; 79-day gap | Not mentioned | Pending DE US | Refresh weekly inventory snapshot |
| `Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT` | Latest known date `2026-03-10`; 71-day gap | Not mentioned | Pending DE US | Refresh or confirm currency |
| `Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA` | Latest known date `2026-03-15`; 66-day gap | Not mentioned | Pending DE US | Refresh or confirm currency |
| `Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL` | Latest known date `2026-03-23`; 58-day gap | Not mentioned | Pending DE US | Refresh or confirm currency |
| `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.IMHIST` | Future-date issue on `TRNDT MAX` | Not mentioned | Pending DE US | Verify future date and load completeness |
| `Enterprise_Lakehouse.Manufacturing_Inventory_AFI.TFRDTL` vs `TFRHDR` | 188 orphan detail rows; 35 transfer numbers | Not mentioned | Pending DE US | Confirm expected logic or header completeness |
| `Enterprise_Lakehouse.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | 9,128 duplicate/grain-conflict groups | Not mentioned | Pending DE US | Confirm upstream issue or accepted dedupe rule |
| `Enterprise_Lakehouse.Wholesale_Purchasing_AFI.ATPSUM.APWK01` | Detail incomplete / cut off | Not mentioned | Pending clarification | Provide or confirm APWK01 issue detail |

## 7. Temporary Workaround Sources Still In Use

These sources are still not available as official Enterprise Lakehouse paths, so VN is using temporary paths.

| Missing official Enterprise source | Current workaround | Approx rows | Status |
|---|---|---:|---|
| `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance` | `SupplyChain_Lakehouse.dbo.itembalance` via `df_brz_ItemBalance` | ~48.97M | Waiting for DE US Enterprise Lakehouse promotion |
| `Enterprise_Lakehouse.SupplyChain_Enh.PurchaseOrderSnapshot` | `SupplyChain_Lakehouse.dbo.purchaseordersnapshot` via `df_brz_PurchaseOrderSnapshot` | ~2B | Waiting for DE US Enterprise Lakehouse promotion |

## 8. What VN Team Already Fixed In ETL

While waiting for upstream data to become fully official and validated, VN has already implemented ETL-side fixes to unblock Mart B.

| Area | VN ETL action |
|---|---|
| Stale weekly forecast source | Bypassed stale weekly table; built `ForecastSnapshotWeekly` from daily Saturday snapshots |
| Stale weekly inventory source | Bypassed stale weekly table; built `InventorySnapshotWeekly` from daily Saturday snapshots |
| Purchase orders | Switched active logic to Enterprise `PoDetail` + `PoMaster` |
| Logility | Switched active logic to Enterprise Logility table |
| Logility grain conflict | Added deterministic dedupe rule in Silver view |
| Sales shipment | Removed duplicate Mart B materialization; reused Mart A invoice Silver view |
| Shared dimensions | Consolidated into `Shared_DW.DimCalendar`, `Shared_DW.DimProduct`, and `Shared_DW.DimWarehouse` |
| Gold facts | Built `FactInventoryHealthSnapshot`, `FactInventoryRiskForward`, and `CogsRollingHelper` |
| Semantic model | Bound semantic model to Gold/shared dimensions and smoke tested |

## 9. Current Mart B Technical State

| Layer | Current state |
|---|---|
| Bronze | Mixed readiness: some fixed by DE US, some still pending, two workaround paths still active |
| Silver | Built and aligned with DA feedback |
| Gold | Built with `InventoryHealth_DW` facts and shared `Shared_DW` dimensions |
| Semantic model | Working validation version: `sc_inventory_health_control_tower` |
| Power BI | Ready for validation against business logic |
| Schedule / automation | Manual/on-demand evidence is available; schedule state should be verified before claiming fully stable automation |

## 10. AI Agent Readiness Notes

If the China AI team plans to build an AI agent that reads the Gold layer, these questions should be answered before opening production-style access.

| Topic | Required question |
|---|---|
| Access path | Will the AI agent read Gold tables directly, or read through the semantic model? |
| KPI contract | Will the AI use official semantic measures / DAX definitions? |
| Security | Which identity will the agent use: user identity, service account, or service principal? |
| Permission | Will it respect row-level security and column-level security if needed? |
| Read-only control | Can we guarantee the agent only runs read-only queries? |
| Query audit | Will we get SQL/DAX/query logs for review? |
| Source status awareness | Can the AI show a warning when source data is still under validation? |
| Answer traceability | Can the AI show which table, column, or measure was used? |
| Ownership | If the AI gives a wrong KPI answer, who will debug and fix it? |

## 11. Final Message

Mart B Inventory Health is technically ready for validation.

Silver, Gold, shared dimensions, and the semantic model are already built and working as a validation version.

The remaining work is not a single generic "pending" bucket. The correct status is:

```text
Some source items have already been fixed or loaded by DE US.
Those items now need VN validation.

Some source items still have no DE US update.
Those items remain pending DE US.

Two source paths are still temporary workarounds.
Those need official Enterprise Lakehouse promotion later.
```

Before using this dataset for production AI agent access, the team should confirm:

1. Bronze source completeness and freshness.
2. VN validation results for tables already loaded by DE US.
3. Business/KPI sign-off.
4. AI agent access pattern, security model, query logging, and KPI contract.

## 12. Reference Files

- `10_bronze.md`
- `20_silver.md`
- `30_gold.md`
- `50_semantic.md`
- Latest DE US progress update pasted by Aric on 2026-06-03
