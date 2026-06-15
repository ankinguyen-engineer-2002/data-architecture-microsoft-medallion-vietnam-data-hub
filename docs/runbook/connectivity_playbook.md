# Connectivity Playbook (API-first, no wandering)

Goal: keep all “connect / verify / operate” work fast and repeatable using **Azure token → REST/SQL** paths (Fabric REST, Power BI REST, Azure REST, Power Automate REST) plus a small set of Python libs.  
Language note: docs/code in English; short Vietnamese hints included where helpful.

## 0) Golden rules (VN team working style)

1. **Auth once**: use `az login` (interactive) as the default.
2. **Prefer control-plane APIs** over clicking around UI:
   - Fabric REST → pipelines/items/schedules/jobs, getDefinition/updateDefinition (TMDL, dataflows, reports)
   - Power BI REST → refreshes, `executeQueries`, dataset/report operations
   - Azure ARM REST → infra/identity/resource queries (when needed)
   - Power Automate REST → alerting/workflows (when enabled by IT)
3. **Prefer `az rest`** for one-off checks (it handles tokens cleanly).
4. **Prefer Python** for repeatable checks/exports (commit scripts into repo).
5. **SQL endpoint**: in headless/agent environments, `sqlcmd -G` often fails; use **`pyodbc` + Entra access token** (see §2).

## 1) Canonical IDs / endpoints (DEV)

Source of truth:
- `AGENTS.md` (root) — tenant/workspace/sql endpoint + token commands
- `Enterprise_SupplyChain_Dev_architect/projects/inventory_health/00_workspace.md` — Processing/Gold WH IDs + semantic model IDs

Key values (DEV):
- Tenant: `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d`
- Workspace: `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`
- SQL endpoint (Fabric Warehouses): `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com`
- Processing WH DB (Silver + Meta): `SupplyChain_Processing_Warehouse`
- Gold WH DB (DirectLake serving): `SupplyChain_Gold_Warehouse`

## 1.1 Token “resources” (Entra audiences)

Use these consistently (do not invent new ones unless verified):

```bash
# SQL / Warehouse (ODBC / pyodbc)
az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv

# Fabric REST API (control plane)
az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

# Power BI REST API
az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv

# OneLake / ADLS Gen2
az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv

# Azure ARM (when needed)
az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv

# Microsoft Graph (Mail/Teams/Users… when needed)
az account get-access-token --resource https://graph.microsoft.com/ --query accessToken -o tsv
```

## 1.2 Agent / CI note (avoid az writing to HOME)

Some agent/sandbox setups block writes to `~/.azure`. For repeatable automation, pin Azure CLI state into the repo:

```bash
export AZURE_CONFIG_DIR="$PWD/.azure"
az login --tenant 5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d
```

## 2) Warehouse SQL endpoint (pyodbc + Entra token) — canonical pattern

Canonical implementation exists in:
- `lineage_explorer/export_lineage_data.py` (`get_token()` + `connect()`)

Minimal pattern (Python):

```python
import struct
import subprocess
import pyodbc

server = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
database = "SupplyChain_Processing_Warehouse"

token = subprocess.check_output(
    ["az","account","get-access-token","--resource","https://database.windows.net/","--query","accessToken","-o","tsv"],
    text=True,
).strip()

# IMPORTANT (this repo’s proven working format):
# ODBC attr 1256 expects: 4-byte little-endian length prefix + UTF-16LE token bytes
token_bytes = token.encode("utf-16-le")
token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

cn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER=tcp:{server},1433;DATABASE={database};"
    "Encrypt=yes;TrustServerCertificate=no;",
    attrs_before={1256: token_struct},
    autocommit=True,
)
```

Fast verification tables/views (typical):
- `Meta.AssetRegistry` (is_active, last_load_date, legacy_view_name, cron_expression, …)
- `Meta.RunLog` (status, rows_loaded, error_message, timestamps)
- `Meta.PipelineRunLog` (pipeline executions)

## 3) Fabric REST API (items, pipelines, schedules, jobs, getDefinition/updateDefinition)

### 3.1 Base URL

```text
https://api.fabric.microsoft.com/v1
```

Workspace base:

```text
https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}
```

### 3.2 “Quick check” via `az rest` (recommended for one-off)

Examples (see also `Enterprise_SupplyChain_Dev_architect/30_runbook/19_legacy_v8_daily_refresh_recovery.md`):

```bash
# List pipeline schedules
az rest --method GET \
  --resource https://api.fabric.microsoft.com \
  --url "https://api.fabric.microsoft.com/v1/workspaces/<wsId>/items/<pipelineItemId>/jobs/Pipeline/schedules"

# List pipeline job instances
az rest --method GET \
  --resource https://api.fabric.microsoft.com \
  --url "https://api.fabric.microsoft.com/v1/workspaces/<wsId>/items/<pipelineItemId>/jobs/instances"
```

### 3.3 getDefinition / updateDefinition (TMDL, pipelines, dataflows)

Proven patterns in repo:
- Pipelines export: `Enterprise_SupplyChain_Dev_architect/tools/export_v10_readiness_baseline.py` uses `POST .../items/{id}/getDefinition`
- Semantic model definition (TMDL): `lineage_explorer/export_lineage_data.py` uses `POST .../semanticModels/{id}/getDefinition?format=TMDL` and handles 200 vs 202 (LRO)
- Dataflows automation: `Enterprise_SupplyChain_Dev_architect/projects/inventory_health/dataflows/drafts/API_AUTOMATION_RESULTS.md`

Notes:
- Some Fabric APIs return **202 Accepted** with `Location`/`x-ms-operation-id`. Poll until you can GET the `/result`.
- When deploying TMDL via `updateDefinition`, keep **relationships** in a dedicated `definition/relationships.tmdl` part (to avoid “tables without relationships” in live).
- Reference payload example: `Enterprise_SupplyChain_Dev_architect/projects/inventory_health/artifacts/backups/semantic_relationship_fix_20260528/update_definition_body.json`

## 4) Power BI REST API (refresh, executeQueries, datasets)

Base:

```text
https://api.powerbi.com/v1.0/myorg
```

Common checks:

```bash
# Dataset refresh history
az rest --method GET \
  --resource https://analysis.windows.net/powerbi/api \
  --url "https://api.powerbi.com/v1.0/myorg/groups/<wsId>/datasets/<datasetId>/refreshes?\$top=10"
```

Semantic smoke tests (DAX) use `executeQueries` (see `Enterprise_SupplyChain_Dev_architect/projects/*/50_semantic.md`).

## 5) Azure REST API (ARM) — when needed

Use ARM only when you truly need infra/identity data.

Base:

```text
https://management.azure.com
```

Token resource:

```bash
az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
```

## 6) Power Automate REST API (alerting/workflows)

Operational intent: map “SQL Agent alerts” → Fabric pipeline failures → **Power Automate / Teams / Mail / Graph / Data Activator** (blocked until IT/admin consent in this tenant).

This repo currently documents the operational requirement and blockers, but does not hardcode a single REST base URL because it depends on the allowed approach (Power Platform env / Graph / connectors). When IT unblocks, record the chosen base URL + resource here.

## 7) MCP connectors (Fabric / Power BI / Modeling / Microsoft docs)

Use MCP connectors when available because they:
- reuse the same `az` token (less auth plumbing)
- provide typed operations (less endpoint guesswork)

Evidence in repo:
- `Enterprise_SupplyChain_Dev_architect/projects/inventory_health/00_workspace.md` notes MCP server `fabric-dynamic` reuses `az` token.
- `Enterprise_SupplyChain_Dev_architect/projects/inventory_health/dataflows/drafts/API_AUTOMATION_RESULTS.md` documents:
  - MCP for Microsoft Learn lookup (`microsoft-docs-search`, `microsoft_docs_fetch`)
  - DataFactory MCP (`Microsoft.DataFactory.MCP`) to manage Dataflow Gen2 end-to-end

Rule of thumb:
1) Try MCP tool → 2) fall back to `az rest` → 3) fall back to Python `requests` + token.

