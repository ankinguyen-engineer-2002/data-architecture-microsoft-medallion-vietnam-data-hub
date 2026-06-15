# AGENTS.md — Project Instructions
> SupplyChain Warehouse v9 — Microsoft Fabric, Pure T-SQL, Metadata-Driven
> Last updated: 2026-04-26 | Score: 8.2/10 | Enterprise mapping: ~91%

## Who I Am
- Name: Aric Nguyen
- Role: Data Engineer, DataHub VN team — Global Supply Chain Analytics at Ashley Furniture Industries
- Language: Vietnamese (primary communication), English (docs/code)
- Skills: T-SQL, PySpark, Microsoft Fabric, Azure, pipeline orchestration, data warehouse architecture
- Working style: Iterative — builds, hits constraints, adapts

## Project Overview
Warehouse-native medallion architecture on Microsoft Fabric. Pure T-SQL, no Notebooks/PySpark.
- ~91 objects: 4 schemas (bronze/silver/gold/meta), 28 data tables + 4 _edw supplement tables, 11 meta tables, 30 views, 11 SPs, 3 functions
- 7 pipelines: multi-mart architecture (ForEach projects -> pl_sc_mart -> bronze->silver->gold). DQ gates deactivated
- 1 generic SP handles 8 load patterns for all 28 tables
- Auto-trigger: daily 2AM UTC+7
- 11 meta tables: 8 core + 3 Phase 3 (performance_baseline, pipeline_cost_log, schema_contracts)
- Pipeline runtime: ~20 min (multi-mart, DQ off) or ~27 min (DQ on)

## Connection Details

| Resource | ID/Endpoint |
|----------|-------------|
| Tenant | `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d` |
| Workspace DEV | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Warehouse | `e146ffe2-d907-46a7-9b7e-3e739a31b24e` |
| SQL Endpoint | `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com` |
| Semantic Model | `a52841ee-d853-46df-b2f7-2a2cc4493d60` |
| Database | `SupplyChain_Warehouse` |

### Pipeline IDs
| Pipeline | ID |
|----------|-----|
| pl_sc_master | `319a8160-3f3a-4b87-8ad6-75ac4f3ec184` |
| pl_sc_mart | `9a1e7a12-30ab-465c-a45d-b051619193ac` |
| pl_bronze_forecast | `1bdbaebb-7222-4e9c-a45d-3e632bba846d` |
| pl_silver_forecast | `46437ae6-3a15-4697-957d-f1f44ba10633` |
| pl_silver_wave_forecast | `57a09720-21a2-49b5-a472-1e19abd14f76` |
| pl_gold_forecast | `94fc130e-f327-46a9-b7ba-cd2aa328c0da` |
| pl_dq_check | `c32dc18d-d027-4672-9872-f73404cd7c6f` |

### Token Commands
```bash
# Warehouse (pyodbc / sqlcmd)
az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv

# Fabric REST API
az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

# Power BI API
az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv

# OneLake (ADLS Gen2)
az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv
```

## Connectivity Workflow (API-first — no wandering)

Canonical reference: `docs/runbook/connectivity_playbook.md`.

- Default auth: `az login` interactive (no Service Principal unless automation requires it).
- REST ops: prefer `az rest --resource ... --url ...` (Fabric / Power BI / Azure).
- SQL endpoint: prefer `pyodbc` + Entra access token (ODBC attr `1256` with length-prefix + UTF-16LE). Canonical code: `lineage_explorer/export_lineage_data.py`.
- Modeling/TMDL: use Fabric `getDefinition`/`updateDefinition`; keep `definition/relationships.tmdl` as a separate part in payloads.
- MCP-first when available (Fabric/PowerBI/Modeling/Microsoft docs) → fallback to REST → fallback to Python.

## Mandatory Context Logging (anti-amnesia)

Every AI assistant run MUST be auditable and resumable across chat sessions.

1) Always read this file (`AGENTS.md`) at the start of every prompt/turn.

2) Context file rule (SINGLE FILE):

- If `CONTEXT.md` exists at repo root: DO NOT create a new context file. Always append/update `CONTEXT.md`.
- If `CONTEXT.md` does not exist: create it at repo root (only once), then keep appending/updating it.
- Do not create additional context files under `docs/runbook/` (legacy pattern). If any legacy context files exist, treat them as read-only history and consolidate into `CONTEXT.md`.
- Goal: persist the working state so a future session can continue without missing intent, decisions, evidence, and actions.

3) Update cadence (do NOT wait until the end of the user prompt):

- Append/update the context file after any meaningful change (repo file edits, tool outputs, command executions, decisions, live Fabric mutations).
- During long work, append at least once every ~15–30 seconds of active progress (best-effort within the constraints of the chat/tooling runtime).

4) Minimum content to record per update (short but complete):

- Timestamp (ICT) + scope lock (workspace/item/db).
- User instructions received since last update (verbatim or tight paraphrase).
- Actions executed (commands run, scripts, REST calls) + where artifacts/evidence saved.
- Files changed in repo (paths) and any live Fabric changes (what/where).
- Current blockers/risks + next concrete step (1–3 bullets).
