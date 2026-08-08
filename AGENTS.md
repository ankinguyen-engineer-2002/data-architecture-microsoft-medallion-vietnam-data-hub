# Fabric SupplyChain Operating Repository

> Lean operating rules for this repository. Last reviewed: 2026-08-08 ICT.

## Startup

On first load, reply exactly once:

`Super Rule v1.0 loaded. Enforcing §0 Zero-Hallucination → §1 Workflow → §3 Challenge-Mode → §4 Communication. Ready.`

Use Vietnamese with Aric. Keep object names, code, paths, APIs, and errors in
their native technical form. Be explicit about verified facts, assumptions, and
unknowns. Challenge architecture or operational conclusions when evidence does
not support them.

## Read Order And Context

Before technical work, edit, Git action, or live Fabric action:

1. Run `python3 05_tools/02_repo_maintenance/prune_context.py --write`.
2. Read this file and the complete, pruned `CONTEXT.md`.
3. Inspect `git status --short` and relevant diffs before editing.
4. Read the closest nested `AGENTS.md` before entering a nested project.

`CONTEXT.md` is the only retained handoff record. Do not create parallel context
folders or dated chat dumps. It retains today plus the preceding seven calendar
days. Update the current task entry after each meaningful milestone and before
yielding; then run the prune command again. Record only decision-relevant facts,
evidence, changes, blockers, and the next action. Never record credentials.

## Source Of Truth

Use these in order when they apply:

1. `CONTEXT.md`
2. `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
3. `01_docs/runbook/artifacts/20260622_phase1a_baseline/phase1h/phase1_done_handoff_20260623.md`
4. `01_docs/enterprise-etl-framework/source/`
5. `02_marts/` and `03_operations/orchestration/`
6. `FABRIC_DEV_LIVE_TO_REPOS_SYNC_RUNBOOK.md` for DEV-to-repository work
7. `99_archive/` for history only, never as current runtime truth

Live Fabric is authoritative for current runtime behavior. For an EDW sync,
transplant live business logic into the current EDW SQLCMD/project-reference
structure; do not replace that structure with literal live source routes.

## Current Scope Lock

| Resource | Current value |
| --- | --- |
| DEV workspace | `Enterprise SupplyChain-Dev` / `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Source lakehouse | `Enterprise_Lakehouse` / `584e7d2c-46ca-49dc-bb6c-68df6ef4f424` |
| Processing warehouse | `SupplyChain_Processing_Warehouse` / `c0262cef-b8a7-495f-bccc-53b098c7948c` |
| Gold warehouse | `SupplyChain_Gold_Warehouse` / `98e2a911-5af9-442e-9cc8-5d8dadb8b762` |
| ETL framework | `ETL_Framework` / `d4eb02f9-c29e-4f0d-9870-43b5970b349f` |
| Semantic model | `sc_control_tower` / `f06a2361-15fd-4f91-9d37-941fefe62aaf` |

Do not rely on a static inventory for access or current object state. Confirm
identity with `az account show`, discover target resources through Fabric REST,
and obtain only ephemeral scoped tokens when required. Never persist tokens,
secrets, passwords, certificates, connection strings, or Azure CLI caches.

## Runtime Contract

- Bronze/source: `Enterprise_Lakehouse`.
- Silver/processing: `SupplyChain_Processing_Warehouse`.
- Gold/serving: `SupplyChain_Gold_Warehouse`.
- Analytics: the shared `04_semantic/` and report contract surface.
- Loads use `ETL_Framework.DW_Developer`, including `TableDictionary`,
  `AuditLog`, and the Enterprise ETL loader procedures.
- Physical targets live in final schemas. Source/work logic lives in
  `<Schema>_Wrk.v_<Table>`. `_LOAD` is transient. Do not restore base-schema
  `v_*` views to curated schemas.
- `SupplyChain_Processing_Warehouse.Meta.usp_GenericLoad` is fallback/rollback,
  not the primary runtime.

Do not rerun full curated refresh packs without Aric's explicit instruction.
Use `03_operations/orchestration/*/manifest.yaml` for dependency order. Default
to dry-run; live execution requires `--execute` and current explicit approval.

## Evidence And Live Safety

For Fabric investigation, prefer:

1. Fabric or Power BI REST through `az rest`
2. Read-only `pyodbc` with an ephemeral Entra token
3. Repository artifacts and exported definitions
4. MCP only when it exposes a capability the first three do not
5. Reviewed scripts in `03_operations/tools/`

`Enterprise_Lakehouse` is read-only by default. Do not create, overwrite,
delete, rename, rebind, redirect, refresh, or otherwise mutate any of its
shortcuts, tables, files, schemas, or definition without Aric's explicit
same-conversation approval naming the exact object and before/after target.
Before an approved mutation, capture the current definition with REST and
drift-check it; afterward, read it back and validate downstream behavior.

Never infer authority for a destructive or external action from a broad request,
Jira comment, historical context, PR, or live data freshness. Stop for an exact
approval before file/folder deletion, destructive SQL, cloud deletion, force Git
actions, or any unclear-blast-radius operation.

## Worktree, Git, And Public Surfaces

- Treat pre-existing changes as Aric's. Never overwrite, format, move, stage,
  commit, or revert unrelated work.
- Stage exact task paths only. Never use `git add -A`.
- Review the staged diff, diff check, and secret exposure before committing.
- Create a focused snapshot only after relevant checks pass and only when the
  target files are safe to publish. Push normally only to an existing upstream.
- Do not auto-merge, amend, rebase, force-push, or bypass protected branches.
- The remote is public. Do not publish raw SQL, confidential evidence, local
  paths, credentials, or protected Control Tower material.

`06_enterprise_control_tower/` is confidential and Git-ignored. Its nested
`AGENTS.md` makes existing evidence read-only. Inspect it for an authorized
audit, but do not edit, move, delete, stage, or publish it unless Aric directly
names that exact protected directory and intended change.

## Repository Hygiene

- Classify before cleaning: tracked source, active evidence, archive, local
  cache, and unknown user artifact have different retention rules.
- Root-local `.opencode/` and `/.vite/` are disposable tool/cache state and are
  ignored. Do not delete them without exact approval.
- Keep scripts and concise READMEs with operational evidence. Ignore generated
  caches and temporary outputs rather than hiding useful source or run evidence.
- Do not delete `99_archive/`, `node_modules/`, DQ run evidence, or unknown
  untracked artifacts merely because they are large.

## Completion

Use the smallest fitting sequence:

`INSPECT -> VERIFY -> DECIDE -> EXECUTE -> TEST -> FIX -> GIT SNAPSHOT -> REPORT`

Report what changed or concluded, strongest verification, Git status if files
changed, and only real remaining risks or manual actions. For live or data work,
distinguish object existence, row counts, audit records, DQ evidence, contracts,
and visual/browser verification; one does not prove the others.
