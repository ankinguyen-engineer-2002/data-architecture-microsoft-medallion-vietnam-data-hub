# 00 — Workspace, Warehouses, Auth

> **Status (updated 2026-06-01):** LIVE. Same workspace + warehouses as `forecast/` project. No new infrastructure required; latest full master rerun is green, while schedule auto-run enablement and residual cleanup decisions remain open.

## Fabric Workspace

| Item | Value |
|------|-------|
| Display name | `SupplyChain Dev` |
| Workspace ID | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Capacity | DATAWAREHOUSE PROD |
| Environment | DEV |
| Owner | VN SC DA team (Aric + Cherry) |

## Warehouses

| Warehouse | ID | Purpose | Inventory Health usage |
|---|---|---|---|
| `SupplyChain_Processing_Warehouse` | `c0262cef-b8a7-495f-bccc-53b098c7948c` | Silver + Meta control plane | Hosts `InventoryHistory_Enh`, `ReferenceMaster_Enh`, and `Meta.*` control-plane tables |
| `SupplyChain_Gold_Warehouse` | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` | Gold Direct Lake serving | Hosts `InventoryHealth_DW` facts/helper/vendor plus shared `Shared_DW` dims |

SQL Endpoint (both WHs): `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com`

## Lakehouses

| Lakehouse | ID | Purpose | Inventory Health usage |
|---|---|---|---|
| `Enterprise_Lakehouse` | (Enterprise ETL hub) | OneLake shortcuts to Enterprise Bronze | Primary source for most active Inventory Health bronze paths |
| `SupplyChain_Lakehouse` | `62a3081e-4093-4f46-856c-f50aa58732fa` | EDW supplement staging | Current workaround path for `dbo.itembalance`; `dbo.purchaseordersnapshot` remains inactive Phase 2 |

## Authentication

Per memory `reference_fabric_connections`:
- Connection mode: `az login` interactive (no Service Principal required)
- For programmatic use: `az account get-access-token --resource https://api.fabric.microsoft.com`
- pyodbc via SQL Endpoint using `ODBC Driver 18 for SQL Server` (installed locally)
- MCP server `fabric-dynamic` reuses the same `az` token

## Permissions required

| Action | Permission | Status |
|---|---|---|
| READ Processing + Gold WH | Member of `SupplyChain Dev` workspace | ✅ Aric has |
| WRITE views + INSERT registry rows | Contributor of `SupplyChain Dev` workspace | ✅ Aric has |
| Trigger pipelines manually | Contributor + Item Permissions on `pl_sc_master` | ✅ Aric has |
| Schedule trigger auto-enable | Contributor/write on item; IT may need to own enablement depending workspace policy | ⏳ `pl_sc_master` schedules exist but are disabled |
| Alerting (Mail.Send/Teams) | IT-level permission | ⏳ BLOCKED |

## Network / Capacity

Same Fabric capacity as forecast (DATAWAREHOUSE PROD). Inventory Health has already materialized large Silver/Gold tables; latest verified full `pl_sc_master` success is 2026-05-29. Before enabling recurrence, re-check Fabric item schedule state and confirm ownership/alerting expectations.

## Live Control-Plane Snapshot (2026-06-01)

| Check | Result |
|---|---|
| Fabric workspace items | 146 total items; 17 DataPipelines, 7 SemanticModels, 6 Warehouses, 3 Lakehouses |
| Main semantic model | `sc_inventory_health_control_tower` (`88c3fccd-698d-4175-b7b9-ea377e0f5afc`) |
| Current `pl_sc_master` item ID | `f36f56b8-5668-4a0c-b991-2c28302f1710` |
| Latest verified `pl_sc_master` run in `Meta.PipelineRunLog` | Success on 2026-05-29 16:15:29→17:27:22 UTC, `12 succeeded, 0 failed` |
| Schedule state | [Need-verify] latest audit proves manual job success; do not claim cron auto-run active until Fabric schedule state is rechecked |
