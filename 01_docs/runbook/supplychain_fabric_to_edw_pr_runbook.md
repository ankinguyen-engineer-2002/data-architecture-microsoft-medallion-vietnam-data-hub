# SupplyChain Fabric to EDW PR Runbook

Purpose: package the repeatable process for moving Supply Chain warehouse database-object changes from Fabric DEV into the correct GitHub PR flow.

This document lives in the architecture repo, but most commands execute in the database objects repo:

```text
Architecture/runbook repo:
  /Users/MAC/Documents/20260413_Fabric_Refactor_Architect

Fabric workspace repo (`data-fabric-enterprise-supply-chain`):
  /Users/MAC/Documents/Ashley-Git-Data-Fabric/data-fabric-enterprise-supply-chain
  https://github.com/afi-internal/data-fabric-enterprise-supply-chain

Database object repo (`data-edw-fabric`):
  /Users/MAC/Documents/Ashley-Git-Data-Fabric/data-edw-fabric
  https://github.com/afi-internal/data-edw-fabric
```

## Routing Rule

Use database object repo (`data-edw-fabric`) for database objects:

- schemas
- tables
- views
- stored procedures
- functions
- SQL project configuration needed to build/deploy those objects
- external source stubs needed by SQL project references

Use Fabric workspace repo (`data-fabric-enterprise-supply-chain`) for Fabric item/workspace artifacts:

- notebook items
- pipeline items
- lakehouse/warehouse item metadata
- semantic models
- Power BI reports
- workspace folder/item organization
- Fabric Git item definitions that are not database object source code

Short rule:

```text
SQL/database object logic -> database object repo (`data-edw-fabric`)
Fabric item/artifact/orchestration metadata -> Fabric workspace repo (`data-fabric-enterprise-supply-chain`)
```

## Golden Safety Rules

1. Do not PR unrelated domain objects.
2. Do not include generated `bin/` or `obj/` files.
3. Do not commit from `main`; create a feature branch from current `origin/main`.
4. Do not add external source definitions blindly. Add only what SQL project build needs.
5. Treat `Databricks` in `data-edw-fabric` as an external database reference project, not as actual Azure Databricks work.
6. Build locally before push/PR.
7. Use `git diff --check` before commit to catch whitespace/line-ending noise.
8. If a branch is already attached to a closed PR, create a new branch name instead of reusing it.

## Current SupplyChain Example

The July 2026 handoff used:

```text
Branch:
  feature/supplychain-processing-gold-warehouse-objects

Commit:
  9dc71001 Add Supply Chain processing and gold warehouse objects

PR direction:
  feature/supplychain-processing-gold-warehouse-objects -> main
```

The commit touched these groups:

```text
SupplyChain_Processing_Warehouse/   database objects and sqlproj
SupplyChain_Gold_Warehouse/         database objects and sqlproj
Databricks/                         external source definitions for SQL build
EDW-Fabric.sln                      solution registration for new SQL projects
```

## End-to-End Process

### 1. Start from a fresh `data-edw-fabric` branch

```bash
cd /Users/MAC/Documents/Ashley-Git-Data-Fabric/data-edw-fabric
git fetch origin --prune
git switch main
git pull --ff-only origin main
git switch -c feature/<short-supplychain-change-name>
```

Use a branch name that is specific enough to avoid stale closed PRs:

```text
feature/supplychain-processing-gold-warehouse-objects
feature/supplychain-forecast-warehouse-objects
feature/supplychain-inventory-health-sql-objects
```

### 2. Bring in only database objects

Copy or generate only SQL database-object files into the correct `data-edw-fabric` SQL project:

```text
SupplyChain_Processing_Warehouse/
SupplyChain_Gold_Warehouse/
ETL_Framework/              only if the change is really ETL framework DB object code
Databricks/                 only external source definitions needed for build
```

Do not copy Fabric item metadata into `data-edw-fabric`:

```text
.platform
xmla.json
notebook item metadata
pipeline item metadata
semantic model/report files
```

### 3. Add or update `.sqlproj` and solution wiring

If adding a new SQL project, follow existing domain patterns in `data-edw-fabric`:

- SDK-style SQL project
- `Microsoft.Build.Sql`
- Fabric DW target platform:

```xml
<DSP>Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider</DSP>
```

- SQLCMD variables for external database references
- `ProjectReference` entries where one SQL project depends on another
- publish profiles following existing Dev/Prod profile style
- `EDW-Fabric.sln` updated to include the project

Validate the solution recognizes the project:

```bash
git diff -- EDW-Fabric.sln
```

### 4. Scan external source references

From `data-edw-fabric`, scan the new/changed warehouse projects:

```bash
cd /Users/MAC/Documents/Ashley-Git-Data-Fabric/data-edw-fabric

rg -n "\[\$\(Databricks\)\]|Enterprise_Lakehouse|SupplyChain_Enh|Wholesale_Codis|MasterData|SalesHistory|ItemMaster" \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
```

For each external source reference, confirm a matching stub exists under `Databricks/`.

Example:

```sql
FROM [$(Databricks)].[SupplyChain_Enh].[DemandInventorySnapshotDaily]
```

requires definitions like:

```text
Databricks/SupplyChain_Enh/SupplyChain_Enh.sql
Databricks/SupplyChain_Enh/Tables/DemandInventorySnapshotDaily.sql
```

Important: in `data-edw-fabric`, `Databricks` is the existing external-reference project name. Publish profiles map it to `Enterprise_Lakehouse`.

```text
$(Databricks) -> Enterprise_Lakehouse
```

This does not mean the SupplyChain workspace uses Azure Databricks.

### 5. Normalize cross-database references

Prefer SQLCMD variables instead of hard-coded database names:

```sql
-- Preferred for external lakehouse/source objects
[$(Databricks)].SchemaName.TableName

-- Preferred for ETL framework references
[$(ETL_Framework)].SchemaName.ObjectName

-- Preferred for cross-project warehouse references
[$(SupplyChain_Processing_Warehouse)].SchemaName.ObjectName
```

Avoid this in `data-edw-fabric` SQL project source unless there is a verified local pattern requiring it:

```sql
[Enterprise_Lakehouse].SchemaName.TableName
[ETL_Framework].SchemaName.ObjectName
SupplyChain_Processing_Warehouse.SchemaName.ObjectName
```

Self-references inside the same SQL project should usually be two-part names:

```sql
SchemaName.ObjectName
```

### 6. Remove known out-of-scope artifacts

Before build, check for old architecture or backup artifacts:

```bash
rg -n "\bMeta\b|BACKUP_|semantic_recovery" \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse || true
```

If `Meta` belongs to old architecture and is not in scope, do not include it.

If backup/recovery tables were temporary live repair objects, do not include them.

### 7. Build locally

`data-edw-fabric` has a pinned SDK in `global.json`. If local `dotnet` is not the expected SDK, use the local install path:

```bash
cd /Users/MAC/Documents/Ashley-Git-Data-Fabric/data-edw-fabric

DOTNET_ROOT="$HOME/.dotnet" PATH="$HOME/.dotnet:$PATH" \
  dotnet restore EDW-Fabric.sln

DOTNET_ROOT="$HOME/.dotnet" PATH="$HOME/.dotnet:$PATH" \
  dotnet build EDW-Fabric.sln --configuration Release /p:NetCoreBuild=true --no-restore
```

Expected acceptance:

```text
Build succeeded.
0 Error(s)
```

Warnings such as `SQL71558` casing differences may remain if they match existing source casing drift. Document them in the PR if they are present.

### 8. Clean generated files

The build may generate `bin/` and `obj/`. Do not commit them.

```bash
git status --short -uall | rg '/(bin|obj)/' || true
```

If generated files appear under new project folders:

```bash
rm -rf SupplyChain_Processing_Warehouse/bin SupplyChain_Processing_Warehouse/obj
rm -rf SupplyChain_Gold_Warehouse/bin SupplyChain_Gold_Warehouse/obj
```

Then verify again:

```bash
git status --short -uall | rg '/(bin|obj)/' || true
```

### 9. Run final diff checks

```bash
git diff --check origin/main...HEAD
git status --short --branch
git diff --name-only origin/main...HEAD | awk -F/ '{print $1}' | sort | uniq -c
```

Expected changed top-level groups for SupplyChain Processing/Gold warehouse object work:

```text
Databricks                      only if external source stubs are needed
EDW-Fabric.sln                  if adding/updating SQL projects
SupplyChain_Processing_Warehouse
SupplyChain_Gold_Warehouse
```

If unrelated projects appear, investigate before commit.

### 10. Commit and push

```bash
git add EDW-Fabric.sln Databricks SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
git status --short --branch
git commit -m "Add Supply Chain processing and gold warehouse objects"
git push -u origin HEAD
```

If amending a branch already pushed but not yet reviewed:

```bash
git add -u
git commit --amend --no-edit
git push --force-with-lease
```

Use `--force-with-lease`, not plain `--force`.

### 11. Create PR

PR direction:

```text
base:    main
compare: feature/<branch-name>
```

PR description template:

```text
This PR adds/updates Supply Chain database objects in data-edw-fabric.

Changes include:
- Added/updated SupplyChain_Processing_Warehouse SQL objects
- Added/updated SupplyChain_Gold_Warehouse SQL objects
- Added required external source definitions under Databricks for SQL project compilation
- Updated SQL project configuration / publish profiles / EDW-Fabric.sln where required

Validation:
- dotnet restore EDW-Fabric.sln
- dotnet build EDW-Fabric.sln --configuration Release /p:NetCoreBuild=true --no-restore
- Build succeeded with 0 errors
- git diff --check passed
```

After opening the PR, check:

```text
base is main
compare is the feature branch
Files changed are in expected folders only
CI/checks pass or have clear warning-only status
```

## Live Fabric to `data-edw-fabric` Sync Checklist

Use this checklist whenever a Fabric DEV warehouse object changed intentionally:

```text
[ ] Identify changed database object(s) in Fabric DEV.
[ ] Confirm object type is `data-edw-fabric` scope.
[ ] Export/copy SQL definition into the matching `data-edw-fabric` SQL project.
[ ] Scan external references from the changed SQL.
[ ] Add/update Databricks source stubs only for referenced external objects.
[ ] Normalize cross-database references to SQLCMD variables.
[ ] Remove old Meta/backup/recovery objects if out of scope.
[ ] Build EDW-Fabric.sln locally.
[ ] Remove bin/obj generated files.
[ ] Run git diff --check.
[ ] Review changed top-level folders.
[ ] Commit on feature branch.
[ ] Push and create PR to main.
```

## Quick Commands For Investigation

Changed files by top-level folder:

```bash
git diff --name-only origin/main...HEAD | awk -F/ '{print $1}' | sort | uniq -c
```

External references:

```bash
rg -n "\[\$\(Databricks\)\]|\[\$\(ETL_Framework\)\]|\[\$\(SupplyChain_Processing_Warehouse\)\]" \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
```

Hard-coded database references to clean up:

```bash
rg -n "\[(Enterprise_Lakehouse|ETL_Framework|SupplyChain_Processing_Warehouse|SupplyChain_Gold_Warehouse)\]|Enterprise_Lakehouse\.|SupplyChain_Processing_Warehouse\.|SupplyChain_Gold_Warehouse\." \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
```

Out-of-scope object scan:

```bash
rg -n "\bMeta\b|BACKUP_|semantic_recovery" \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse || true
```

Check whether a staging object is actually consumed downstream:

```bash
rg -n "ObjectNameWithoutSchema|SchemaName.ObjectName|SchemaName\\].\\[ObjectName" \
  SupplyChain_Processing_Warehouse SupplyChain_Gold_Warehouse
```

Remote PR/branch sanity:

```bash
gh pr list --state all --head "$(git branch --show-current)" --json number,title,state,url,isDraft
git rev-parse HEAD
git rev-parse "origin/$(git branch --show-current)"
git rev-parse origin/main
```

## Reviewer Questions To Be Ready For

If reviewer asks why `Databricks/` changed:

```text
Those files are external source definitions required by the SQL project build.
In this repo, Databricks is the existing external-reference project name and is mapped by publish profiles to Enterprise_Lakehouse. It is not Azure Databricks runtime work.
```

If reviewer asks why `EDW-Fabric.sln` changed:

```text
The solution file was updated to include the new/updated SupplyChain SQL projects so CI/build can validate them.
```

If reviewer asks whether object changes are Supply Chain only:

```text
The database objects are under SupplyChain_Processing_Warehouse and SupplyChain_Gold_Warehouse. Additional Databricks files are build-time external source stubs for objects referenced by those SupplyChain SQL objects.
```

If reviewer asks about warnings:

```text
The build succeeds with 0 errors. Remaining SQL71558 warnings are casing differences between external source references and stub definitions; they do not block the SQL project build.
```

