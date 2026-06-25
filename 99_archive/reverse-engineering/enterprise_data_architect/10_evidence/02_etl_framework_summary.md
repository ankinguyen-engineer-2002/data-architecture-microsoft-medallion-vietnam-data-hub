# ETL Framework Summary — `EnterpriseData-Dev.ETL_Framework`

> High-level summary. **Full deep-dive synthesis (1,210 lines)**: [`../projects/etl_framework/SYNTHESIS.md`](../projects/etl_framework/SYNTHESIS.md)

## What it is

`ETL_Framework` warehouse (`02c8970b-7af3-4d4e-b011-cc3cdc3825ef`) is the **metadata-driven orchestration brain** of the entire `EnterpriseData-Dev` workspace. Every Bronze→Silver→Gold transformation across 5 domain warehouses runs through procs here.

## 4 key tables

```
DW_Developer.TableDictionary          ← 65-col master registry
DW_Developer.TableDictionary_UpdateLog ← append-only event log
DW_Developer.AuditLog                  ← 4-col audit trail (Description, DateTime, [User], Command)
DW_Developer.FabricLoad                ← Fabric-specific load metadata
```

## 35 stored procedures, 10 families

| Family | Count | Examples | Purpose |
|--------|------:|----------|---------|
| Parquet loaders | 12 | `Usp_CreateTableFromParquet`, `Usp_CreateTableFromParquet_V2`, `Usp_TableFromParquet_CopyInto_TruncateLoad` | Bronze landing from ADLS Parquet |
| Curated refresh | 6 | `usp_RefreshCuratedTableFromView`, `usp_UpdateCuratedTableFromView_DateRange`, `usp_UpdateTableDictionary_ModifiedDate`, `usp_UpdateTableDictionaryModified` | Bronze→Silver transformations |
| Alert/SLA | 5 | `usp_DataWarehouseDataFeedAlert_Fabric`, `usp_DataWarehouseSLAAlert_Fabric`, `usp_GenerateEmailHTML_DimAggregateDiffer` | Notifications |
| Audit/DQ | 3 | `usp_Audit_ADW_Tables`, `usp_Audit_Fabric_Tables`, `usp_Audit_ADW_Tables_V1` | Reconciliation |
| Incremental | 3 | `usp_IncrementalTableLoad`, `usp_IncrementalTableLoad_CDC`, `usp_IncrementalTableLoad_Backup` | CDC + delta loads |
| Drop/Cleanup | 2 | `usp_DropConstraints`, `usp_DropWorkTable` | Working table cleanup |
| SCD2/Snapshot | 2 | `usp_SCD2_TableLoad`, `Usp_SnapshotLoad` | Type 2 SCD + snapshots |
| Other | 2 | `usp_GrantSchemaSecurity`, `Usp_WriteTableToParquet` | Utilities |

**12 parquet-loader variants** is technical debt — created via experimentation. VN team should pick ONE and standardize.

## TableDictionary 65-col schema (grouped by purpose)

| Group | Cols | Examples |
|-------|------|----------|
| Identity | 6 | `ServerName`, `DatabaseName`, `SchemaName`, `TableName`, `ObjectType`, `StorageType` |
| Update method | 4 | `UpdateMethod`, `UpdateQuery`, `ExtractQuery`, `RefreshDescription` |
| Primary keys | 3 | `PrimaryKey`, `AlternateKey`, `DistributionKey` |
| Date handling | 3 | `DateKey`, `DateRangeDays`, `LastBatchStartDate` |
| Source ref | 5 | `SourceSystem`, `SourceServer`, `SourceDatabase`, `SourceObject`, `ReplicatedSource` |
| Scheduling/SLA | 5 | `RefreshRate` (hours), `JobServer`, `JobName`, `Modified`, `LastAudit` |
| Metadata discovery | 6 | `ColumnCount`, `ColumnStatsCount`, `ColumnStatsLastUpdated`, `CreateDate`, `Created`, `CreatedBy` |
| Audit/error | 4 | `ErrorMsg`, `InvalidCount`, `RowCount`, `DeletedRows` |
| Storage location | 5 | `DataLake`, `DataLakeFolder`, `DataLakeFolderArchive`, `StageDataLakeFolder`, `LibraryList` |
| Source mapping | 4 | `ETLTool`, `PackageName`, `TFSPath`, `SourcePlatform` |
| Replication policy | 2 | `ReplicatedSourceExpiryHours`, `ReplicatedSourceArchiveExpiryHours` |
| Index/structure | 3 | `IndexType`, `RowSToreClusteredKey`, `AdditionalIndexes` |
| Databricks | 3 | `DataBricksClusterVersion`, `DataBricksNodeType`, `DataBricksClusterRange` |
| Misc | 7 | `OperationKey`, `PII`, `ValidKeyValues`, `SelectColumn`, `PartitionKey`, `SourceObjectAlias`, `ModifiedBy`, etc. |

## Lifecycle pattern

```
Loader proc starts
  └→ INSERT AuditLog ('Process Start', user, datetime via fn_GetDate UTC→CST)
  └→ business logic (CTAS/MERGE/INSERT)
  └→ EXEC usp_UpdateTableDictionary_ModifiedDate(@db, @schema, @table)
       ├─ if row not in TableDictionary → INSERT base row
       └─ INSERT TableDictionary_UpdateLog (DatabaseName, SchemaName, TableName, LastUpdated, UpdateQuery)
  └→ INSERT AuditLog ('Process End', user, datetime)

End of batch (deferred):
  EXEC usp_UpdateTableDictionaryModified  ← UPDATE TableDictionary.Modified = MAX(LastUpdated) FROM UpdateLog
```

## Domain team workflow (how Wholesale adds a Silver table)

1. Domain engineer creates `Wholesale_Warehouse.<Domain>_Wrk.v_<Table>` view (curated logic)
2. INSERT row in `ETL_Framework.DW_Developer.TableDictionary` with metadata (ServerName, DatabaseName='Wholesale_Warehouse', SchemaName='<Domain>', TableName='<Table>', UpdateMethod='Insert', RefreshRate=24, etc.)
3. Pipeline activity calls `EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView 'Wholesale_Warehouse', '<Domain>', '<Table>'`
4. Proc looks up TableDictionary row, generates dynamic SQL, executes load, logs audit, updates Modified

→ Domain team doesn't touch ETL_Framework procs. They only register tables + write `_Wrk` views.

## VN team's parallel pattern (current)

VN team built equivalent control plane in `Enterprise SupplyChain-Dev` workspace:

| Bob's pattern | VN's parallel |
|---------------|---------------|
| `ETL_Framework.DW_Developer.TableDictionary` | `Meta.TableDictionary` (cloned 65-col schema 2026-05-10 per ADR-008) |
| `ETL_Framework.DW_Developer.TableDictionary_UpdateLog` | `Meta.TableDictionary_UpdateLog` |
| `ETL_Framework.DW_Developer.AuditLog` | `Meta.AuditLog` |
| `ETL_Framework.DW_Developer.fn_GetDate` | `Meta.ufn_utc_to_cst` |
| `usp_UpdateTableDictionary_ModifiedDate` | `Meta.usp_UpdateTableDictionary_ModifiedDate` (ported) |
| `usp_UpdateTableDictionaryModified` | `Meta.usp_UpdateTableDictionaryModified` (ported) |
| 35 procs (`Usp_CreateTableFromParquet`×12 + `usp_RefreshCuratedTableFromView`×6 + ...) | **1 generic** `Meta.usp_GenericLoad` (registry-driven, supports 8 load patterns) |
| Per-table `EXEC` from pipeline | ForEach asset_id from `Meta.AssetRegistry`, parallel batch=8 |

**Key VN advantage**: registry-driven 1-generic-proc collapses Bob's 35 procs into 1 dispatcher. Less code to maintain.

**Key Bob advantage**: per-domain refresh wrappers (`Usp_Refresh_Wholesale_Warehouse` chains 100+ EXEC calls) provide tight coupling for domain SLA tracking.

## VN team alignment options

See full proposals: [`../20_proposals/01_etl_framework_alignment.md`](../20_proposals/01_etl_framework_alignment.md)

Top 5 actionable insights from synthesis:
1. **Metadata registry is non-negotiable** — VN already has TableDictionary clone (per ADR-008). Cross-DB sync to Bob's hub via `usp_LogRun v2` once permission unblocked.
2. **Domain WH isolation is by design** — VN's `SupplyChain_Warehouse` (pending) should have its own refresh wrapper proc, not share Retail/Wholesale's.
3. **Standardize ONE parquet loader** — Bob has 12 variants (tech debt). VN should pick `Usp_CreateTableFromParquet_V2` style for new VN tables in hub.
4. **Audit trail is linear, not hierarchical** — Bob's AuditLog doesn't track call stack. VN's AuditLog already extended with `AssetID`/`RunID`/`Severity` (10 cols vs Bob's 4) — superior, no regression.
5. **TableDictionary needs governance early** — no INSERT validation, no retention policy. VN should add validation rules before scaling.

## Cross-refs

- [Full deep-dive synthesis](../projects/etl_framework/SYNTHESIS.md) — 1,210 lines, ~46KB
- [ETL framework alignment proposal](../20_proposals/01_etl_framework_alignment.md)
- VN side ADR-008: [`../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md`](../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md)
- VN side execution: [`../../Enterprise_SupplyChain_Dev_architect/artifacts/bob_alignment_2026-05-10/`](../../Enterprise_SupplyChain_Dev_architect/artifacts/bob_alignment_2026-05-10/)
