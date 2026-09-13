# Supply Chain Fabric DEV → Repository → Pull Request Workflow

## Purpose and author boundary

Use this runbook to synchronize approved changes from Fabric DEV into
`afi-internal/data-edw-fabric`.

The PR author is finished only when the intended commit has a correct scope,
passes the exact local solution build, and has a successful GitHub **Build the
database project** check. The reviewer/repository process owns approval, merge,
and release. Do not deploy, change Fabric DEV, or merge unless separately
assigned.

## Core rule

```text
Routine change only in SupplyChain_Processing_Warehouse and/or
SupplyChain_Gold_Warehouse
    → one Supply Chain PR to main.

Any new or changed external source contract
    → validate the approved target, live route, exact schema/table/column case,
      and reviewer-approved PR scope before editing.

Any remaining or new $(Databricks) dependency
    → stop. Do not add or modify Databricks objects. Obtain an approved
      non-Databricks mapping first.
```

The current approved source pattern is not a global string replacement. A
Supply Chain view may intentionally reference `Source_Data`,
`Wholesale_Warehouse`, `MasterData_Warehouse`, or `SupplyChain_Warehouse`.
Every reference must use the approved object and exact identifier case.

## 1. Start from a current baseline

```bash
git fetch origin --prune
git switch main
git pull --ff-only
git switch -c feature/<short-supplychain-change>
```

Read the repository `AGENTS.md` and `CONTEXT.md`. Confirm the exact Fabric DEV
workspace/item, the target repository project, and the scope owned by the
change before copying any definition.

If an existing main PR already represents the same work item, update that PR's
branch. Do not create a parallel PR unless the reviewer explicitly asks to
recreate it.

## 2. Compare and classify the DEV change

Compare the live Fabric DEV definition with the repository definition and
classify every changed object before staging.

| Object class | Default action |
|---|---|
| `SupplyChain_Processing_Warehouse/` object | Include in the Supply Chain PR. |
| `SupplyChain_Gold_Warehouse/` object | Include in the Supply Chain PR. |
| Existing external contract on `main` | Reference it with the approved SQLCMD variable; do not copy its object. |
| Missing external contract | Validate live metadata and request/obtain owner approval for its minimal DDL and PR scope. |
| `Databricks/` object or `$(Databricks)` reference | Exclude it; obtain an approved migration mapping. |
| Other business-domain object | Exclude it and coordinate with its owner. |
| Object absent from DEV | Investigate before proposing deletion; do not infer it is obsolete. |

## 3. External source-contract decision

For each external dependency, verify all of the following before coding:

1. approved target warehouse/database, schema, table, and exact case;
2. required columns and compatible business grain;
3. DEV runtime route/Fabric portal reference is available;
4. repository compile-time contract exists on `main`, or its minimal DDL is
   explicitly approved for this PR;
5. required `.sqlproj` project reference, SQLCMD variable, and publish-profile
   value are present.

For the approved Databricks migration pattern, the main Supply Chain PR may
contain the minimal missing external contract definitions together with the
redirected Supply Chain views **only when the reviewer explicitly approves
that one-PR scope**. Otherwise, stop for owner direction; never create a broad
copy of a source project.

## 4. Synchronize only approved definitions

Copy/export only the classified definitions into their matching paths. Preserve
the Enterprise ETL layout:

- final tables remain in final schemas;
- source/work logic remains in `_Wrk.v_<TableName>` views;
- project inclusions contain only files belonging to that project;
- do not add generated `bin/`, `obj/`, unrelated source schemas, or unrelated
  domain objects.

When an external contract is included by approval, add only its required
schema/table definition and the exact references needed to compile the
consuming project.

## 5. Verify the scope before staging

```bash
git status --short
git diff --check
git diff --name-only origin/main
```

For a routine Supply Chain-only change, the changed-file list must contain only:

```text
SupplyChain_Processing_Warehouse/
SupplyChain_Gold_Warehouse/
```

An approved external-contract change may additionally contain only the named
minimal contract files, required `.sqlproj`/publish-profile updates, and the
solution file if project inclusion changes. Any `Databricks/`, unrelated
warehouse, generated, or unexplained file is a stop condition.

For a migration away from Databricks, scan the candidate diff and require zero
remaining Supply Chain `$(Databricks)` references.

## 6. Build locally before committing

Use the SDK pinned by `global.json`. Restore only when required:

```bash
dotnet restore EDW-Fabric.sln
dotnet build EDW-Fabric.sln --configuration Release /p:NetCoreBuild=true --no-restore
```

Required result: `0 Error(s)`.

Review warnings. Correct a warning introduced by the change, or obtain explicit
owner acceptance. A local build failure means no commit and no PR.

## 7. Commit and push only the reviewed scope

Stage explicit paths, never `git add .`:

```bash
git add SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
git diff --cached --check
git diff --cached --name-only
git commit -m "Sync Supply Chain DEV Fabric definitions"
git push -u origin feature/<short-supplychain-change>
```

When approved external contracts are part of the change, add their explicit
paths in the same command and re-check the staged file list.

## 8. Create or update one PR

Create (or update) one PR against `main` with:

- an accurate scope and source-mapping summary;
- the exact local build command and result;
- any approved external contract files clearly named;
- a statement that no `Databricks/` objects are included.

Do not create a separate prerequisite/parallel PR unless the reviewer asks for
one. If a reviewer asks to keep one main PR, update that existing PR instead.

## 9. Confirm GitHub CI after push

The latest PR head SHA is review-ready only when all are true:

1. **Build the database project** is **Success** for that SHA;
2. the changed-files tab still matches the approved scope;
3. no required reviewer feedback remains unaddressed.

If CI fails, reproduce its first actual build error using the exact command,
correct only approved in-scope files, push the correction, and repeat this
step.

## Completion checklist

- [ ] Live DEV definition and ownership classified.
- [ ] External dependencies, if any, have approved mapping, contract, route,
  grain, and exact case.
- [ ] No unapproved `Databricks/` object or `$(Databricks)` dependency remains.
- [ ] `git diff --check` passes.
- [ ] Local full solution build has `0 Error(s)` before commit.
- [ ] One PR is open against `main`; no redundant parallel/prerequisite PR is
  open for the same work.
- [ ] GitHub **Build the database project** is successful for the latest SHA.
- [ ] Reviewer receives the PR link and accurate validation summary.

Stop after the PR is review-ready. Do not merge, deploy, or mutate Fabric
 without separate authorization.
