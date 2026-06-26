# CLAUDE.md — Fabric SupplyChain Operating Repo
> Current target: Enterprise ETL-aligned Microsoft Fabric ETL operating repository  
> Last updated: 2026-06-23 ICT

## Startup Acknowledgment

On loading this rule, reply exactly once before processing the first request:

`Super Rule v1.0 loaded. Enforcing §0 Zero-Hallucination → §1 Workflow → §3 Challenge-Mode → §4 Communication. Ready.`

## Operating Principles

- Primary language with Aric: Vietnamese. Keep object names, paths, API names, SQL, DAX, errors, and technical terms in English.
- No hallucination. For technical claims, prefer verified repo artifacts, live Fabric/Power BI/SQL evidence, Microsoft docs, Enterprise ETL guide docs, and exported definitions.
- Challenge-mode is mandatory for architecture, ETL, schema, semantic, operational, or cloud decisions. Do not rubber-stamp proposed changes.
- Preserve the business product surface unless Aric explicitly changes scope:
  - keep Bronze/Silver/Gold layers
  - keep existing business views/tables
  - keep 04_semantic/report contracts
  - replace or operate the framework/runtime, not the business logic
- Destructive operations need explicit same-conversation approval:
  - file/folder delete
  - `DROP`, `TRUNCATE`, destructive `ALTER`, destructive `MERGE`
  - force/reset/clean/overwrite actions
  - Fabric/Power BI/cloud deletes or unclear production mutations

## Current Architecture Source Of Truth

Use these first, in order:

1. `00_CONTEXT/current.md` — current working state and latest actions.
2. `01_docs/Enterprise_Framework_Migration_Master_Plan.md` — Phase 1 Enterprise ETL migration plan and status.
3. `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1_done_handoff_20260623.md` — Phase 1 completion handoff.
4. `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1h_final_cleanup_audit_20260623.txt` — final Phase 1 cleanup/audit evidence.
5. `01_docs/enterprise-etl-framework/source/` — Enterprise ETL guide docs and email-derived architecture summary.
6. `02_marts/` and `03_operations/orchestration/` — current mart definitions and ad-hoc run manifests.
7. `99_archive/architectures/` — old v8/v9/v10 knowledge archive; useful history, not current source of truth.

## Context Logging

Every assistant run must be resumable.

- Always read `CLAUDE.md` and `00_CONTEXT/current.md` at the start of a technical turn.
- Append/update `00_CONTEXT/current.md` after meaningful changes:
  - repo edits
  - tool/script execution
  - live Fabric/Power BI/SQL mutation
  - important decision or blocker
- `00_CONTEXT/` owns project context now.
  - Each dated chunk covers at most four calendar days.
  - `00_CONTEXT/current.md` mirrors the latest active chunk and is the default append target.
  - `00_CONTEXT/_source/CONTEXT_full_before_split_20260623.md` preserves the pre-split full file.
- Keep context entries short but complete:
  - timestamp ICT
  - scope lock
  - user instruction
  - commands/actions/evidence
  - files changed/live changes
  - blocker/risk
  - next concrete step

## Fabric Scope Lock

| Resource | Current value |
|---|---|
| Tenant | `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d` |
| Workspace DEV | `Enterprise SupplyChain-Dev` / `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Source Lakehouse | `Enterprise_Lakehouse` / `584e7d2c-46ca-49dc-bb6c-68df6ef4f424` |
| Processing Warehouse | `SupplyChain_Processing_Warehouse` / `c0262cef-b8a7-495f-bccc-53b098c7948c` |
| Gold Warehouse | `SupplyChain_Gold_Warehouse` / `98e2a911-5af9-442e-9cc8-5d8dadb8b762` |
| Local ETL Framework | `ETL_Framework` / `d4eb02f9-c29e-4f0d-9870-43b5970b349f` |
| SQL endpoint | `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com` |
| Current semantic model | `sc_control_tower` / `f06a2361-15fd-4f91-9d37-941fefe62aaf` |
| Legacy report-bound model | `Supply Chain Control Tower` / `3eecf594-...` |

## Current Runtime Contract

[Verified] Phase 1 is complete as of 2026-06-23.

- Primary runtime/load framework:
  - `Enterprise SupplyChain-Dev.ETL_Framework`
  - schema `DW_Developer`
  - `TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog`
  - Enterprise ETL loader/wrapper procedures including `usp_IncrementalTableLoad`
- Medallion layers remain:
  - Bronze/source: `Enterprise_Lakehouse`
  - Silver/processing: `SupplyChain_Processing_Warehouse`
  - Gold/serving: `SupplyChain_Gold_Warehouse`
  - Analytics: shared 04_semantic/report layer
- Canonical Enterprise/Enterprise ETL curated warehouse pattern:
  - Bronze/source docs list source lakehouse shortcuts and source tables.
  - Silver/Gold final schemas hold physical final tables.
  - Silver/Gold `_Wrk` schemas hold `v_<TableName>` work/source views.
  - `ETL_Framework` loader procedures derive `_Wrk.v_<TableName>` from final `SchemaName` + `TableName`.
  - Base-schema `v_*` views have been removed from active Silver/Gold curated schemas and must not be reintroduced.
  - `_LOAD` is transient loader work surface.
- `SupplyChain_Processing_Warehouse.Meta.usp_GenericLoad` is fallback/rollback only, not the target primary runtime.
- Do not rerun full curated refresh packs unless Aric explicitly requests it.

## Live Pipeline IDs

| Pipeline | ID | Notes |
|---|---|---|
| `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | top-level orchestrator; schedules exist but were disabled in the 2026-06-15 audit |
| `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | per-project router |
| `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | staging/reference load |
| `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | project-aware silver dispatcher |
| `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | wave executor |
| `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | project-filtered Gold publisher |
| `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | on-demand DQ gate |

## Auth And Tooling

```bash
# Validate identity
az account show

# Warehouse / pyodbc token
az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv

# Fabric REST token
az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

# Power BI REST token
az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv

# OneLake token
az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv
```

Preferred tool order:

1. Repo artifacts and exported definitions.
2. Fabric/Power BI MCP tools if available.
3. `az rest` for Fabric/Power BI REST.
4. `pyodbc` with Entra token for Warehouse SQL endpoint.
5. Python scripts in `03_operations/tools/` for repeatable ad-hoc workflows.

## Manual Refresh Rule

- Use `03_operations/orchestration/*/manifest.yaml` for dependency order.
- Default scripts must run dry-run first.
- Live execution requires explicit `--execute` and a current Aric approval.
- Order is always:
  1. `forecast_accuracy` Silver wrapper, then Gold wrapper
  2. `inventory_health` Silver wrapper, then Gold wrapper
  3. Silver wrappers include `ReferenceMaster_Enh` prerequisite Wave 00
  4. Gold wrappers include `Shared_DW` prerequisite Wave 00
  5. DQ/parity/semantic smoke after publish

## Persistence Rule

After major work, propose only the next useful persistence target, for example:

`Propose persisting to 01_docs/decisions/ADR-XXX.md: "<concise content, <=3 lines>". Confirm? (y/n)`

Do not write new project memory/ADR/runbook rules without explicit approval unless the user directly requested that file update.
