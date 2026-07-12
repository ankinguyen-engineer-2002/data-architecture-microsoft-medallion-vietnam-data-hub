# ETL Framework Live Sync And Pattern Audit

Date: `2026-07-02`  
Scope: `EnterpriseData-Dev.ETL_Framework` -> `Enterprise SupplyChain-Dev.ETL_Framework`

## Summary

This note records the live framework sync and runtime-pattern audit completed on `2026-07-02`.

Primary outcome:

- `Enterprise SupplyChain-Dev.ETL_Framework` is now aligned to the usable runtime surface from `EnterpriseData-Dev.ETL_Framework`
- one broken source procedure was intentionally excluded
- one snapshot procedure was patched minimally so it is usable in SupplyChain
- Forecast Accuracy DQ remains on a direct-insert pattern, not the generic loader

## Live Scope

Source workspace:

- `EnterpriseData-Dev`
- warehouse: `ETL_Framework`

Target workspace:

- `Enterprise SupplyChain-Dev`
- warehouse: `ETL_Framework`

## Sync Result

Additive sync applied to target live warehouse:

- `6` missing schemas created
- `23` missing tables created empty
- missing functions/procedures/views created
- changed framework objects updated from live source definitions

Target parity rule after sync:

- keep current target data in existing framework tables
- create missing framework tables empty
- sync runtime objects, not historical source data

## Intentional Exceptions

### 1. `DW_Developer.Usp_TableFromParquet_RowADF`

This procedure was intentionally removed from `Enterprise SupplyChain-Dev`.

Reason:

- source live definition is internally broken
- it references `DW_Developer.FabricLoad` columns such as `RowId`, `Status`, `ErrorMessage`
- live `DW_Developer.FabricLoad` in both source and target only contains:
  - `FabricDatabaseName`
  - `FabricSchemaName`
  - `TableName`
  - `Path`
  - `ColumnList`
  - `LoadDate`
- the procedure also hardcodes a OneLake path and uses a framework table as scratch staging
- no other framework object references it

Decision:

- remove from SupplyChain target
- do not preserve as active runtime surface

### 2. `DW_Developer.Usp_SnapshotLoad`

This procedure was patched minimally in `Enterprise SupplyChain-Dev`.

What changed:

- still uses the original `stage -> target` algorithm
- now accepts both:
  - full `abfss://...` path
  - relative path
- no longer appends `/` to a `.parquet` file path
- now writes:
  - `DW_Developer.AuditLog`
  - `DW_Developer.TableDictionary`
  - `DW_Developer.TableDictionary_UpdateLog`

What did not change:

- procedure signature
- staging-table pattern
- truncate/reload target behavior

Intent:

- keep the procedure close to source behavior
- only patch the parts that made it unusable in SupplyChain

## Pattern Audit

### Snapshot

Status:

- engine patched and usable
- no further code change required for now

Key finding:

- source version was not generic because it hardcoded a OneLake prefix while live `Snapshot` metadata often stores full `abfss://...` paths

### Append

Status:

- framework code in SupplyChain is usable after sync
- no further procedure change required

Key findings:

- `usp_IncrementalTableLoad` append branch in target now uses `SELECT DISTINCT`
- one SupplyChain metadata row still exists with incomplete business configuration:
  - `SupplyChain_Warehouse.SCP_Core.FactFcstErrorCalc`
  - `ReplicatedSource = NULL`
  - `SelectColumn = NULL`
- this is a business metadata problem, not a framework-engine problem

### Upsert / Insert

Status:

- no active `Insert` or `Upsert` rows currently exist in SupplyChain target
- no code change required now

Key findings:

- source workspace contains several active `Upsert` rows
- source also contains at least one broken metadata row with `ReplicatedSource = NULL`
- this confirms metadata quality must be validated separately from loader code

### DateKey / DateRange

Status:

- active in SupplyChain target
- no code change applied

Active rows observed in target:

- `InventoryHistory_Enh.HoldingTransferSnapshotDaily` -> `DateKey`
- `InventoryHistory_Enh.ManufacturingOrderSnapshotDaily` -> `DateKey`
- `Staging.DemandForecastSnapshotDaily` -> `DateRange`

Key finding:

- metadata required by these patterns is present in target live rows

### CDC

Status:

- no active CDC rows currently exist in SupplyChain target
- no code change applied

Key findings:

- source workspace has active CDC rows
- some source rows have metadata risks, especially around `SourcePlatform`
- CDC should not be enabled in SupplyChain until a dedicated live use case exists

## Forecast Accuracy DQ Decision

Forecast Accuracy DQ was tested against the generic ETL framework and was intentionally kept on a direct-insert pattern.

Reason:

- the DQ requirement is append-by-run history
- each run should write a fresh time-stamped batch
- generic `Insert` / `Upsert` logic is key-based and not a clean match for DQ run-history semantics
- previous generic-loader attempts returned `Process Complete` while writing `0` rows

Current operating pattern:

- keep the DQ view
- execute a direct `INSERT INTO ... SELECT ... FROM view` at the end of the mart gold procedure
- keep `LoadDT` in the target DQ history table

## Operational Reading

As of `2026-07-02`, the correct interpretation for SupplyChain is:

- framework runtime surface is synchronized enough to use as the current baseline
- generic framework is appropriate for standard curated-table patterns
- custom DQ history append should remain a mart-specific direct insert until a dedicated framework pattern exists

## Follow-up Guidance

Recommended next enhancement, if needed later:

- add a dedicated enterprise-style history loader such as `usp_AppendHistoryFromView`
- keep the normal framework logging and metadata updates
- do not force DQ history append into the current generic `usp_IncrementalTableLoad`
