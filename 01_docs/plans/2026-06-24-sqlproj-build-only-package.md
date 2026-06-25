# SQLPROJ Build-Only Package Implementation Plan

**Goal:** Package the current Enterprise ETL-aligned SupplyChain runtime into local `.sqlproj` projects for build validation and US/Enterprise ETL CI-CD handoff, without publishing to Fabric.

**Scope Lock:** Repo/local files only. Read-only live metadata queries are allowed. No `SqlPackage /Action:Publish`, no CI/CD workflow, no live Fabric mutation, no destructive cleanup.

## Implementation Steps

1. Generate table DDL from live Fabric Warehouse metadata for active final tables.
2. Copy active repo `_Wrk` view SQL and wrapper procedure SQL into SQL project folder structure.
3. Export live `ETL_Framework` framework tables/modules into a local SQL project.
4. Create SDK-style `.sqlproj` files with Fabric Data Warehouse target platform.
5. Add package README/runbook and root docs links.
6. Run local generator, then attempt `dotnet build` for each generated project.
7. Record any build blockers as package validation evidence instead of claiming false success.

## Completion Status

[Verified] Implemented on 2026-06-24 as build-only package under `03_operations/deployment/sqlproj/`.

| Project | Result | Warnings | Errors |
|---|---:|---:|---:|
| `ETL_Framework` | pass | 0 | 0 |
| `Enterprise_Lakehouse_Reference` | pass | 0 | 0 |
| `SupplyChain_Processing_Warehouse` | pass | 0 | 0 |
| `SupplyChain_Gold_Warehouse` | pass | 0 | 0 |

The package is safe for local build validation and handoff. It is not configured to publish to Fabric.

## Expected Output

```text
03_operations/deployment/sqlproj/
├── README.md
├── build_all.sh
├── package_summary.json
├── ETL_Framework/
├── Enterprise_Lakehouse_Reference/
├── SupplyChain_Processing_Warehouse/
└── SupplyChain_Gold_Warehouse/
```

## Validation

```bash
python3 05_tools/05_sqlproj/build_sqlproj_package.py
cd 03_operations/deployment/sqlproj
./build_all.sh
```
