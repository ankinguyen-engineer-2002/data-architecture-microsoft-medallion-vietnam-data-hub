# AGENTS.md — Fabric SupplyChain Operating Repo
> Current target: Enterprise ETL-aligned Microsoft Fabric ETL operating repository
> Last updated: 2026-08-07 ICT

## Agent Applicability And Required Reading

This file is the repository instruction file for **every coding agent**, including Codex, OpenCode, Claude Code, sub-agents, and future automation agents.

- Before any technical investigation, edit, build, Git action, or live-platform action, locate and read this `AGENTS.md` in full.
- Also read the root `CONTEXT.md` in full; it is the complete retained history relevant to prior work.
- When a task enters a nested repository, worktree, or sibling repository, locate and obey its closest `AGENTS.md` too. The closest applicable instruction file adds to this one; it does not erase these safety and continuity rules.
- Do not rely only on the visible chat window. Treat the latest repository context as the persistent handoff record and reconcile it with the current conversation before acting.
- If the context is missing, stale, contradictory, or insufficient, state that clearly, inspect the available evidence, and repair the context record before claiming a conclusion.

## Startup Acknowledgment

On loading this rule, reply exactly once before processing the first request:

`Super Rule v1.0 loaded. Enforcing §0 Zero-Hallucination → §1 Workflow → §3 Challenge-Mode → §4 Communication. Ready.`

If the host agent's system instructions prohibit an exact acknowledgement, acknowledge the rules concisely without falsely claiming compliance with an impossible format.

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

1. `CONTEXT.md` — the only current project-context and agent-handoff file.
2. `01_docs/Enterprise_Framework_Migration_Master_Plan.md` — Phase 1 Enterprise ETL migration plan and status.
3. `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1_done_handoff_20260623.md` — Phase 1 completion handoff.
4. `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1h_final_cleanup_audit_20260623.txt` — final Phase 1 cleanup/audit evidence.
5. `01_docs/enterprise-etl-framework/source/` — Enterprise ETL guide docs and email-derived architecture summary.
6. `02_marts/` and `03_operations/orchestration/` — current mart definitions and ad-hoc run manifests.
7. `99_archive/architectures/` — old v8/v9/v10 knowledge archive; useful history, not current source of truth.
8. `01_docs/runbook/guides/supplychain_fabric_dev_to_pr_workflow.md` — mandatory workflow for Fabric DEV sync through PR/CI completion; the PR author stops before merge.

## Mandatory Context Retention And Conversation Continuity — Highest Repository Priority

This is the highest-priority repository instruction for every agent. It is mandatory and may only be superseded by host system/developer safety rules.

- `CONTEXT.md` is the **only** context file/folder permitted in this repository. Do not create `00_CONTEXT/`, dated context chunks, `_source/` context copies, or parallel agent-memory files.
- Retention window: keep the **latest seven prior calendar days plus today**. On `2026-07-27`, retain `2026-07-20` through `2026-07-27`; entries dated `2026-07-19` or earlier must be deleted.
- At the beginning of every technical turn, and immediately after writing a meaningful handoff, run:

  ```bash
  python3 05_tools/02_repo_maintenance/prune_context.py --write
  ```

  The script automatically removes expired entries. Do not continue routine technical work if this mandatory context-retention check fails; report the failure and repair it first.
- Then read `AGENTS.md` and the pruned `CONTEXT.md` in full before acting. Do not rely only on the visible chat window.
- Update `CONTEXT.md` after each meaningful user instruction or work milestone, including:
  - repo edits, commits, PR creation/retargeting, rebases, or push outcomes
  - tool/script execution
  - live Fabric/Power BI/SQL mutation
  - important decision or blocker
- Record the latest relevant conversation history as one concise, factual dated handoff entry. It must include:
  - timestamp ICT and scope lock
  - the user's latest objective, constraints, and explicit approvals
  - decisions made in the chat and why
  - commands/actions/evidence, including build/test/CI status
  - changed files, branches, commits, PRs, live resources, and external links/IDs when applicable
  - remaining risks/blockers and the next concrete action
- Do **not** paste an unbounded raw transcript or credentials/tokens into repository context. Summarize the decision-relevant chat accurately enough for a new agent to continue without asking the user to repeat it.
- Before ending a technical task, verify that `CONTEXT.md` reflects the work actually completed and does not claim unverified success. If no repository or live change occurred, log the investigation/result when it materially affects a later decision.
- If a work item spans several turns or agents, each agent must refresh this same file before yielding. Never leave important chat-only knowledge unpersisted.
- **Every conversation session is mandatory context work:** before sending the final response or otherwise yielding to the user, the agent must INSERT a new context note or UPDATE the current task's note. This applies even to a read-only investigation, explanation, plan, clarification, or “no change” result. The note must capture the user's request, the outcome/decision, and the next action; then run the retention script.
- This context rule is directly authorized by Aric. Updating/pruning `CONTEXT.md` under this policy does not require a separate persistence confirmation.

### Required Context Operations: INSERT, UPDATE, DELETE

- **INSERT (mandatory):** append one new `## YYYY-MM-DD HH:MM ICT — <short title>` entry immediately after a meaningful user instruction, verified investigation, code/Git/PR change, build/test/CI result, live-platform action, decision, approval, blocker, handoff, or end of a conversation session. Include only the facts needed for the next agent to resume safely.
- **UPDATE (mandatory):** amend the existing entry for the same active task/day when a fact changes or is corrected—for example a build changes from failing to passing, a PR is retargeted, approval is granted, or an assumption is disproven. Correct the earlier statement; do not leave contradictory facts or append a duplicate entry merely to correct it.
- **DELETE (strictly limited):** do not manually remove any entry inside the retained window. The only automatic deletion is `prune_context.py --write`, which removes entries older than the current date plus seven preceding calendar dates. Delete a retained entry only when Aric explicitly asks, or when it contains a secret; in the latter case remove/redact it immediately and record that a sensitive value was removed without reproducing it.
- **Ordering and integrity:** keep entries chronological, one task/milestone per entry, with a clear scope, evidence, changed targets, risk/blocker, and next action. Run the retention script immediately after every INSERT, UPDATE, or permitted DELETE.

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

Authentication is user-delegated Azure CLI only. Store resource metadata and access methods, never access tokens, refresh tokens, passwords, client secrets, certificates, or connection strings. This file records the current verified workspace/item inventory.

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

Preferred tool order for Fabric investigation and verification:

1. Fabric/Power BI REST API through `az rest` for workspace items, definitions, shortcuts, jobs, and current platform contracts.
2. Python `pyodbc` with an ephemeral Entra token for Warehouse/Lakehouse SQL endpoint metadata, definitions, compile checks, counts, DQ, and runtime evidence.
3. Repo artifacts and exported definitions for drift comparison and CI/CD intent.
4. Fabric/Power BI MCP tools only after REST and `pyodbc`, or when they expose a capability those primary tools do not.
5. Python scripts in `03_operations/tools/` for repeatable, reviewed workflows built on the same REST/`pyodbc` evidence.

## Enterprise Lakehouse Mutation Guard — Explicit Approval Required

`Enterprise_Lakehouse` is read-only by default for agents. Do not create, overwrite, delete, rename, rebind, redirect, refresh, or otherwise mutate its shortcuts, tables, files, schemas, or item definition unless Aric gives explicit same-conversation approval naming the exact object and intended before/after change.

- Broad directions such as “fix live”, “sync live”, “live is authoritative”, “make DEV match”, or “fix everything” do **not** authorize an `Enterprise_Lakehouse` mutation.
- Source freshness, row-count superiority, an empty window, a failing downstream load, or repo/lineage drift does not prove a new authoritative source route. Report the evidence and ask the source/platform owner to confirm or perform the route change.
- Prefer downstream fail-before-delete guards, diagnostics, and owner escalation when they solve the immediate safety problem without changing `Enterprise_Lakehouse`.
- Before any explicitly approved mutation, use Fabric REST to capture the exact current definition and drift-check it against the approved target. Afterward, verify the resulting definition with a fresh REST read and validate downstream behavior through Python `pyodbc` where applicable.
- Never infer `Enterprise_Lakehouse` mutation authority from a Jira comment, repository mapping, PR, historical context, or another person's proposed PROD implementation. The exact live change still requires Aric's direct approval.

## Azure/Fabric Access Inventory — Mandatory Repository Reference

This is the reusable access reference; it is not project history and therefore belongs in `AGENTS.md`, not `CONTEXT.md`. Refresh the inventory through Fabric REST before a live mutation.

- Tenant: `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d`
- Subscription: `DATAWAREHOUSE PROD` / `8e606065-9e63-4319-ba39-0ff434c72b39`
- Verified `az login` user on `2026-07-27`: `NAric@ashleyfurniture.com`
- Credential/access method: `az account show`; obtain an ephemeral scoped token only with `az account get-access-token` when needed. Never persist a token, secret, certificate, password, connection string, or local Azure CLI cache in this repository.

### Accessible Workspaces

`Supply Chain Analytics-Premium` `f0e1bc90-35c4-4e31-bc00-ff4a225152b7` · `SCP Global Team` `fb03479c-f98b-414f-bf8f-ab2dfa744ff4` · `SCP Team` `29ff4afb-7e3c-4218-9cc9-cd4e14e09551` · `DEV Global Supply Chain Analytics` `d61a0b3d-48d6-42f6-8bbe-11aed22a9bd2` · `EnterpriseData-Sandbox` `5360a935-1984-4775-895f-f4c90bafa19d` · `EnterpriseData` `ce4e6503-b368-496b-95e2-63b43c8b3b0a` · `Enterprise SupplyChain` (production) `d9cc38a6-0d7f-4913-9181-d1443c381b65` · `Enterprise SupplyChain-Dev` `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` · `Enterprise Retail-Sandbox` `6c64a79f-f68e-45bb-b287-6c336b89952f`.

### Warehouse And Lakehouse Inventory

- `Supply Chain Analytics-Premium`
  - Lakehouse: `StagingLakehouseForDataflows_20260213151631` — `e71d8366-8ed7-45a3-b544-ba2f10b8addc`
  - Warehouse: `StagingWarehouseForDataflows_20260213151656` — `bd96a2c0-77ee-4d41-8cc1-786dc57e6682`
- `EnterpriseData-Sandbox`
  - Lakehouses: `A_Developement` `1545d3ce-0fae-40b5-b314-ac2fd43e25c5`; `RadarSync_Test` `ddadbe2e-c2e2-4949-8e84-81eed6a81c9e`; `Centralized_Lakehouse` `50e11300-9fb4-4e82-876c-7183bb2501ba`; `StagingLakehouseForDataflows_20251008191803` `c2583202-eb6f-49bb-9f2f-1bb551b786b0`; `DataflowsStagingLakehouse` `68d19239-4abc-456b-9fa4-5dceb4b2d99e`.
  - Warehouses: `ETL_Framework` `02c8970b-7af3-4d4e-b011-cc3cdc3825ef`; `Source_Data` `f14e2ea6-ae2c-4b90-8e08-522e84f1aefc`; `Centralized_Warehouse` `c5a1f95b-f9db-4cb7-8ded-396ea70da572`; `Retail_Warehouse` `09504907-575d-446a-991a-87fa525166d7`; `Distribution_Warehouse` `7d51a21f-c1fe-4968-930d-1702c0ee39dc`; `MasterData_Warehouse` `db565620-28ac-4510-a61e-1023743efdc6`; `Wholesale_Warehouse` `c1ef4a62-f8e2-4d55-96bd-33eb07b81b7c`; `StagingWarehouseForDataflows_20251008191817` `0f273877-0905-4a68-b1c3-814f5c532f43`; `DataflowsStagingWarehouse` `4cf62bd7-4fe0-4785-bcd4-0f95977725eb`; `Quality_Warehouse` `6a6129c1-5342-4ea2-bcb8-9b8a1af8db20`; `Test_Owneraccess` `2d1d459e-debb-439d-876a-34cd30c44961`; `SupplyChain_Warehouse` `3c9afac8-f1c6-495a-9e09-09f1d7b086b0`; `HR_Warehouse` `673eeb21-89b5-4946-9313-503e26c19739`.
  - Mirrored Databricks: `edw_dev` `1e284ab4-dc84-4421-a96d-fe4f942cec97`; `customersupporthub` `a371ca53-ce55-469b-aaa7-b0238e31a42b`.
- `EnterpriseData`
  - Lakehouse: `Centralized_Lakehouse` `08de1cf3-d529-4a71-8f6f-4c8d6f3b2018`.
  - Warehouses: `ETL_Framework` `0d84211d-d326-4efd-956f-c0d1a5350db5`; `Enterprise_Warehouse` `3468b240-13c9-466d-af75-e28d374b93cc`; `Source_Data` `d27b3ef9-a331-4489-abca-588f909c4321`; `A_Production2` `67ea8404-016d-4875-8f63-816fa6a8461e`; `Retail_Warehouse` `d8bec39c-5973-47e9-aa68-67c0f0c4a771`; `MasterData_Warehouse` `d8e6439b-830d-421d-aa3e-435fc8bacacf`; `Wholesale_Warehouse` `9293af4e-3974-4ec0-b619-fc3c64c42c0c`; `Centralized_Warehouse` `513a8f2c-b434-4ded-bcaf-30a6ebfd4cd1`; `SupplyChain_Warehouse` `d926e44c-d23f-4762-873e-0f3edbc94319`; `EnterpriseData` `83183106-3f76-4d7a-866e-4560499abac8`; `Quality_Warehouse` `063c11ae-85e1-4736-af5f-52b0e27746ec`; `Distribution_Warehouse` `c4099421-5fe1-4968-930d-1702c0ee39dc`; `AI_Warehouse` `d47c0980-f969-482c-9633-cc4f7d628c2a`.
  - Mirrored Databricks: `edw_prod` `19714c5c-bcb1-46a8-9a77-4736b1ac397b`; `Databricks` `c4026038-48f4-47da-bd03-1048aed00aec`; `customersupporthub` `a853e370-ebc3-4bf2-8e2e-faba55866897`.
- `Enterprise SupplyChain` (production)
  - Lakehouses: `Enterprise_Lakehouse` `92a6098d-5e4d-440b-9e77-b7b8681da30c`; `SupplyChain_Lakehouse` `919e2391-5d46-44f1-84e8-0137ed01016e`; `StagingLakehouseForDataflows_20251218201154` `091c1f3f-76a0-4309-a897-44714ec560f3`; `SupplyChainPlanning_lh_cdca5839445743e68471922634b134ed` `470b6c04-2758-4c49-96d0-d88b4cf40205`.
  - Warehouses: `ETL_Framework` `09b2402d-fd61-498f-a7e8-a42bb92c55be`; `SupplyChain_Warehouse` `22ca16aa-bbbc-46e3-b316-2c1379abdce8`; `StagingWarehouseForDataflows_20251218201208` `e0674a25-d78a-44d3-b34d-af059d7614dd`; `SupplyChain_Gold_Warehouse` `1f95b472-ab22-46c8-9f8a-51676cb1bf71`; `SupplyChain_Processing_Warehouse` `56d53d8c-53aa-40d7-8e77-f1b84d68df3a`.
- `Enterprise SupplyChain-Dev`
  - Lakehouses: `Enterprise_Lakehouse` `584e7d2c-46ca-49dc-bb6c-68df6ef4f424`; `SupplyChain_Lakehouse` `62a3081e-4093-4f46-856f-f50aa58732fa`; `StagingLakehouseForDataflows_20251008171206` `e3012f7c-eaba-44ff-8252-05d79661b09d`.
  - Warehouses: `ETL_Framework` `d4eb02f9-c29e-4f0d-9870-43b5970b349f`; `SupplyChain_Warehouse` `e146ffe2-d907-46a7-9b7e-3e739a31b24e`; `StagingWarehouseForDataflows_20251008171231` `b8182cdf-abb6-4d13-b1be-2837ae8efac2`; `SupplyChain_Processing_Warehouse` `c0262cef-b8a7-495f-bccc-53b098c7948c`; `SupplyChain_Gold_Warehouse` `98e2a911-5af9-442e-9cc8-5d8dadb8b762`.
  - Mirrored database: `SCPGlobalTeam_SharepointLists` `405b5771-6be2-4f09-82d5-42fbf186a811`.
- `Enterprise Retail-Sandbox`
  - Lakehouses: `StagingLakehouseForDataflows_20251031143937` `c75bf692-24d4-40d7-9c2b-acad4ec0f83e`; `Enterprise_Lakehouse` `495555b8-2a22-48b7-93f3-3f07a5895378`; `Retail_Lakehouse` `fc55fdfb-380a-4167-9ed1-c6232f9db8fd`.
  - Warehouses: `StagingWarehouseForDataflows_20251031144011` `cceaa068-b99b-4a4b-9ead-ea3a185f05d3`; `ETL_Framework` `242e75ee-ec5c-4f00-96b3-f5c51d9e1e1f`; `Pricing_Warehouse` `e17ee6a1-87ec-4c88-905a-702a7227a7b5`; `Retail_Commissions` `c3bde369-f4e0-40af-9b34-bdee7b90fec7`; `Merchandising_Warehouse` `53e01096-f4a6-480b-9f07-c027f7748b77`; `Retail_Warehouse` `fd86af74-b80d-41ac-94e8-15c6b34832c4`.

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
