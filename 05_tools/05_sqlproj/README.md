# SQLPROJ Tools

Tools for generating local, build-only Microsoft.Build.Sql packages from the current BOB-aligned Fabric runtime.

These tools are intentionally non-publishing:

- read live Fabric Warehouse metadata
- copy current repo SQL object definitions
- generate `.sqlproj` folders under `03_operations/deployment/sqlproj/`
- build/validate locally
- never deploy or publish to Fabric

## Usage

```bash
python3 05_tools/05_sqlproj/build_sqlproj_package.py
```

Then build manually:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

Latest verified build output:

- `03_operations/deployment/sqlproj/_package/build_summary.json`
- `03_operations/deployment/sqlproj/_package/build_logs/*.log`

Current result: all four generated projects build successfully with zero warnings and zero errors.

## Safety

`build_sqlproj_package.py` is read-only against Fabric SQL endpoints and only writes repo-local package files.
It does not call `SqlPackage /Action:Publish`, does not create CI/CD workflows, and does not mutate live warehouses.
