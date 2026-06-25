# Storage Inventory — `EnterpriseData-Dev`

> Synthesized from `_external_refs/enterprisedata-dev-01_docs/docs/02-storage/`. 11 warehouses + 5 lakehouses + 1 SQL DB.

## Warehouses comparison

| Warehouse | Tier | Schemas | Tables | Views | Procs | ID |
|---|---|---:|---:|---:|---:|---|
| `ETL_Framework` | PROD-CTRL | 13 | 31 | 14 | **35** | `02c8970b-7af3-4d4e-b011-cc3cdc3825ef` |
| `Source_Data` | PROD-SRC | **64** | **636** | 12 | 2 | `f14e2ea6-ae2c-4b90-8e08-522e84f1aefc` |
| `Centralized_Warehouse` | PROD-GOLD | 23 | 38 | 12 | 0 | `c5a1f95b-f9db-4cb7-8ded-396ea70da572` |
| `Retail_Warehouse` | PROD | 25 | **198** | 41 | **146** | `09504907-575d-446a-991a-87fa525166d7` |
| `Wholesale_Warehouse` | PROD | 28 | **209** | **126** | 8 | `c1ef4a62-f8e2-4d55-96bd-33eb07b81b7c` |
| `MasterData_Warehouse` | PROD | 14 | 46 | 12 | 0 | `db565620-28ac-4510-a61e-1023743efdc6` |
| `Distribution_Warehouse` | PROD | 8 | 7 | 12 | 0 | (small/incomplete) |
| `Quality_Warehouse` | PROD-EMPTY | 6 | **0** | 12 | 0 | (empty shell) |
| `StagingWarehouseForDataflows_*` | AUTO | 6 | 0 | 12 | 0 | dataflow gen2 staging |
| `DataflowsStagingWarehouse` | AUTO | 6 | 0 | 12 | 0 | dataflow gen2 staging |
| `Test_Owneraccess` | TEST | 6 | 0 | 12 | 0 | leftover from access testing |

**Totals**: 199 schemas · 1,165 tables · 277 views · 191 procs.

## Per-WH key schemas + naming patterns

### `ETL_Framework` (control plane)
Schemas: `DW_Developer` (the brain), `Performance_Logs`, `Manufacturing_Maximo`, `MasterData_ItemMaster_AFI`, `Retail_DW`, `Wholesale_ProductSourcing_AFI`, `Wholesale_Quality_AFI_wrk`.

Key tables:
- `DW_Developer.TableDictionary` (65 cols) — master registry
- `DW_Developer.AuditLog` (4 cols: Description, DateTime, [User], Command)
- `DW_Developer.TableDictionary_UpdateLog` + `_RadarSync` (event logs)
- `DW_Developer.FabricLoad`, `EnvironmentControl` (load metadata)
- `Performance_Logs.tblFabricSLAAlertLog` + `_Detail` (SLA tracking)
- `Performance_Logs.EmailQueue`, `DimEmailQueue` (alert delivery)
- `DW_Developer.Source_EDW_AggCheck`, `Source_EDW_CountCheck` (daily reconciliation)

### `Source_Data` (Bronze landing)
**64 schemas** — 1 per source feed. Pattern observed:
- Wholesale: `Wholesale_CODIS_AFI`, `Wholesale_Customers`, `Wholesale_DemandPlanning_AFI`, `Wholesale_Invoicing_AFI`, `Wholesale_SalesHistory_AFI`, `Wholesale_ProductSourcing_AFI`, etc. (each + `_Wrk` working set)
- Retail: `Retail_Corporate`, `Retail_Corporate_SCD`, `Retail_Dart`, `Retail_Ecommerce`, `Retail_Marketing`, `Retail_Shoppertrack`, etc.
- MasterData: `MasterData_GeographicData`, `MasterData_HR_UKG`, `MasterData_HR_UKG_AGR`, `MasterData_HR_UKG_DSG`, `MasterData_ItemMaster_AFI`, `MasterData_OneSource`, `MasterData_PIM`, `MasterData_ProductKnowledge`, `MasterData_Retail`, `MasterData_Security`, `Masterdata_Finance`
- **SupplyChain**: `SupplyChain_DW`, `SupplyChain_Enh` (Bronze landing)
- Manufacturing: `Manufacturing_Inventory`, `Manufacturing_Inventory_AFI`, `Manufacturing_Masterdata`, `Manufacturing_ProductionPlanning_AFI`
- Other: `AFISales`, `Merch_ExternalFiles`, `ResidentHome`

Naming convention in Source_Data: `<Domain>_<SubDomain>[_AFI][_Wrk][_SCD]` — domain prefix + optional source tag + optional working/SCD suffix.

### `Wholesale_Warehouse` (Silver — wholesale value stream)
Schemas (canonical + `_Wrk` working pairs):
- `SalesHistory_AFI` + `_Wrk` + `_Archive` — invoice detail/header (shared 4 streams per Enterprise ETL)
- `CustomerOrders_AFI` + `_Wrk` — open orders, order types, audit
- `Customers` + `_Wrk` — account master, shipping locations
- `Marketing` + `_Wrk` (35 _Wrk views — heaviest)
- `Pricing_AFI` + `_Wrk` (20 _Wrk views)
- `ProductSourcing_AFI` + `_Wrk`
- `Purchasing_AFI` + `_Wrk`
- `Quality_AFI` + `_Wrk`
- `PartyContacts` + `_Wrk`
- `Placements` + `_Wrk`
- `AFISales_Wrk` (no canonical pair)

Pattern: each domain has canonical schema + `_Wrk` schema with `v_<Table>` views (curated logic). 8 procs total — main one is `Usp_Refresh_Wholesale_Warehouse` (chains hundreds of `usp_Refresh*` calls).

### `Retail_Warehouse` (Silver — retail value stream)
Schemas:
- `Retail_Sales`, `Retail_Sales_Enh`, `Retail_Sales_Wrk` (3-tier: canonical + enhanced + working)
- `Retail_OOM_Enh`, `Retail_OOM_Wrk` (Order Operations Management)
- `Retail_Traffic`, `Retail_Traffic_Wrk`
- `MasterData_Ent`, `MasterData_Ent_Wrk` — enterprise-shared subset
- `MasterData_HR_UKG_Enh`, `MasterData_HR_UKG_Enh_Wrk` — HR enhanced (used by Retail)
- `MasterData_HR_UKG_DSG_Enh`, `MasterData_HR_UKG_DSG_Enh_Wrk` — HR design tier
- `MasterData_Product`, `MasterData_Product_Enh`, `MasterData_Product_Wrk`
- `MasterData_Retail_Ent`, `MasterData_Retail_Ent_Wrk`

**146 procs** — heaviest proc set. Pattern: 49 Refresh-Load + 38 MERGE + 19 Validate + 13 Audit-DQ.

### `MasterData_Warehouse` (Silver — master data shared)
Schemas:
- `MasterData_DW`, `MasterData_DW_Wrk` — **only `_DW`-suffix schemas observed** (Dim* prefix on tables)
  - Tables: `DimDate`, `DimDate_NonRetail`, `DimDateTool`, `DimItemMaster`, `DimRetailLocations`, `DimTime`
- `ProductKnowledge`, `ProductKnowledge_Wrk`
  - Tables: `Item`, `ItemClass`, `ItemMaster`, `ItemDimensions`, `LifeStyleArea`, `ParentStyleLookup`, etc. (no `Dim` prefix)
- `GeographicData`, `GeographicData_Wrk`
- `Retail`, `Security`

**0 procs internal** — loaded by ETL_Framework procs (cross-WH).

### `Centralized_Warehouse` (Gold — aggregation)
Schemas:
- `MetaData` (control tables: ShortcutCatalog, SysObjectInfo, CopyTables)
- `<WH>_INFORMATION_SCHEMA` mirrors per WH
- `<WH>_sys` mirrors per WH
- `dbo` (38 tables consolidated views)

**0 procs** — loaded externally by `MetaData-Pull` notebook (cross-WH JDBC sync).

### `Distribution_Warehouse`
Only 7 tables — likely incomplete or future domain.

### `Quality_Warehouse`
**EMPTY** — PROD tier but 0 tables, 0 procs. Decision pending: build or remove.

## Lakehouses (5)

| Lakehouse | Tier | Tables | Description |
|---|---|---:|---|
| `Centralized_Lakehouse` | PROD | 501 (5.92B rows) | **18 OneLake shortcuts** to PROD WS Source_Data + Retail_Warehouse |
| `A_Developement` | DEV-SANDBOX | 3 local + 7 ADLS shortcuts | Dev sandbox |
| `RadarSync_Test` | TEST | 2 local + entire ADLS trusted+raw mount | **Risk** — broad scope |
| `DataflowsStagingLakehouse` | AUTO | 0 | Dataflow gen2 staging |
| `StagingLakehouseForDataflows_*` | AUTO | 0 | Dataflow gen2 staging |

## SQL Database (1)
- `Commissions_Prototype` — used by `test` + `pipeline1` cross-WS Copy. Misnamed.

## Key observations for VN team

1. **Each domain WH owned by its value-stream team** (Wholesale, Retail, etc.). VN team should own `SupplyChain_Warehouse` (proposed, doesn't exist yet).
2. **Naming convention** is consistent: `<Domain>` (canonical) + `<Domain>_Wrk` (working) + optional `_AFI` (source tag) / `_Enh` (enhanced) / `_DW` (dim/fact) / `_Archive`.
3. **Dim/Fact prefix** ONLY in `_DW` schemas (only `MasterData_DW` observed). Other schemas use plain table names.
4. **126 `_Wrk` views in Wholesale** — each `_Wrk` schema contains `v_<Table>` views with curated logic. This is the pattern Enterprise ETL expects VN to use.
5. **Quality_Warehouse empty** — risk that's been there for months. Quality DQ infrastructure not built; VN's DQ approach (54 rules in `Meta.DQRule`) could potentially be reused here.

## Cross-refs

- Per-WH detail (raw scan): `_external_refs/enterprisedata-dev-01_docs/docs/02-storage/warehouses/`
- ETL framework deep dive: [`../projects/etl_framework/SYNTHESIS.md`](../projects/etl_framework/SYNTHESIS.md)
- Naming proposal: [`../20_proposals/03_naming_conventions.md`](../20_proposals/03_naming_conventions.md)
