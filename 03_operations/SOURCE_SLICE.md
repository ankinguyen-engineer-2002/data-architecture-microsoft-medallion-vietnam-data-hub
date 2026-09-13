# Source slice — two marts, not the estate

## Why a slice

Enterprise hub scan (archive, not this runtime): `Source_Data` **64 schemas /
636 tables**. Wholesale and Retail value-stream warehouses are hundreds of
objects each. Putting that in a portfolio git is neither sanitizable nor
honest: you did not operate every domain table from this repo.

The operating evidence **in this git** is two products:

| Mart | Business question | Gold |
|---|---|---|
| Forecast Accuracy | Forecast vs actual at planning grain | `ForecastAccuracy_DW` |
| Inventory Health | Weekly on-hand / risk at item-warehouse | `InventoryHealth_DW` |

Interview line: these are the two SCM products we keep current; upstream
jobs below exist because **these Gold tables read those Bronze names**.

## How the list was built

1. List files in `02_marts/*/01_bronze/01_enterprise_lakehouse/`.
2. Keep only `Enterprise_Lakehouse.<schema>.<table>` references.
3. Union Forecast + Inventory (shared masters appear once).
4. Attach load method from runtime contracts, not from imagination:
   - `DemandForecastSnapshotDaily` → DateRange **30 days**
     (`final_enterprise_etl_runtime_architecture.md`)
   - invoices + forecast snapshot → bounded DQ windows, live counts
     (ADR-011: snapshot ~11.0B, InvoiceDetail ~296.7M, InvoiceHeader ~63.2M)
   - `usp_IncrementalTableLoad` CDC = DB2 journals, strip `JO*`
   - inventory `run_order.json`: MO and holding transfer **incremental**;
     weekly snapshots **overwrite**

No Retail POS, no UKG, no Maximo **unless** a mart SQL file points at them.
ADF still has those feeds [Verified as mounted factory]; they are out of
slice for Spark jobs in this folder.

## Counts

| | n |
|---|---:|
| Forecast-only Bronze files | 21 |
| Inventory-only extras | 12 |
| Union (slice) | 33 |
| Spark jobs grouping the slice | 7 |

Registry: [databricks/registry/sources.yaml](databricks/registry/sources.yaml).

Spark load methods (must match notebooks; validator enforces):

| Kind | Landing | Write | Example |
|---|---|---|---|
| Current-state | `raw/.../current` | overwrite | dims, CODIS, ItemBalance, PO |
| Date-bounded fact | `raw/.../dt=` | `replaceWhere` | forecast `dfcSnapshot` 30d, invoices 3 completed months, inventory `dtea` |
| CDC journal | `dt=yesterday` | MERGE JOENTT UP/PX/PT | TFRHDR / TFRDTL |
