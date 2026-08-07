# Fabric DEV Live -> Operating Repo -> EDW Repo Sync Runbook

> Current scope: Enterprise Supply Chain DEV, Processing/Gold code synchronization, repository CI/CD, and web lineage evidence.
> Primary rule: **live Fabric DEV is authoritative for runtime business logic; each repository receives only the representation appropriate to that repository.**
> Last verified example: 2026-08-07 ICT.

## 1. Purpose

This root runbook defines one repeatable process for synchronizing changes across
three different surfaces:

1. **Fabric DEV live runtime** in `Enterprise SupplyChain-Dev`.
2. **This operating repository** (`20260413_Fabric_Refactor_Architect`).
3. **The EDW CI/CD repository** (`afi-internal/data-edw-fabric`).

It answers four questions:

- Which surface is authoritative?
- Which objects belong in each repository?
- In what order must synchronization and validation run?
- What evidence is required before commit, PR, lineage publication, or handoff?

This is a code-synchronization runbook. It does not authorize data refresh,
pipeline execution, production promotion, destructive SQL, PR merge, or any
other live/cloud mutation outside the explicit task approval.

## 2. Non-negotiable rules

### 2.1 Live DEV is the runtime source of truth

Use live Fabric DEV as the authority for:

- current view transformation logic;
- exact live schema, table, and column identifiers;
- live hotfixes and identifier casing;
- live object existence and compilation;
- current shortcut target definitions;
- current SQL dependency evidence.

Do not infer live success from repository files, filenames, a successful build,
`AuditLog`, or `TableDictionary` alone.

### 2.2 The two repositories have different responsibilities

The operating repository and EDW repository are not identical mirrors.

| Surface | What it represents | Synchronization behavior |
|---|---|---|
| Fabric DEV live | Actual runtime code and shortcut routes | Fix first when explicitly approved; validate directly after every write. |
| Operating repo | Live-oriented mart packages, build stubs, operational evidence, and lineage | Preserve live runtime syntax and source naming where needed for accurate local build and lineage. |
| EDW repo | Deployable enterprise SQL project and CI/CD contract | Transplant live business logic into approved SQLCMD/project-reference structure; do not copy literal live routes blindly. |

### 2.3 Do not synchronize everything everywhere

Every detected difference must be classified before editing.

- A live view logic change usually belongs in both repositories.
- A live shortcut rebind belongs to Fabric live; the operating repo may record
  it in lineage evidence, while EDW usually keeps its existing logical SQLCMD
  route.
- A live `Enterprise_Lakehouse` reference normally stays literal in the
  operating repo but becomes an approved EDW logical reference such as
  `$(Source_Data)`, `$(Wholesale_Warehouse)`, `$(MasterData_Warehouse)`, or
  `$(SupplyChain_Warehouse)`.
- A table DDL change is synchronized only when the actual table contract changed
  and the object is in scope.
- Stored procedures and pipelines are excluded by default for the current user
  scope. Include them only when explicitly requested.
- Data rows, refresh state, and backfill results are never copied as source code.

### 2.4 Build before EDW commit or PR

No EDW commit or PR is allowed before the full solution build completes with
`0 Error(s)`.

The PR author stops after the PR is review-ready and the GitHub build succeeds.
The author does not merge unless separately authorized.

### 2.5 Preserve unrelated work

- Inspect `git status` before every edit and Git action.
- Assume existing changes belong to the user.
- Stage only explicit task paths.
- Never use `git add -A`, `git reset --hard`, destructive restore, rebase, amend,
  force-push, or cleanup commands unless specifically authorized.

## 3. What is synchronized to each target

| Object/evidence | Fabric DEV live | Operating repo | EDW repo |
|---|---:|---:|---:|
| Processing `_Wrk` view business logic | Runtime authority | Yes, mart copy and SQLPROJ package copy | Yes, adapted to EDW SQLCMD routes |
| Gold `_Wrk` view business logic | Runtime authority | Yes, mart copy and SQLPROJ package copy | Yes, adapted to EDW SQLCMD routes |
| Final table DDL | Actual live contract | Only when verified and in scope | Only when verified and required by CI/CD contract |
| Bronze/source compile stubs | Actual source objects/columns | Yes, minimal exact live compile contracts | Use approved external warehouse project contracts, not live shortcut copies |
| Lakehouse shortcut route | Actual runtime route | Record in live baseline/lineage | Normally represented by SQLCMD/project references, not copied literally |
| Identifier casing | Exact live authority | Match exact live case | Match approved external contract case |
| `TableDictionary` | Runtime governance evidence | Export/audit as evidence; do not blindly overwrite | Not copied unless specifically part of EDW framework scope |
| Stored procedures | Runtime authority | Excluded unless requested | Excluded unless requested |
| Pipelines | Runtime orchestration | Excluded unless requested; may be audited | Not copied as Warehouse SQL code |
| Semantic model bindings | Runtime analytics evidence | Used by lineage portal | Not part of Processing/Gold SQL PR unless explicitly scoped |
| Row counts/backfills | Runtime/data validation only | Evidence, not code | Not synchronized as code |
| Lineage snapshot | Read-only live evidence | Yes, sanitized and tested | EDW target manifest is generated from an exact commit/PR SHA |

## 4. Required execution order

```text
1. Context and scope lock
2. Fresh live read-only scan
3. Difference classification
4. Live DEV fix, only when explicitly authorized
5. Live post-fix validation
6. Operating repo synchronization
7. Operating repo build and lineage validation
8. Operating repo focused Git snapshot
9. Fresh EDW main baseline
10. EDW structural adaptation
11. Full EDW solution build
12. EDW focused commit, push, and PR
13. GitHub CI verification
14. Lineage manifest/snapshot refresh when behavior or routes changed
15. Context and reviewer handoff
```

Never reverse steps 4-7 by treating a stale repository as the live authority.
Never create an EDW PR before steps 9-11 pass.

## 5. Detailed procedure

### Step 1 - Lock context, scope, and safety boundary

From the operating repository root:

```bash
python3 05_tools/02_repo_maintenance/prune_context.py --write
git status --short --branch
```

Then read:

1. `AGENTS.md`;
2. `CONTEXT.md`;
3. this runbook;
4. `01_docs/runbook/guides/supplychain_fabric_dev_to_pr_workflow.md`;
5. any closer `AGENTS.md` in the EDW repository.

Write down the exact scope before querying or editing:

- live workspace and Warehouse items;
- object classes in scope;
- whether live writes are authorized;
- whether stored procedures/pipelines are excluded;
- whether the task is code-only or also includes data/DQ/runtime validation;
- whether commit/push/PR is authorized;
- explicit stop-before-merge boundary.

### Step 2 - Validate identity and acquire ephemeral access

Use delegated Azure CLI identity only:

```bash
az account show
az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
```

Rules:

- Keep tokens in memory only.
- Never write tokens, secrets, connection strings, or Azure CLI cache into a
  repository file, context, build log, snapshot, or PR.
- Prefer Fabric REST for item/shortcut definitions and `pyodbc` with Entra token
  plus `ApplicationIntent=ReadOnly` for SQL inspection.

### Step 3 - Capture a fresh live baseline

Use Fabric REST to verify:

- current workspace item inventory;
- exact Warehouse/Lakehouse item identity;
- shortcut names, paths, and target item identities;
- semantic-model definition when lineage is in scope.

Use `pyodbc` to capture:

- `sys.tables`, `sys.views`, `sys.procedures`, and columns;
- `sys.sql_modules` definitions and hashes;
- `sys.sql_expression_dependencies` when permission is available;
- `TableDictionary`, `AuditLog`, and update-log evidence when relevant;
- `SELECT TOP (0)` compile/binding probes for every targeted view;
- exact-case source object existence and required columns.

For a code-only synchronization, do not automatically run large row-count,
backfill, refresh, or DQ workloads. Add those checks only when the user requests
runtime/data validation.

Recommended repeatable exporters in this repository:

```bash
python3 05_tools/03_mart_sync/sync_live_mart_layers.py
python3 05_tools/03_mart_sync/export_dev_runtime_contract.py
```

These scripts write local repository artifacts. Inspect their diff immediately
and never assume every generated file belongs to the current task.

### Step 4 - Classify every difference

Classify each delta into exactly one primary category:

| Delta type | Meaning | Default action |
|---|---|---|
| Business transformation delta | `SELECT`, join, filter, calculation, grain, or DQ logic differs | Sync to operating repo and adapt into EDW repo. |
| Source-route delta | Same logic, different live versus EDW database route | Keep live route in operating repo; preserve approved SQLCMD route in EDW. |
| Identifier-case defect | Object exists but live definition uses wrong case | Fix live if approved; sync exact case to both representations. |
| Shortcut-target defect | Shortcut points to wrong upstream item | Fix live through REST if approved; update lineage evidence; EDW changes only if its logical contract is wrong. |
| Table-contract delta | Column/type/nullability/grain changed | Validate downstream impact, then update only required DDL/stubs. |
| Repository-only intent | Approved future CI/CD structure not deployed live | Keep separate from live truth and label it as repository target. |
| Lineage/UI evidence delta | Code is correct but snapshot/portal is stale | Refresh sanitized lineage evidence; do not alter SQL. |
| No behavior delta | Definitions normalize to the same logic after route adaptation | Do not invent SQL changes; use documentation/traceability only when requested. |

Stop when the mapping is ambiguous, a source object is missing, required columns
do not match, a route is unreadable, or the proposed change would alter grain.

### Step 5 - Fix Fabric DEV live first, when authorized

Before every live write:

1. Export the exact current view or shortcut definition.
2. Save a temporary local backup outside Git.
3. Record a SHA-256 or equivalent drift assertion.
4. Re-read the object immediately before writing.
5. Abort if the definition changed since the backup.

For SQL view fixes, use the smallest targeted `ALTER VIEW` required. For
shortcut fixes, use Fabric REST `CreateOrOverwrite` with the exact existing
path and intended target. Do not delete and recreate source data.

Immediately after each write, verify:

- object definition is the intended definition;
- source object exists with exact case;
- `SELECT TOP (0)` succeeds;
- dependency metadata points to the intended source;
- no unrelated object changed.

Live writes require explicit same-conversation approval. A repository sync
request by itself does not authorize live mutation.

### Step 6 - Synchronize the operating repository

The operating repository receives live-oriented artifacts.

For a changed Processing/Gold view, update all applicable copies:

```text
02_marts/<mart>/02_silver/... or 03_gold/...
03_operations/deployment/sqlproj/SupplyChain_Processing_Warehouse/...
03_operations/deployment/sqlproj/SupplyChain_Gold_Warehouse/...
```

When the live view references a source contract needed for local SQLPROJ build,
update only the exact minimal stub under:

```text
03_operations/deployment/sqlproj/Enterprise_Lakehouse_Reference/
```

Operating-repo rules:

- Keep the live runtime database/source representation where required.
- Keep exact live identifier casing.
- Update table DDL only when a verified live contract changed.
- Do not import every live object merely because it exists.
- Do not stage archived, generated, temporary, or unrelated dirty files.
- Do not include stored procedures/pipelines when they are excluded by scope.

### Step 7 - Validate the operating repository

Run the SQLPROJ build:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

Required result:

- all projects complete with `0` errors;
- no new source-route, identifier-case, or object-contract warning caused by the
  change;
- existing unrelated warnings are identified honestly, not hidden.

Also verify:

```bash
git diff --check
git status --short
```

For duplicate mart/package copies, compare normalized SQL bodies and require an
exact match after removing only formatting or repository-specific wrappers.

### Step 8 - Refresh and validate operating lineage

Refresh repository target evidence only from a clean EDW worktree and exact SHA:

```bash
cd 05_tools/06_lineage_portal
PYTHONPATH=. python3 -m scanner.repository_manifest \
  --repo-root /path/to/clean/data-edw-fabric \
  --expected-sha <full-edw-sha> \
  --pull-request <pr-number> \
  --out repository_lineage_manifest.json
```

Refresh delegated live evidence:

```bash
FABRIC_USE_AZ_CLI=1 PYTHONPATH=. python3 -m scanner.cli \
  --repository-manifest repository_lineage_manifest.json \
  --write-live-baseline live_lineage_baseline.json \
  --out site-v2/public/lineage_snapshot.json
```

Run the portal gates:

```bash
PYTHONPATH=. python3 -m unittest discover -s tests -v
cd site-v2
npm run test:views
npm run typecheck
npm run build
```

Required lineage conditions:

- no dangling, duplicate, self, backward, same-column, or cycle defect;
- mart filters contain only objects with a real directed path to the selected
  mart;
- semantic bindings are complete for the expected model;
- live and EDW target routes are labeled separately;
- zero raw SQL definitions, credentials, or secrets are published;
- generated public and build artifacts have matching hashes when required.

Do not update the expected EDW manifest SHA/PR merely because a documentation-
only PR exists. Update lineage target evidence only when the EDW behavior or
dependency graph actually changed.

### Step 9 - Create the operating-repo Git snapshot

After all relevant checks pass:

1. Review the complete task diff.
2. Stage only explicit approved paths.
3. Inspect `git diff --cached --check`, staged names, and staged content.
4. Scan for credentials, tokens, raw SQL publication, binaries, and caches.
5. Commit one coherent change.
6. Push normally only to the established upstream allowed by repository policy.

Never stage `CONTEXT.md` together with unrelated accumulated context changes
unless its complete staged diff is intentionally part of the commit.

### Step 10 - Refresh the EDW repository baseline

Do not use a stale feature checkout. Use a clean clone or worktree based on the
current remote `main`:

```bash
git fetch origin main --prune
git switch main
git pull --ff-only
git switch -c feature/<short-supplychain-change>
```

Before editing, verify:

- `HEAD == origin/main`;
- worktree is clean;
- no merge/rebase/conflict/detached-HEAD state exists;
- no open PR already represents the same task;
- closest EDW repository instructions have been read.

### Step 11 - Adapt live logic to the EDW structure

EDW synchronization is a structural transplant, not a literal copy.

Example:

```text
Live DEV:
  [Enterprise_Lakehouse].[SalesHistory_AFI].[InvoiceDetail]

EDW repo:
  [$(Wholesale_Warehouse)].[SalesHistory_AFI].[InvoiceDetail]
```

The transformation body should match after normalizing only approved route
differences. Preserve:

- SQLCMD variables;
- project references;
- publish profiles;
- external warehouse contracts;
- exact schema/table/column case;
- repository naming and SQL project conventions.

The approved external source families are not interchangeable:

```text
Source_Data
Wholesale_Warehouse
MasterData_Warehouse
SupplyChain_Warehouse
```

Never replace every former Databricks reference with one database using a broad
string replacement. Validate each source mapping and business grain.

For a routine code sync, edit only:

```text
SupplyChain_Processing_Warehouse/
SupplyChain_Gold_Warehouse/
```

Add a minimal external source contract only when it is missing, verified, and
explicitly approved for the PR.

### Step 12 - Validate EDW scope and build

Before staging:

```bash
git status --short
git diff --check
git diff --name-only origin/main
```

Stop if the diff includes:

- an unapproved `Databricks/` object;
- a remaining scoped `$(Databricks)` reference;
- unrelated warehouse/domain files;
- generated `bin/` or `obj/` artifacts;
- a literal live database route that should be an SQLCMD reference;
- any unexplained file.

Run the full solution build with the pinned SDK:

```bash
dotnet --version  # must match the repository-pinned SDK, currently 9.0.303
dotnet build EDW-Fabric.sln \
  --configuration Release /p:NetCoreBuild=true --no-restore
```

Required result: `0 Error(s)`.

Classify every warning. A warning introduced in a Supply Chain project is a
stop condition unless it is corrected or explicitly accepted by the owner.

### Step 13 - Commit, push, and create the EDW PR

Stage exact paths only:

```bash
git add -- <approved-path-1> <approved-path-2>
git diff --cached --check
git diff --cached --name-only
git diff --cached
```

Then:

```bash
git commit -m "fix(supplychain): <actual outcome>"
git push --set-upstream origin <branch>
```

The PR body must state:

- live DEV source and exact objects checked;
- what changed in live;
- what changed in EDW;
- what is intentionally different because of SQLCMD adaptation;
- whether the PR changes behavior or only records alignment;
- local full-build command and result;
- remaining warnings and their ownership;
- no unapproved Databricks objects/references;
- explicit stop-before-merge boundary.

### Step 14 - Verify GitHub CI and final PR state

The PR is review-ready only when:

- the head SHA is the intended commit;
- changed files match the approved scope;
- `Build the database project` is `SUCCESS` for that exact SHA;
- PR is open against `main`;
- no unresolved build failure exists;
- reviewer receives an accurate summary.

`mergeStateStatus=BLOCKED` may simply mean branch protection or review is still
required. It is not a build failure when the required build check is successful.

Do not merge.

### Step 15 - Update context and handoff

Update `CONTEXT.md` with:

- timestamp and scope;
- live changes and backup evidence;
- operating-repo changed paths, commit, and push;
- EDW branch, commit, PR, local build, and GitHub build;
- lineage workflow/snapshot result when applicable;
- exclusions, residual risk, and next owner action.

Then run:

```bash
python3 05_tools/02_repo_maintenance/prune_context.py --write
```

## 6. Validation gates by surface

### 6.1 Fabric DEV live gate

- [ ] Correct workspace and items verified by REST.
- [ ] Exact definitions backed up before write.
- [ ] Drift assertion passed immediately before write.
- [ ] Target source objects exist with exact case.
- [ ] Required columns and business grain match.
- [ ] Every targeted view passes `SELECT TOP (0)`.
- [ ] Shortcut paths point to approved target items.
- [ ] No unrelated live object changed.

### 6.2 Operating repo gate

- [ ] All required mart and SQLPROJ copies are synchronized.
- [ ] Minimal source stubs match live contracts.
- [ ] No excluded stored procedure/pipeline was imported.
- [ ] `build_all.sh` completes with `0` errors.
- [ ] No new warning is caused by the change.
- [ ] Lineage tests, projections, typecheck, and build pass when lineage changed.
- [ ] Public artifacts contain no raw SQL or secrets.
- [ ] Only explicit task paths are staged.

### 6.3 EDW repo gate

- [ ] Branch starts from fresh `origin/main`.
- [ ] Live business logic matches after approved route normalization.
- [ ] SQLCMD/project-reference structure is preserved.
- [ ] External contracts and identifier case are exact.
- [ ] Scoped `$(Databricks)` count is zero.
- [ ] Full `EDW-Fabric.sln` build returns `0 Error(s)`.
- [ ] No new Supply Chain warning exists.
- [ ] Staged diff contains only approved paths and no secrets.
- [ ] GitHub build succeeds for the exact PR head.
- [ ] PR author does not merge.

### 6.4 Lineage gate

- [ ] Live snapshot uses current delegated evidence or a valid fresh baseline.
- [ ] Repository manifest uses an exact EDW behavior SHA/PR.
- [ ] Live and repository edges are not conflated.
- [ ] Selected mart views contain only connected upstream/downstream objects.
- [ ] Semantic bindings are complete.
- [ ] Snapshot is sanitized and production gate passes.
- [ ] Deployed artifact hash matches the validated local artifact when deployed.

## 7. Stop conditions

Stop and report instead of editing, committing, or publishing when:

- live authorization is missing;
- the source mapping is ambiguous;
- the proposed target lacks required columns or changes grain;
- a shortcut route is missing or points to an unapproved target;
- the live object changed after backup;
- an unexpected user-owned file changes during work;
- operating SQLPROJ or EDW full build has an error;
- a new Supply Chain warning is introduced;
- EDW diff contains unrelated files or literal live routes;
- a token, secret, connection string, or raw enterprise SQL would be published;
- PR head/base/scope does not match the intended task;
- lineage evidence is stale, incomplete, fixture-based, or semantically invalid;
- the requested action would require merge, production promotion, destructive
  SQL, pipeline execution, or data refresh without explicit approval.

## 8. Verified 2026-08-07 synchronization example

This example records the latest completed flow and demonstrates how the rules
above apply.

### 8.1 Live DEV findings and fixes

The audit found:

- `ReferenceMaster_Enh_Wrk.v_ItemMaster` referenced the nonexistent
  `SalesHistory_AFI_Enh.InvoiceDetail` route;
- `SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel` referenced nonexistent
  `SalesHistory_AFI_Enh.InvoiceDetail` and `InvoiceHeader` routes;
- `InventoryHistory_Enh_Wrk.v_AwdHelper` used incorrect identifier case
  `CurFcStSnapshotWeekly`;
- the canonical `DemandForecastSnapshotDaily` shortcut targeted the wrong
  upstream warehouse item.

After explicit approval, live DEV was corrected to:

- `SalesHistory_AFI.InvoiceDetail`;
- `SalesHistory_AFI.InvoiceHeader`;
- exact-case `CurFcstSnapshotWeekly`;
- approved `SupplyChain_Warehouse` shortcut target.

Post-fix results:

```text
Targeted live view compile:        30/30
Exact-case source contracts:       33/33
Shortcut target alignment:         33/33
Corrected live-to-EDW view parity:  3/3
```

### 8.2 Operating repository result

The operating repository received:

- the affected mart view copies;
- the affected SQLPROJ package view copies;
- exact compile-contract stubs for `SalesHistory_AFI.InvoiceDetail` and
  `InvoiceHeader`;
- exact-case `CurFcstSnapshotWeekly` reference contract;
- refreshed sanitized live lineage baseline and snapshot.

Verification:

- operating SQLPROJ build: `0` errors;
- lineage scanner tests: `30/30`;
- production safety gate: passed;
- mart projections, TypeScript, and Vite build: passed;
- commit: `cf886b9a71d023027b35efeb1a669dd8d4c4588f`;
- verified lineage workflow: `31142912804`, successful.

### 8.3 EDW repository result

The fresh EDW `main` already represented the corrected contracts through:

```text
$(Wholesale_Warehouse).SalesHistory_AFI
$(SupplyChain_Warehouse).SupplyChain_Enh
```

Therefore the normalized transformation logic had no new behavior delta.

The small follow-up PR records the latest alignment in three affected view
files without changing SQL behavior:

- commit: `2b6e2c1636e32a667aa14fd949352ebafe5660c3`;
- PR: `https://github.com/afi-internal/data-edw-fabric/pull/703`;
- local full build: `46` existing unrelated warnings, `0` errors;
- Supply Chain warnings introduced: `0`;
- GitHub `Build the database project`: `SUCCESS`;
- PR state at handoff: open, unmerged, waiting for review.

Historical responsibility remains clear:

- PR #678 contains the substantive 30-view / 33-contract Databricks-to-approved-
  warehouse redirect;
- PR #694 contains the subsequent live-code and DQ synchronization;
- PR #703 records the latest final live source/case alignment and is explicitly
  no-behavior-change.

## 9. Reviewer handoff template

```text
Live DEV scope checked:
- <objects>

Live changes applied:
- <exact changes, or "none">

Validation:
- view compile: <passed>/<total>
- exact-case contracts: <passed>/<total>
- shortcut alignment: <passed>/<total>
- normalized live-to-EDW parity: <passed>/<total>

Operating repo:
- changed paths: <paths>
- build/tests: <result>
- commit/push: <sha/status>
- lineage: <workflow/snapshot result>

EDW repo:
- baseline SHA: <sha>
- behavior delta: <yes/no and why>
- SQLCMD adaptation: <summary>
- local full build: <warnings/errors>
- commit: <sha>
- PR: <url>
- GitHub build: <result>

Boundary:
- PR is ready for review.
- PR author did not merge.
- Remaining owner action: <review/merge/deploy/none>.
```

## 10. Related detailed references

- `AGENTS.md`
- `CONTEXT.md`
- `01_docs/runbook/guides/supplychain_fabric_dev_to_pr_workflow.md`
- `03_operations/deployment/sqlproj/README.md`
- `05_tools/README.md`
- `05_tools/03_mart_sync/README.md`
- `05_tools/06_lineage_portal/README.md`
- `.github/workflows/lineage-portal.yml`
