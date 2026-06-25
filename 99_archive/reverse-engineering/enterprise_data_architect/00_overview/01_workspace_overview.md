# Workspace Overview — `EnterpriseData-Dev`

> Source: scan of `EnterpriseData-Dev` workspace 2026-05-08 via Fabric REST API + pyodbc, generated docs 2026-05-10.

## Identity

| Field | Value |
|---|---|
| Display name | `EnterpriseData-Dev` |
| Workspace ID | `5360a935-1984-4775-895f-f4c90bafa19d` |
| Tenant | Ashley Furniture (`@ashleyfurniture.com`) |
| Capacity | `30d06c17-...` East US Dedicated Large dataset |
| Workspace SPN | `14bfa211-3cab-...` |
| Git integration | `ConnectedAndInitialized` to Azure DevOps |
| ADO Org/Project/Repo | `ashleyfurniture` / `Enterprise Data Services` / `Fabric-EnterpriseData` |
| ADO Branch | `main` |
| Sync state | `ConnectedAndInitialized` |

## At-a-glance

| Item type | Count |
|---|---:|
| Warehouses | 11 |
| Lakehouses | 5 |
| SQL Database | 1 |
| Pipelines | 22 |
| Notebooks | 18 |
| Stored procedures (across all WHs) | 192 |
| Views (across all WHs) | 145 |
| Shortcuts | 412 |
| GUIDs cross-referenced | 412 |
| Risks identified | 28 (1 critical, 4 high, rest low/medium) |
| Total items scanned | 71 |

## Role in Ashley Furniture's data platform

`EnterpriseData-Dev` is the **DEV mirror of the enterprise data platform**, primarily a **definition store** (code + config). Real ETL execution lives in:

- **PROD workspace** `EnterpriseData` (`ce4e6503-...`) — Centralized_Lakehouse here has 5.92B rows; DEV uses OneLake shortcuts back to PROD for testing
- **Databricks Unity Catalog** `edw_dev` — live mirrored to Fabric
- **Legacy ADF** `ashleyv2datafactory` — mounted, still active for SaaS feeds (UKG, AFI, Maximo, ServiceNow, GA)

DEV workspace orchestrates by **definition** — most pipelines are scheduled but only 3 of 41 orchestration items have recent run history. The **`Source_EDW_Check_Test`** pipeline runs daily 03:50 UTC (count + aggregate reconciliation EDW vs Fabric).

## Active migration context

Ashley is **mid-migration EDW (legacy SQL Server) → Fabric**. Visible signs:

- `Fabric Migration ADF` pipeline ports table definitions from Synapse `Ashley_Edw.dw_developer.tabledictionary` into Fabric
- `EDW2FabricLoader` reads metadata `ASHLEY_EDW_DEV.dw_developer.FabricMapping` (Flag=1) → row-by-row Copy
- Mirror Databricks `edw_dev` autoSync (last sync 2026-05-08)
- `ETL_Framework` warehouse: 35 procs + 65-col TableDictionary = orchestration brain

## VN team's relationship to this workspace

- **VN team workspace** `Enterprise SupplyChain-Dev` (`c8d9fc83-...`) is a **value-stream workspace** (not a hub). Owns Gold + Silver SC-specific + semantic model + reports.
- VN's `Enterprise_Lakehouse` is a **shortcut aggregator** with 5 schemas pointing to Bob's hub: `MasterData_DW`, `Customers`, `Wholesale_Codis_AFI`, `Wholesale_ProductSourcing_AFI`, `SupplyChain_DW` (via `Source_Data` Bronze).
- **Pending**: Bob to create `SupplyChain_Warehouse` in this hub for SC-team-owned shared Silver (forecast, naive baseline, etc.)
- **Permissions today**: VN team has read access via shortcuts; no write access to any WH in this hub

## Cross-refs

- [Architecture at a glance](02_architecture_at_a_glance.md)
- [Storage inventory](../10_evidence/01_storage_inventory.md)
- [ETL framework summary](../10_evidence/02_etl_framework_summary.md)
- Raw scan: `_external_refs/enterprisedata-dev-01_docs/docs/01-introduction.md`
