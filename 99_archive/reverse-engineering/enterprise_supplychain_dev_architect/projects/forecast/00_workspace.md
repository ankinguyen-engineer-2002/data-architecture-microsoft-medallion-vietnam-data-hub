# 00 — Workspace, Warehouses, Auth

> Scanned: 2026-05-06 via Fabric REST API + pyodbc · Updated 2026-05-10 post Bob alignment (ADR-008).

## Fabric Workspace

| Item | Value |
|------|-------|
| Display name | `SupplyChain Dev` |
| Workspace ID | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Capacity | DATAWAREHOUSE PROD |
| Environment | DEV |
| Total items | 135 (live count: 19 pipelines, 18 dataflows, 3 lakehouses, 81 notebooks, 1 report, 3 SQL endpoints, 4 semantic models, 6 warehouses) |

## Warehouses (in workspace)

| Warehouse | ID | Role for `forecast` mart |
|-----------|----|--------------------------|
| `SupplyChain_Processing_Warehouse` | `c0262cef-b8a7-495f-bccc-53b098c7948c` | **Active** — Silver + control plane |
| `SupplyChain_Gold_Warehouse` | `98e2a911-5af9-442e-9cc8-5d8dadb8b762` | **Active** — Gold serving (Direct Lake) |
| `SupplyChain_Warehouse` | `e146ffe2-d907-46a7-9b7e-3e739a31b24e` | Legacy v9 (objects deleted; Cherry's `dbo.*` still has data) |
| `ETL_Framework` | — | Enterprise utility |
| `Temp_SCPWarehouse` | — | Temp |
| `StagingWarehouseForDataflows_20251008171231` | — | Auto-provisioned by dataflow gen2 |

## Lakehouses (in workspace)

| Lakehouse | Role |
|-----------|------|
| `Enterprise_Lakehouse` | OneLake shortcuts → enterprise source data (read-only) |
| `SupplyChain_Lakehouse` | EDW supplement (4 dataflow feeds → `_edw` tables) |
| `StagingLakehouseForDataflows_20251008171206` | Auto-provisioned by dataflow gen2 |

## Common SQL Endpoint

```
7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com
```

Same endpoint hosts both `SupplyChain_Processing_Warehouse` and `SupplyChain_Gold_Warehouse` databases.

## Auth — Token Acquisition

```bash
# Warehouse SQL (pyodbc / sqlcmd / SSMS)
az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv

# Fabric REST API (pipelines, items, workspace metadata)
az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

# Power BI REST API (semantic model, datasets)
az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv

# OneLake storage (Delta read direct)
az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv
```

## pyodbc Connection (Processing WH)

```python
import pyodbc, struct, subprocess

token = subprocess.check_output([
    "az", "account", "get-access-token",
    "--resource", "https://database.windows.net/",
    "--query", "accessToken", "-o", "tsv"
]).decode().strip()
tb = token.encode("UTF-16-LE")
ts = struct.pack(f"<I{len(tb)}s", len(tb), tb)

conn = pyodbc.connect(
    "Driver={ODBC Driver 18 for SQL Server};"
    "Server=7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com;"
    "Database=SupplyChain_Processing_Warehouse;"
    "Encrypt=yes;TrustServerCertificate=no;",
    attrs_before={1256: ts}
)
```

For Gold WH, change `Database=SupplyChain_Gold_Warehouse`.

## Cross-DB Naming

Gold WH views read Processing WH via 3-part name:

```sql
SELECT * FROM SupplyChain_Processing_Warehouse.<Schema>.<Table>
```

Both warehouses live on the same SQL endpoint — no linked server needed.

## Active az login

```
DATAWAREHOUSE PROD subscription, Enabled state.
Tenant: <auto-detected via az login>
```

## IT Blockers (impact on `forecast`)

| Blocker | Impact | Workaround |
|---------|--------|-----------|
| `Mail.Send` permission denied | No email alert on pipeline fail | Manual `Meta.RunLog` polling |
| Teams webhook denied | No Teams notification | Manual check |
| Data Activator not provisioned | No real-time alerting | — |
| Azure DevOps access denied | No CI/CD | Manual deploy via Fabric REST API |
| Schedule trigger requires IT approval | Pipeline runs manually only | Manual `pl_sc_master` invoke |
| Service Principal grants on Meta tables | Auto-refresh of Gold→SemanticModel lineage skipped | Manual `05_tools/build_semantic_model_lineage.py` |
