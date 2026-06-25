# 10 — Bronze Layer (Logical Access)

> Scanned: 2026-05-06 · Updated 2026-06-01 after `df_ref_forecast_cycle` ProcessingSeed migration.
> **Bronze is logical, not physical** — no dedicated warehouse. Source data accessed via OneLake shortcuts + Lakehouse dataflows.

## Source Lakehouses

### `Enterprise_Lakehouse` — Source-aligned shortcuts (READ-ONLY)

OneLake shortcuts pointing to the central `Enterprise_Data` workspace. Silver views in Processing WH read **directly** from here via 3-part naming.

Schemas accessed by `forecast`:

| Schema | Tables consumed | Role |
|--------|----------------|------|
| `Wholesale_Codis_AFI` | `codatan`, `COMAST`, `EXTORD`, `EXTORIT` | CODIS open-order source |
| `MasterData_DW` | `DimDate`, `DimItemMaster` | Calendar + Item master |
| `Customers` | `AccountMaster`, `ShippingLocations` | Customer dimensions |
| `CustomerOrders_AFI` | `WarehouseMaster` | Warehouse dimensions |
| `Wholesale_ProductSourcing_AFI` | `CustomerGrouping` | Customer group mapping |

### `SupplyChain_Lakehouse` — EDW Supplement (4 dataflow feeds)

When `Enterprise_Lakehouse` is incomplete or unstable, dataflows write `_edw` tables here. Then `Staging_Wrk` views/tables CTAS from these tables.

| Dataflow | Target table | Reason |
|----------|-------------|--------|
| `df_brz_SalesHistory_AFI_InvoiceDetail` | `brz_saleshistory_afi__invoicedetail_edw` | Supplement Enterprise SalesHistory feed |
| `df_brz_SalesHistory_AFI_InvoiceHeader` | `brz_saleshistory_afi__invoiceheader_edw` | Supplement Enterprise SalesHistory feed |
| `df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1` | `brz_supplychain_enh_1__demandforecastsnapshotdaily_edw` | **Legacy** forecast snapshot supplement (older `SupplyChain_Enh_1` namespace). Current v10 reads forecast snapshots from `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily` via canonical Enterprise ETL target `Staging.DemandForecastSnapshotDaily`. |
| `df_ref_product` | `ref_product_edw` | Product master supplement |

> Note: `df_ref_forecast_cycle` lands SharePoint cycle reference data into `ProcessingSeed.ForecastCycle` in the Processing Warehouse. `ReferenceMaster_Enh.ForecastCycle` materializes from that Processing-owned seed table, so forecast Silver no longer reads `SupplyChain_Lakehouse.dbo.ref_forecast_cycle` directly.

## Bronze Access Pattern

```
                        SILVER VIEWS read FROM:
                                    │
                    ┌───────────────┴────────────────┐
                    ▼                                ▼
       Enterprise_Lakehouse                   SupplyChain_Lakehouse
       (cross-DB shortcuts)                   (4 EDW dataflow feeds)
                    │                                │
       direct read via 3-part            CTAS into Staging_Wrk.<Table>Edw
       naming: EL.<Schema>.<Table>       SP: Staging_Wrk.usp_RefreshEdwTables
                    │                                │
                    └────────► SILVER VIEWS ◄────────┘
```

## Why Two Lakehouses?

`Enterprise_Lakehouse` is the **default** source — direct shortcut read is preferred (no local copy, always fresh).

`SupplyChain_Lakehouse` exists because 4 sources (InvoiceDetail, InvoiceHeader, DemandForecast, Product) had unstable SLAs or schema gaps in Enterprise — they're staged via dataflow as a buffer. **Exit candidates** when Enterprise feeds stabilize (see ADR-002).

## Bronze Tables Used by Silver Views (cross-reference)

To find which Silver view uses which Bronze source, see lineage edges in [60_lineage.md](60_lineage.md). Edge type for direct Lakehouse reads is `direct` and for staged reads is `staged`.

## EDW Supplement Refresh

All 4 staged tables refreshed by single SP:

```sql
EXEC Staging_Wrk.usp_RefreshEdwTables;
```

Triggered by pipeline `pl_sc_staging` once per run. The SP performs `DROP TABLE IF EXISTS` + `CREATE TABLE AS SELECT` from Lakehouse `_edw` tables.

Full DDL of the SP: see [`etl/meta_sps.sql`](etl/meta_sps.sql) (look for `Staging_Wrk.usp_RefreshEdwTables`).
