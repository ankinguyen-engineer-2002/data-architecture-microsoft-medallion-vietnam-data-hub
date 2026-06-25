# SQLPROJ And CI/CD Research For BOB-Aligned Fabric Warehouses

## Scope

This note captures Bob's `.sqlproj` guidance, the likely CI/CD model for the SupplyChain operating repo, and the repo-local build-only implementation now available for US/BOB handoff.

It is **not** a publish workflow. Publishing `.dacpac` files can alter live Fabric Warehouse objects, so this repo intentionally stops at local build validation unless US/BOB explicitly approves deployment ownership, publish profiles, service connection, and destructive-change gates.

## Sources Reviewed

| Source | Type | Finding |
|---|---|---|
| `01_docs/bob-framework/source/SQLPROJ_BEST_PRACTICES.md` | Bob guide | Defines Fabric Warehouse `.sqlproj` conventions: `SqlDwUnifiedDatabaseSchemaProvider`, `ModelCollation=1033, CI`, `SqlCmdVariable`, `ProjectReference`, `BeforeBuild`, package refs, validation checklist. |
| `01_docs/bob-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md` | Bob guide | Describes project structure, Dev/Prod publish profiles, Azure Pipelines path, build/deploy/test/approval flow, and PR checklist. |
| `99_archive/reverse-engineering/enterprise_data_architect/30_runbook/02_domain_team_workflow.md` | Reverse-engineered EnterpriseData observation | Observed value-stream workflow: write `_Wrk` view, register `TableDictionary`, add wrapper `EXEC`, PR review by senior reviewer, merge, then Fabric Git sync auto-deploy. |
| Microsoft Learn: Develop warehouse projects in VS Code | Official docs | Fabric Warehouse supports SDK-style SQL Database Projects; build produces `.dacpac`; publish can generate script or apply to warehouse; docs warn to review script/settings first. |
| Microsoft Learn: SQL projects automation | Official docs | CI/CD pattern is build `.sqlproj` to `.dacpac`, publish artifact, then deploy with `SqlPackage`, GitHub `azure/sql-action`, or Azure DevOps `SqlAzureDacpacDeployment`. |
| Microsoft Learn: Target platform overview | Official docs | Fabric Data Warehouse target platform is `Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider`; target platform mismatch blocks publish unless explicitly overridden. |

## Current Finding

[Verified] Bob's intended operating model is code-first warehouse development:

```text
Feature branch
  -> SQL object files in .sqlproj
  -> build validation
  -> PR review
  -> merge
  -> CI/CD / Fabric Git sync deployment
  -> wrapper proc runtime refresh
  -> ETL_Framework AuditLog + TableDictionary evidence
```

[Verified] `.sqlproj` owns schema/object deployment, not daily data refresh. Daily refresh remains SQL Agent or another scheduler calling wrapper procedures.

[Verified] BOB runtime and SQL project deployment are complementary:

| Concern | Owner |
|---|---|
| Object definitions: schemas, tables, views, stored procedures, functions | `.sqlproj` / Git / CI-CD |
| Load execution: view-to-table refresh, incremental load, audit, metadata | `ETL_Framework` stored procedures |
| Schedule trigger | SQL Server Agent / enterprise scheduler |
| Runtime evidence | `AuditLog`, `TableDictionary`, `TableDictionary_UpdateLog`, query history |

## Repo Implementation Status

[Verified] Option B has been implemented as a local build-only package:

```text
03_operations/deployment/sqlproj/
  ETL_Framework/
  Enterprise_Lakehouse_Reference/
  SupplyChain_Processing_Warehouse/
  SupplyChain_Gold_Warehouse/
```

Build command:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

Latest verified build:

| Project | Result | Warnings | Errors |
|---|---:|---:|---:|
| `ETL_Framework` | pass | 0 | 0 |
| `Enterprise_Lakehouse_Reference` | pass | 0 | 0 |
| `SupplyChain_Processing_Warehouse` | pass | 0 | 0 |
| `SupplyChain_Gold_Warehouse` | pass | 0 | 0 |

Implementation notes:

- `Enterprise_Lakehouse_Reference` is a build-time stub project for active Bronze source tables used by Silver/Gold views.
- Processing and Gold projects use `ProjectReference` with `DatabaseVariableLiteralValue` for hard-coded three-part database names.
- Self-database references are normalized in the generated package so same-project objects compile as two-part references.
- `dbo` schema files are no-op markers because DacFx already includes `dbo`.

For DA/DE-facing definitions, examples, and step-by-step operating flow, see:

```text
01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md
```

## Version Drift Resolved For Local Build

[Verified] Bob guide says `Microsoft.Build.Sql` version `0.1.12-preview`, but current package validation uses newer SDK packages:

```xml
<Sdk Name="Microsoft.Build.Sql" Version="2.2.0" />
<PackageReference Include="Microsoft.SqlServer.Dacpacs.FabricDw" Version="170.0.4" />
```

This is documentation/version drift, not an architecture conflict. The local package builds successfully with the newer versions. US/BOB should still confirm the package versions used in the official EnterpriseData CI/CD repo before accepting this package as deployment source.

## Recommended Repo Adoption Model

### Option A — Documentation-only handoff for US-owned CI/CD

Keep this repo as architecture + operation handoff. Document how SupplyChain should be represented in Bob/US `.sqlproj`, but let US own the deploy repo and Azure DevOps pipeline.

Pros:
- Lowest risk.
- Matches current reality: US owns scheduler and enterprise CI/CD.
- Avoids accidental live DacFx publish from this repo.

Cons:
- Local repo is not the deployable source of truth.
- Drift can occur unless US exports/syncs definitions back.

### Option B — Add local `.sqlproj` source packages, no deploy workflow

Create local SQL project folders for:

- `ETL_Framework`
- `SupplyChain_Processing_Warehouse`
- `SupplyChain_Gold_Warehouse`

Use them for build validation and diff review only. No automated publish.

Pros:
- Gives local build/compile guard.
- Easier PR-style review of schema/view/proc changes.
- Can generate `.dacpac`, deploy report, or script for US review.

Cons:
- More maintenance.
- Cross-database references and Fabric-specific package versions must be tested carefully.
- Still not official CI/CD unless US accepts the package.

### Option C — Full CI/CD from this repo

Add GitHub Actions or Azure DevOps pipeline to build `.sqlproj`, publish `.dacpac`, and deploy to Fabric Warehouse.

Pros:
- Strongest automation if repo becomes official deployment source.
- Repeatable build artifact and release gates.

Cons:
- Highest blast radius.
- Requires secrets/service connection, branch policy, approvals, target environment mapping, and destructive-change controls.
- Should not be enabled until ownership with US/BOB is explicit.

## Recommendation For This Repo

[Verified] Use **Option B** as the current repo model:

1. Generate local `.sqlproj` projects from current live/local SQL definitions.
2. Build locally only.
3. Do not publish from automation.
4. Hand over generated artifacts and this guide to US/BOB for official CI/CD alignment.

This keeps the repo useful for review and drift detection while respecting that SQL Agent + enterprise CI/CD ownership sits with the US team.

## Minimum CI/CD Gates If Implemented

| Gate | Requirement |
|---|---|
| Build | `dotnet build` succeeds for each `.sqlproj`. |
| Target platform | `DSP=Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider`. |
| Package version | Fabric DW package version verified against current Microsoft docs or EnterpriseData repo. |
| Cross-db refs | All external database references use `SqlCmdVariable`/`ProjectReference`; no hard-coded deploy env names unless intentionally external. |
| DacFx review | `Script` or `DeployReport` generated before publish. |
| Data-loss guard | `BlockOnPossibleDataLoss=True`; `DropObjectsNotInSource=False` unless explicitly approved. |
| Runtime smoke | Run wrapper proc smoke or compile check after deploy. |
| Evidence | Verify `AuditLog`, `TableDictionary`, and query history after runtime refresh. |

## Open Questions

1. Is `Enterprise Data Services/Fabric-EnterpriseData` the official Azure DevOps repo for SupplyChain SQL projects?
2. Does US want SupplyChain code moved into their repo, or does this repo remain a documentation/operations mirror?
3. Which package versions are currently used in EnterpriseData live `.sqlproj` files?
4. Are Fabric Git sync deployments the official route, or is Azure Pipelines/DacFx publish the route?
5. Who owns approval for publish profiles and service connections?

## Official References

- Microsoft Learn — Develop warehouse projects in Visual Studio Code: <https://learn.microsoft.com/fabric/data-warehouse/develop-warehouse-project>
- Microsoft Learn — SQL projects automation: <https://learn.microsoft.com/sql/tools/sql-database-projects/sql-projects-automation?view=sql-server-ver17>
- Microsoft Learn — Target platform overview: <https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/target-platform?view=sql-server-ver17>
