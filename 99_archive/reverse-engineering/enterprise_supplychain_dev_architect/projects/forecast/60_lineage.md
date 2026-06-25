# 60 — Lineage

> Scanned: 2026-05-06 · Updated 2026-06-01 after shared dimension consolidation.
> **Source:** `Meta.LineageEdge` (auto-built by `Meta.usp_BuildLineage` from registry `source_objects` JSON).
> **Edge count:** see `Meta.LineageEdge` and [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). The important current semantic contract is that `DimCalendar`, `DimProduct`, and `DimWarehouse` flow from `Shared_DW`, not from duplicated mart-specific physical dims.

## 2026-06-01 Shared Dimension Lineage Override

These edges are the current source-of-truth for forecast shared dims:

| Target | ← Source(s) |
|--------|-------------|
| `Shared_DW.DimCalendar` | `ReferenceMaster_Enh.Calendar` |
| `Shared_DW.DimProduct` | `Enterprise_Lakehouse.MasterData_DW.DimItemMaster`, `Enterprise_Lakehouse.Purchasing_AFI.VendorMaster`, `Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT` |
| `Shared_DW.DimWarehouse` | `ReferenceMaster_Enh.Warehouse`, `Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster` |
| `SemanticModel.sc_forecast_control_tower.DimCalendar` | `Shared_DW.DimCalendar` |
| `SemanticModel.sc_forecast_control_tower.DimProduct` | `Shared_DW.DimProduct` |
| `SemanticModel.sc_forecast_control_tower.DimWarehouse` | `Shared_DW.DimWarehouse` |

Stale/inactive physical tables such as `ForecastAccuracy_DW.DimProduct` can still exist in the warehouse for rollback/history, but they are not the intended semantic source after the shared-dim cutover.

## Edge Type Summary

| Edge type | Count | Meaning |
|-----------|------:|---------|
| `direct` | 53 | Source → target via Silver/Gold view (CTAS / SP load) |
| `semantic` | 7 | Gold table → Direct Lake semantic model |

## Full DAG (read top → down: source flows down)

### Layer 0: External Bronze Sources (Lakehouse)

```
Enterprise_Lakehouse.Wholesale_Codis_AFI.{codatan, COMAST, EXTORD, EXTORIT, AAORDTYP}
Enterprise_Lakehouse.MasterData_DW.{DimDate, DimItemMaster}
Enterprise_Lakehouse.Customers.{AccountMaster, ShippingLocations}
Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
SupplyChain_Lakehouse.dbo.{brz_saleshistory_afi__invoicedetail_ver2,
                          brz_saleshistory_afi__invoiceheader_ver2,
                          brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2,
                          ref_product_ver2}
ProcessingSeed.{ForecastCycle, ForecastHorizon}
```

### Layer 1: Staging_Wrk ← External Bronze (4 edges)

| Target | ← Source(s) |
|--------|-------------|
| `Staging_Wrk.InvoiceDetailEdw` | `SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2` |
| `Staging_Wrk.InvoiceHeaderEdw` | `SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2` |
| `Staging.DemandForecastSnapshotDaily` | `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily` |
| `Staging_Wrk.ProductEdw` | `SupplyChain_Lakehouse.dbo.ref_product_ver2` |

### Layer 2: ReferenceMaster_Enh ← External Bronze (10 edges)

| Target | ← Source(s) |
|--------|-------------|
| `ReferenceMaster_Enh.Calendar` | `Enterprise_Lakehouse.MasterData_DW.DimDate` |
| `ReferenceMaster_Enh.CustomerAccount` | `Enterprise_Lakehouse.Customers.AccountMaster` |
| `ReferenceMaster_Enh.CustomerAccountGroup` | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping` |
| `ReferenceMaster_Enh.CustomerGrouping` | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping` |
| `ReferenceMaster_Enh.CustomerShippingLocation` | `Enterprise_Lakehouse.Customers.ShippingLocations` |
| `ReferenceMaster_Enh.ForecastCycle` | `ProcessingSeed.ForecastCycle` |
| `ReferenceMaster_Enh.ForecastHorizon` | `ProcessingSeed.ForecastHorizon` |
| `ReferenceMaster_Enh.ItemMaster` | `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` |
| `ReferenceMaster_Enh.OrderType` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP` |
| `ReferenceMaster_Enh.Warehouse` | `Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster` |

### Layer 3: Silver Wave 0 (3 targets, depends on Staging + ReferenceMaster + Lakehouse direct)

| Target | ← Source(s) |
|--------|-------------|
| `SalesHistory_Enh.InvoiceDetailLineLevel` | `Staging_Wrk.InvoiceDetailEdw`, `Staging_Wrk.InvoiceHeaderEdw`, `ReferenceMaster_Enh.CustomerAccountGroup` |
| `ForecastHistory_Enh.ForecastDemandMonthly` | `Staging.DemandForecastSnapshotDaily`, `ReferenceMaster_Enh.ForecastCycle`, `ReferenceMaster_Enh.Calendar` |
| `OpenOrderHistory_Enh.OpenOrderLineLevel` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.{codatan, COMAST, EXTORD, EXTORIT}`, `ReferenceMaster_Enh.{ItemMaster, OrderType}` |

### Layer 4: Silver Wave 1 (4 targets, depends on Wave 0 + ReferenceMaster)

| Target | ← Source(s) |
|--------|-------------|
| `SalesHistory_Enh.ActualDemandMonthly` | `SalesHistory_Enh.InvoiceDetailLineLevel`, `OpenOrderHistory_Enh.OpenOrderLineLevel`, `ReferenceMaster_Enh.{Calendar, CustomerAccountGroup}` |
| `SalesHistory_Enh.ActualDemandWeekly` | (same sources, week grain) |
| `SalesHistory_Enh.InvoiceWeekly` | `SalesHistory_Enh.InvoiceDetailLineLevel`, `ReferenceMaster_Enh.Calendar` |
| `OpenOrderHistory_Enh.OpenOrderMonthly` | `OpenOrderHistory_Enh.OpenOrderLineLevel`, `ReferenceMaster_Enh.{Calendar, CustomerAccountGroup}` |

### Layer 5: Silver Wave 2 (1 target, depends on Wave 1)

| Target | ← Source(s) |
|--------|-------------|
| `ForecastHistory_Enh.NaiveForecastMonthly` | `SalesHistory_Enh.ActualDemandMonthly`, `ReferenceMaster_Enh.Calendar` |

### Layer 6: Gold ← Silver (7 targets)

| Target | ← Source(s) |
|--------|-------------|
| `Shared_DW.DimCalendar` | `ReferenceMaster_Enh.Calendar` |
| `ForecastAccuracy_DW.DimCustomerGrouping` | `ReferenceMaster_Enh.CustomerGrouping` |
| `ForecastAccuracy_DW.DimForecastHorizon` | `ReferenceMaster_Enh.ForecastHorizon` |
| `Shared_DW.DimProduct` | `Enterprise_Lakehouse.MasterData_DW.DimItemMaster`, `Enterprise_Lakehouse.Purchasing_AFI.VendorMaster`, `Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT` |
| `Shared_DW.DimWarehouse` | `ReferenceMaster_Enh.Warehouse`, `Enterprise_Lakehouse.Wholesale_Codis_AFI.AshleyWarehouseMaster` |
| `ForecastAccuracy_DW.FactForecastActual` | `SalesHistory_Enh.ActualDemandMonthly`, `ForecastHistory_Enh.{ForecastDemandMonthly, NaiveForecastMonthly}` |
| `ForecastAccuracy_DW.FactForecastKpi` | `SalesHistory_Enh.ActualDemandMonthly`, `ForecastHistory_Enh.{ForecastDemandMonthly, NaiveForecastMonthly}`, `ReferenceMaster_Enh.ForecastHorizon` |

### Layer 7: Semantic Model ← Gold (7 edges, type=`semantic`)

| Target | ← Source(s) |
|--------|-------------|
| `SemanticModel.sc_forecast_control_tower` | All 7 Gold tables (Direct Lake mode) |

---

## How edges are built

`Meta.usp_BuildLineage` parses `Meta.AssetRegistry.source_objects` (JSON array per asset) and generates `direct` edges. The `semantic` edges come from a separate workflow that scans semantic model TMDL definitions (see [`30_runbook/18_lineage_extension_to_semantic_models.md`](../../30_runbook/18_lineage_extension_to_semantic_models.md) — template doc).

**Rebuild manually:**
```sql
EXEC Meta.usp_BuildLineage;
```

Auto-rebuilt at end of every pipeline run by `Meta.usp_FinalizePipeline`.

## Streamlit Lineage Explorer

Live URL: https://supplychain-lineage-vn.streamlit.app/

Reads CSVs from `lineage_explorer/data/` (refreshed every 10 min by GitHub Action `.github/workflows/refresh_lineage_data.yml`).

Lineage nodes color-coded by `medallion_group`: BRZ / REF / SLV / DW / SEM.
