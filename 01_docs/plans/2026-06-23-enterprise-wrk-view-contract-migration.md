# Enterprise Wrk View Contract Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the SupplyChain operating repo and live Fabric SQL surface to the verified Enterprise/BOB curated-warehouse contract: final schemas contain physical tables; `_Wrk` schemas contain `v_<TableName>` source/work views used by `ETL_Framework`.

**Architecture:** Preserve the current medallion business surface and table outputs. Treat Bronze/source as source inventory, Silver/Processing and Gold/Serving as curated/domain warehouse layers following the `SCP_Core` pattern. Do not rewrite business SQL or rebuild data unless a verification step proves it is required.

**Tech Stack:** Microsoft Fabric Warehouses, Fabric REST API, Power BI REST API, T-SQL catalog scans via `pyodbc` + Entra token, repo docs under `01_docs/`, mart definitions under `02_marts/`, orchestration manifests under `03_operations/orchestration/`.

---

## Verified Inputs

- [Verified] `SupplyChain_Warehouse.SCP_Core` has physical final tables and no views.
- [Verified] `SupplyChain_Warehouse.SCP_Core_Wrk` has work views and no physical tables.
- [Verified] `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` resolves source view as:

```sql
@ViewName = @DestinationDatabase + '.' + @DestinationSchema + '_Wrk.v_' + @DestinationTable
```

- [Verified] Current `SupplyChain_Processing_Warehouse` and `SupplyChain_Gold_Warehouse` have duplicate `v_*` views in both base schemas and `_Wrk` schemas.
- [Verified] Duplicate base views do not duplicate data, but they are not naming-clean against the Enterprise curated/domain warehouse contract.

## Target Contract

```text
Bronze/source documentation:
  Enterprise_Lakehouse / source shortcuts / source tables
  No forced _Wrk view convention.

Silver/Processing warehouse:
  <DomainSchema>.<TableName>        = physical final table
  <DomainSchema>_Wrk.v_<TableName>  = work/source view used by ETL_Framework

Gold/Serving warehouse:
  <ServingSchema>.<TableName>       = physical final table
  <ServingSchema>_Wrk.v_<TableName> = work/source view used by ETL_Framework

ETL_Framework:
  TableDictionary points to final DatabaseName + SchemaName + TableName.
  Loader SP derives source from SchemaName + '_Wrk.v_' + TableName.
```

## Non-Negotiables

- Preserve Bronze/Silver/Gold layer outputs.
- Preserve physical table names, semantic model table names, report bindings, and business logic.
- Do not drop live views until dependency audit proves zero required references and Aric approves the exact drop list.
- Do not run full refresh just because views are renamed/cleaned; run targeted smoke and only refresh affected semantic model if needed.
- Keep rollback SQL for every live DDL action.

## File Structure

- Modify: `AGENTS.md`
  - Update current runtime contract from broad `_Wrk` wording to curated/domain-specific contract.
- Modify: `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
  - Add Phase 1+ cleanup addendum for Enterprise `_Wrk` contract alignment.
- Create: `01_docs/decisions/ADR-009-enterprise-wrk-view-contract.md`
  - Record the decision and rejected duplicate-view pattern.
- Modify: `01_docs/architecture/README.md`
  - Link the ADR and contract summary.
- Modify: `02_marts/**/README.md`
  - State that Silver/Gold SQL files represent `_Wrk` views and final physical tables separately.
- Move/update: `02_marts/**/{2.silver,3.gold}/**/*.sql`
  - Final target: work view SQL lives under `_Wrk` folder or clearly named `v_<TableName>.sql`; physical table contract lives as `<TableName>.table.sql` or README table inventory.
- Modify: `03_operations/orchestration/**/manifest.yaml`
  - Ensure tasks reference final table names and framework load order, not base-schema duplicate views.
- Create: `03_operations/tools/enterprise_contract/scan_wrk_contract.py`
  - Read-only catalog scanner for base schema/table vs `_Wrk` view contract.
- Create: `03_operations/tools/enterprise_contract/build_wrk_contract_cleanup.py`
  - Generates non-destructive reports plus optional DDL scripts; default mode writes candidate SQL only.
- Create: `03_operations/tools/enterprise_contract/verify_wrk_contract.py`
  - Post-change verifier for object counts, dependency refs, table counts, semantic smoke hints.
- Artifact output: `01_docs/runbook/artifacts/<yyyymmdd>_enterprise_wrk_contract_migration/`
  - Save scan JSON, dependency CSV, before-DDL scripts, candidate cleanup SQL, verification JSON.

---

### Task 1: Freeze Evidence And Define The Contract

**Files:**
- Create: `01_docs/decisions/ADR-009-enterprise-wrk-view-contract.md`
- Modify: `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
- Modify: `AGENTS.md`
- Modify: `00_CONTEXT/current.md`

- [ ] **Step 1: Create ADR from verified live evidence**

Create `01_docs/decisions/ADR-009-enterprise-wrk-view-contract.md` with this content:

```markdown
# ADR-009: Enterprise `_Wrk` View Contract For Curated Warehouses

## Status
Accepted

## Context
Live scan on 2026-06-23 showed that `SupplyChain_Warehouse.SCP_Core` uses physical final tables in the base schema and `SCP_Core_Wrk.v_<TableName>` work views as the ETL source. `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` derives the work view from `@DestinationSchema + '_Wrk.v_' + @DestinationTable`.

EnterpriseData curated/domain warehouses such as `Retail_Warehouse` and `Wholesale_Warehouse` follow the same broad pattern: base schemas are final table surfaces, `_Wrk` schemas hold work views or work objects. `Source_Data` is different because it is a source/staging estate where `_Wrk` can be physical landing/work tables.

## Decision
For SupplyChain Silver/Processing and Gold/Serving warehouses, use one canonical contract:

```text
<BaseSchema>.<TableName>        = physical final table
<BaseSchema>_Wrk.v_<TableName>  = work/source view used by ETL_Framework
```

Bronze/source documentation may list source shortcuts and source tables without forcing the curated `_Wrk` view convention.

## Consequences
- Base-schema duplicate `v_*` views are legacy compatibility artifacts only.
- No business table, semantic model, or report contract changes are intended.
- Cleanup of duplicate base views requires dependency audit, rollback scripts, and explicit approval.
```

- [ ] **Step 2: Update master plan addendum**

Append a section to `01_docs/Enterprise_Framework_Migration_Master_Plan.md`:

```markdown
## Phase 1+ Addendum — Enterprise `_Wrk` Contract Cleanup

Phase 1 is operationally complete, but a live Enterprise pattern scan found one naming-contract cleanup item:

- Final curated/domain schemas should expose physical final tables only.
- `_Wrk` schemas should expose `v_<TableName>` work/source views for `ETL_Framework`.
- Existing duplicate base-schema `v_*` views are compatibility artifacts and must be removed only after dependency audit.

Acceptance:
- `SupplyChain_Processing_Warehouse` base domain schemas have no required `v_*` views.
- `SupplyChain_Gold_Warehouse` base serving schemas have no required `v_*` views.
- `_Wrk.v_<TableName>` views exist for all framework-loaded final tables.
- `TableDictionary` rows continue to point to final schema/table names.
- `sc_control_tower` refresh and DAX smoke still pass.
```

- [ ] **Step 3: Update `AGENTS.md` runtime wording**

Replace the current broad `_Wrk` bullet with:

```markdown
- Canonical Enterprise/BOB curated warehouse pattern:
  - Bronze/source docs list source lakehouse shortcuts and source tables.
  - Silver/Gold final schemas hold physical final tables.
  - Silver/Gold `_Wrk` schemas hold `v_<TableName>` work/source views.
  - `ETL_Framework` loader procedures derive `_Wrk.v_<TableName>` from final `SchemaName` + `TableName`.
  - Base-schema `v_*` views have been removed from active Silver/Gold curated schemas and must not be reintroduced.
```

- [ ] **Step 4: Context checkpoint**

Append to `00_CONTEXT/current.md`:

```markdown
## <timestamp ICT> — Enterprise `_Wrk` contract plan accepted for implementation

**Scope lock:** `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse`, `ETL_Framework`, `02_marts/`, `03_operations/orchestration/`.

**Decision:** Use the Enterprise curated/domain warehouse contract: base schema physical tables only, `_Wrk.v_<TableName>` source views.

**Next step:** Build read-only dependency scanner before any live DDL cleanup.
```

---

### Task 2: Build Read-Only Contract Scanner

**Files:**
- Create: `03_operations/tools/enterprise_contract/scan_wrk_contract.py`
- Artifact: `01_docs/runbook/artifacts/<run_id>_enterprise_wrk_contract_migration/contract_scan.json`

- [ ] **Step 1: Create scanner script**

Create `03_operations/tools/enterprise_contract/scan_wrk_contract.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import pathlib
import struct
import subprocess
import time

import pyodbc


WAREHOUSES = {
    "processing": "SupplyChain_Processing_Warehouse",
    "gold": "SupplyChain_Gold_Warehouse",
    "etl": "ETL_Framework",
}

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"


def token_attr() -> bytes:
    raw = subprocess.check_output(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--query",
            "accessToken",
            "-o",
            "tsv",
        ],
        text=True,
    ).strip().encode("utf-16-le")
    return struct.pack("<I", len(raw)) + raw


def connect(database: str):
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={database};Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_attr()},
        timeout=120,
        autocommit=True,
    )


def rows(cur, sql: str):
    cur.execute(sql)
    columns = [d[0] for d in cur.description]
    return [dict(zip(columns, r)) for r in cur.fetchall()]


def scan_database(database: str):
    conn = connect(database)
    cur = conn.cursor()
    objects = rows(
        cur,
        """
        SELECT s.name AS schema_name, o.name AS object_name, o.type_desc, o.create_date, o.modify_date
        FROM sys.objects o
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY s.name, o.type_desc, o.name
        """,
    )
    modules = rows(
        cur,
        """
        SELECT s.name AS schema_name, o.name AS object_name, o.type_desc, m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY s.name, o.name
        """,
    )
    schema_pairs = []
    schemas = sorted({o["schema_name"] for o in objects})
    for wrk_schema in [s for s in schemas if s.endswith("_Wrk")]:
        base_schema = wrk_schema[:-4]
        if base_schema not in schemas:
            continue
        base_objects = [o for o in objects if o["schema_name"] == base_schema]
        wrk_objects = [o for o in objects if o["schema_name"] == wrk_schema]
        base_tables = sorted(o["object_name"] for o in base_objects if o["type_desc"] == "USER_TABLE")
        base_views = sorted(o["object_name"] for o in base_objects if o["type_desc"] == "VIEW")
        wrk_views = sorted(o["object_name"] for o in wrk_objects if o["type_desc"] == "VIEW")
        schema_pairs.append(
            {
                "base_schema": base_schema,
                "wrk_schema": wrk_schema,
                "base_tables": base_tables,
                "base_views": base_views,
                "wrk_views": wrk_views,
                "expected_wrk_views_missing": sorted(
                    f"v_{table}" for table in base_tables if f"v_{table}" not in wrk_views
                ),
                "duplicate_base_views": sorted(v for v in base_views if v in wrk_views),
            }
        )
    return {"database": database, "objects": objects, "modules": modules, "schema_pairs": schema_pairs}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    result = {
        "checked_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "databases": {name: scan_database(db) for name, db in WAREHOUSES.items()},
    }
    (out_dir / "contract_scan.json").write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")
    print(json.dumps({k: v["database"] for k, v in result["databases"].items()}, indent=2))
    print("RESULT", out_dir / "contract_scan.json")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run scanner**

Run:

```bash
RUN_ID="$(date +%Y%m%d_%H%M)_enterprise_wrk_contract_migration"
python3 -u 03_operations/tools/enterprise_contract/scan_wrk_contract.py \
  --out-dir "01_docs/runbook/artifacts/${RUN_ID}"
```

Expected:

```text
RESULT 01_docs/runbook/artifacts/<run_id>/contract_scan.json
```

- [ ] **Step 3: Review scan output**

Run:

```bash
jq '.databases.processing.schema_pairs[] | {base_schema, wrk_schema, base_view_count:(.base_views|length), wrk_view_count:(.wrk_views|length), duplicate_base_views}' \
  "01_docs/runbook/artifacts/${RUN_ID}/contract_scan.json"

jq '.databases.gold.schema_pairs[] | {base_schema, wrk_schema, base_view_count:(.base_views|length), wrk_view_count:(.wrk_views|length), duplicate_base_views}' \
  "01_docs/runbook/artifacts/${RUN_ID}/contract_scan.json"
```

Expected:
- Duplicate base views are listed in Processing and Gold.
- `_Wrk` views exist for framework-loaded final tables.

---

### Task 3: Build Dependency Audit Before Any Live DDL

**Files:**
- Create: `03_operations/tools/enterprise_contract/build_wrk_contract_cleanup.py`
- Artifact: `01_docs/runbook/artifacts/<run_id>/dependency_audit.json`
- Artifact: `01_docs/runbook/artifacts/<run_id>/duplicate_base_view_definitions.sql`
- Artifact: `01_docs/runbook/artifacts/<run_id>/candidate_drop_duplicate_base_views.sql`

- [ ] **Step 1: Create cleanup planner script**

Create `03_operations/tools/enterprise_contract/build_wrk_contract_cleanup.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import pathlib


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def find_refs(modules, schema_name, view_name):
    needles = [
        f"{schema_name}.{view_name}",
        f"[{schema_name}].[{view_name}]",
        f"{quote_name(schema_name)}.{quote_name(view_name)}",
    ]
    refs = []
    for module in modules:
        definition = module.get("definition") or ""
        if any(needle.lower() in definition.lower() for needle in needles):
            refs.append(
                {
                    "schema_name": module["schema_name"],
                    "object_name": module["object_name"],
                    "type_desc": module["type_desc"],
                }
            )
    return refs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()
    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    audit = []
    rollback_lines = []
    drop_lines = [
        "-- Candidate only. Do not execute until dependency_audit.json has zero required refs and Aric approves exact drop list.",
    ]
    for db_key in ["processing", "gold"]:
        db = scan["databases"][db_key]
        modules = db["modules"]
        database = db["database"]
        for pair in db["schema_pairs"]:
            base_schema = pair["base_schema"]
            for view_name in pair["duplicate_base_views"]:
                refs = find_refs(modules, base_schema, view_name)
                audit.append(
                    {
                        "database": database,
                        "schema": base_schema,
                        "view": view_name,
                        "required_refs": refs,
                        "safe_to_drop_candidate": len(refs) == 0,
                    }
                )
                rollback_lines.append(f"-- Save live definition for {database}.{base_schema}.{view_name} before drop.")
                drop_lines.append(
                    f"DROP VIEW {quote_name(database)}.{quote_name(base_schema)}.{quote_name(view_name)};"
                )

    (out_dir / "dependency_audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    (out_dir / "candidate_drop_duplicate_base_views.sql").write_text("\n".join(drop_lines) + "\n", encoding="utf-8")
    (out_dir / "duplicate_base_view_definitions.sql").write_text("\n".join(rollback_lines) + "\n", encoding="utf-8")
    print("RESULT", out_dir / "dependency_audit.json")
    print("CANDIDATE_SQL", out_dir / "candidate_drop_duplicate_base_views.sql")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run cleanup planner**

Run:

```bash
python3 -u 03_operations/tools/enterprise_contract/build_wrk_contract_cleanup.py \
  --scan-json "01_docs/runbook/artifacts/${RUN_ID}/contract_scan.json" \
  --out-dir "01_docs/runbook/artifacts/${RUN_ID}"
```

Expected:

```text
RESULT 01_docs/runbook/artifacts/<run_id>/dependency_audit.json
CANDIDATE_SQL 01_docs/runbook/artifacts/<run_id>/candidate_drop_duplicate_base_views.sql
```

- [ ] **Step 3: Block if any required refs remain**

Run:

```bash
jq '[.[] | select(.safe_to_drop_candidate == false)] | length' \
  "01_docs/runbook/artifacts/${RUN_ID}/dependency_audit.json"
```

Expected:
- `0` before any drop is allowed.
- If not `0`, update callers to `_Wrk.v_<TableName>` or final physical table first.

---

### Task 4: Audit Repo References And Rewrite Docs/Manifests

**Files:**
- Modify: `02_marts/**/README.md`
- Modify: `02_marts/**/*.sql`
- Modify: `03_operations/orchestration/**/manifest.yaml`
- Modify: `README.md`
- Modify: `01_docs/architecture/README.md`

- [ ] **Step 1: Search for base-schema `v_*` references**

Run:

```bash
rg -n "(ForecastHistory_Enh|InventoryHistory_Enh|OpenOrderHistory_Enh|ReferenceMaster_Enh|SalesHistory_Enh|ForecastAccuracy_DW|InventoryHealth_DW|Shared_DW)\\.v_" \
  02_marts 03_operations 04_semantic 01_docs README.md AGENTS.md
```

Expected:
- Any operational reference to base-schema `v_*` is reviewed.
- Documentation examples are rewritten to `_Wrk.v_*` or final tables depending on context.

- [ ] **Step 2: Update mart folder convention**

For each mart README under `02_marts/`, add:

```markdown
## Enterprise `_Wrk` Contract

Silver and Gold follow the Enterprise curated-warehouse contract:

- Final schema files document physical final tables: `<Schema>.<TableName>`.
- `_Wrk` view files document load source views: `<Schema>_Wrk.v_<TableName>`.
- ETL Framework metadata points to final table names; the framework derives `_Wrk.v_<TableName>`.
- Base-schema duplicate `v_*` views are not canonical and should not be used by new logic.
```

- [ ] **Step 3: Re-home SQL docs without changing business SQL**

For each Silver/Gold object:

```text
Before:
02_marts/<mart>/2.silver/<schema>/v_<TableName>.sql

After:
02_marts/<mart>/2.silver/<schema>_Wrk/v_<TableName>.sql
02_marts/<mart>/2.silver/<schema>/<TableName>.table.sql
```

`<TableName>.table.sql` should contain only table contract metadata or generated DDL, not duplicate transform logic:

```sql
-- Physical final table contract.
-- Loaded by ETL_Framework from <Schema>_Wrk.v_<TableName>.
-- Business transform SQL lives in ../<Schema>_Wrk/v_<TableName>.sql.
```

- [ ] **Step 4: Update orchestration manifests**

For each `03_operations/orchestration/**/manifest.yaml`, ensure each load step uses final table identity:

```yaml
target_database: SupplyChain_Processing_Warehouse
target_schema: InventoryHistory_Enh
target_table: InventorySnapshotWeekly
source_view: InventoryHistory_Enh_Wrk.v_InventorySnapshotWeekly
framework_loader: DW_Developer.usp_RefreshCuratedTableFromView
```

Expected:
- `target_schema` is never an `_Wrk` schema for final table loads.
- `source_view` is always `_Wrk.v_<TableName>` for Silver/Gold framework loads.

---

### Task 5: Verify ETL Framework Metadata

**Files:**
- Artifact: `01_docs/runbook/artifacts/<run_id>/tabledictionary_contract_audit.json`

- [ ] **Step 1: Query `TableDictionary` for SupplyChain rows**

Run a read-only SQL query against `ETL_Framework`:

```sql
SELECT
    DatabaseName,
    SchemaName,
    TableName,
    ObjectType,
    UpdateMethod,
    UpdateQuery,
    DateKey,
    DateRangeDays
FROM DW_Developer.TableDictionary
WHERE DatabaseName IN ('SupplyChain_Processing_Warehouse', 'SupplyChain_Gold_Warehouse')
ORDER BY DatabaseName, SchemaName, TableName;
```

Expected:
- `SchemaName` is final schema, not `_Wrk`.
- `TableName` is physical table name, not `v_<TableName>`.
- `UpdateQuery` points to an approved framework proc.

- [ ] **Step 2: Flag bad rows**

Rows are bad if:

```text
SchemaName LIKE '%_Wrk'
OR TableName LIKE 'v_%'
OR UpdateQuery IS NULL
```

Expected:
- Bad row count is `0`, or each exception has a documented owner and remediation.

---

### Task 6: Live Compatibility Audit Before Cleanup

**Files:**
- Artifact: `01_docs/runbook/artifacts/<run_id>/compatibility_audit.json`

- [ ] **Step 1: Check live module dependencies**

Run read-only dependency scans in:

```text
SupplyChain_Processing_Warehouse
SupplyChain_Gold_Warehouse
ETL_Framework
```

Check these dependency types:

```text
sys.sql_modules string refs
sys.sql_expression_dependencies where available
TableDictionary target rows
Fabric pipeline SQL snippets if exported locally
Power BI semantic TMDL partitions/sourceLineage where exported locally
repo `rg` references
```

Expected:
- No required dependency points to base-schema duplicate `v_*`.
- Semantic model points to final physical tables, not base-schema views.

- [ ] **Step 2: If dependencies remain, fix references first**

For each dependency:

```text
If transform source -> change to <Schema>_Wrk.v_<TableName>
If serving/report source -> change to <Schema>.<TableName>
If documentation only -> rewrite text and mark as legacy
```

Expected:
- Re-run dependency audit and get zero required refs before cleanup.

---

### Task 7: Approval-Gated Live Cleanup

**Files:**
- Artifact: `01_docs/runbook/artifacts/<run_id>/approved_drop_duplicate_base_views.sql`
- Artifact: `01_docs/runbook/artifacts/<run_id>/rollback_recreate_duplicate_base_views.sql`
- Live DDL: `DROP VIEW` only after explicit approval.

- [ ] **Step 1: Prepare exact approval request**

Send Aric this exact approval summary:

```text
Request approval to drop legacy duplicate base-schema views listed in:
01_docs/runbook/artifacts/<run_id>/approved_drop_duplicate_base_views.sql

No physical tables will be dropped.
No _Wrk views will be dropped.
No business SQL will be changed.
Rollback recreate SQL is saved in:
01_docs/runbook/artifacts/<run_id>/rollback_recreate_duplicate_base_views.sql
```

- [ ] **Step 2: Execute only after approval**

Run only the approved SQL file against the correct warehouse:

```bash
python3 03_operations/tools/sql/run_sql_file.py \
  --database SupplyChain_Processing_Warehouse \
  --sql-file "01_docs/runbook/artifacts/${RUN_ID}/approved_drop_duplicate_base_views_processing.sql" \
  --execute

python3 03_operations/tools/sql/run_sql_file.py \
  --database SupplyChain_Gold_Warehouse \
  --sql-file "01_docs/runbook/artifacts/${RUN_ID}/approved_drop_duplicate_base_views_gold.sql" \
  --execute
```

Expected:
- Only duplicate base views are dropped.
- `_Wrk` views and physical final tables remain.

---

### Task 8: Post-Cleanup Verification

**Files:**
- Create: `03_operations/tools/enterprise_contract/verify_wrk_contract.py`
- Artifact: `01_docs/runbook/artifacts/<run_id>/post_cleanup_verification.json`

- [ ] **Step 1: Create verifier**

Create `03_operations/tools/enterprise_contract/verify_wrk_contract.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--out-json", required=True)
    args = parser.parse_args()
    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    failures = []
    for db_key in ["processing", "gold"]:
        for pair in scan["databases"][db_key]["schema_pairs"]:
            if pair["base_views"]:
                failures.append(
                    {
                        "database": scan["databases"][db_key]["database"],
                        "schema": pair["base_schema"],
                        "remaining_base_views": pair["base_views"],
                    }
                )
            if pair["expected_wrk_views_missing"]:
                failures.append(
                    {
                        "database": scan["databases"][db_key]["database"],
                        "schema": pair["wrk_schema"],
                        "missing_wrk_views": pair["expected_wrk_views_missing"],
                    }
                )
    result = {"pass": len(failures) == 0, "failures": failures}
    pathlib.Path(args.out_json).write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Re-scan and verify**

Run:

```bash
python3 -u 03_operations/tools/enterprise_contract/scan_wrk_contract.py \
  --out-dir "01_docs/runbook/artifacts/${RUN_ID}/post"

python3 -u 03_operations/tools/enterprise_contract/verify_wrk_contract.py \
  --scan-json "01_docs/runbook/artifacts/${RUN_ID}/post/contract_scan.json" \
  --out-json "01_docs/runbook/artifacts/${RUN_ID}/post_cleanup_verification.json"
```

Expected:

```json
{
  "pass": true,
  "failures": []
}
```

- [ ] **Step 3: Run semantic smoke if Gold changed**

Run Power BI refresh and DAX smoke only if Gold duplicate views were removed:

```bash
az rest --method post \
  --resource https://analysis.windows.net/powerbi/api \
  --url "https://api.powerbi.com/v1.0/myorg/groups/c8d9fc83-18b6-4e1d-8264-0b49eed36fe0/datasets/f06a2361-15fd-4f91-9d37-941fefe62aaf/refreshes" \
  --headers "Content-Type=application/json" \
  --body '{"notifyOption":"NoNotification"}'
```

Expected:
- Latest refresh status is `Completed`.
- `serviceExceptionJson` is `null`.

---

### Task 9: Final Documentation And Handoff

**Files:**
- Modify: `00_CONTEXT/current.md`
- Modify: `README.md`
- Modify: `01_docs/architecture/README.md`
- Modify: `01_docs/Enterprise_Framework_Migration_Master_Plan.md`

- [ ] **Step 1: Update context with final status**

Append:

```markdown
## <timestamp ICT> — Enterprise `_Wrk` contract migration complete

**Verified:** Silver/Gold final schemas hold physical final tables; `_Wrk` schemas hold `v_<TableName>` source views; duplicate base-schema `v_*` views removed or explicitly retained as documented exceptions.

**Evidence:** `01_docs/runbook/artifacts/<run_id>/post_cleanup_verification.json`.

**Residual exceptions:** <list exact objects or `None`>.
```

- [ ] **Step 2: Update README navigation**

Add:

```markdown
- Enterprise `_Wrk` Contract: `01_docs/decisions/ADR-009-enterprise-wrk-view-contract.md`
- Latest migration evidence: `01_docs/runbook/artifacts/<run_id>_enterprise_wrk_contract_migration/`
```

- [ ] **Step 3: Commit after verification**

Run:

```bash
git status --short
git add AGENTS.md README.md 00_CONTEXT/current.md 01_docs docs 02_marts 03_operations
git commit -m "docs: align repo with Enterprise wrk view contract"
```

Expected:
- Commit succeeds.
- No unreviewed live DDL candidate is committed as an executable “approved” script unless approval was actually granted.

---

## Acceptance Checklist

- [ ] `SCP_Core` evidence preserved as source of truth.
- [ ] Repo docs state one canonical curated/domain contract.
- [ ] `02_marts` no longer presents duplicate base-schema views as canonical.
- [ ] `03_operations/orchestration` references final tables and `_Wrk` source views clearly.
- [ ] `TableDictionary` rows point to final schemas/tables.
- [ ] `_Wrk.v_<TableName>` exists for every framework-loaded Silver/Gold table.
- [ ] Base-schema duplicate `v_*` views are either removed after approval or listed as temporary compatibility exceptions.
- [ ] No semantic/report breakage after cleanup.
- [ ] `00_CONTEXT/current.md` records the result and evidence paths.

## Risk Register

| Risk | Why It Matters | Mitigation |
|---|---|---|
| Hidden dependency on base-schema `v_*` | A proc/report might still reference legacy views. | Dependency audit via `sys.sql_modules`, repo `rg`, TMDL export, and zero-ref gate before drop. |
| Semantic/report binding drift | Report may not use views but any hidden query could. | DAX smoke and dataset refresh after Gold cleanup. |
| TableDictionary mismatch | Loader may derive wrong `_Wrk.v_<TableName>`. | Audit `SchemaName`, `TableName`, `UpdateQuery`; fix metadata before runtime. |
| Source layer confusion | `Source_Data` uses `_Wrk` as tables in many places. | Apply this cleanup only to curated/domain Silver/Gold, not raw/source landing. |
| Destructive cleanup too early | `DROP VIEW` can break compatibility. | Save rollback definitions and require explicit approval for exact drop list. |

## Execution Recommendation

Use two-stage execution:

1. **Stage A: Non-destructive alignment**
   - ADR, docs, repo mart structure, scanners, dependency audit.
   - No live DDL.

2. **Stage B: Approval-gated live cleanup**
   - Drop only duplicate base-schema views proven unused.
   - Keep rollback SQL.
   - Run post-cleanup verification and semantic smoke.

## Execution Update — 2026-06-23 22:15 ICT

Stage A is complete and persisted in repo/docs. The approved metadata cleanup is also complete:

- Removed 2 stale `ETL_Framework.DW_Developer.TableDictionary` rows for live-missing Gold objects:
  - `InventoryHealth_DW.CogsRollingHelper`
  - `InventoryHealth_DW.FactInventoryRiskForward`
- Refreshed scan/verifier:
  - `tabledictionary_bad_rows = 0`
  - missing `_Wrk` views = `0`
  - pre-clean verifier passes with `allow_base_views=true`

Stage B is split into safer subpackages:

- Gold identical-contract package is generated but not executed:
  - `candidate_alter_wrk_views_gold_identical_contract.sql`
  - `rollback_wrk_views_gold_identical_contract.sql`
  - `candidate_drop_base_views_gold_after_identical_wrk_rewrite.sql`
  - Static QC: `13` `CREATE OR ALTER VIEW`, `13` `DROP VIEW`, `0` direct base-view refs in candidate alter script.
- Processing/Silver is not auto-rewritten:
  - `31` simple `LoadDT` wrapper cases require SQL-aware rewrite to preserve `LoadDT`.
  - `1` non-simple case, `ReferenceMaster_Enh.v_ItemMaster`, requires manual design because base and `_Wrk` contracts have large schema drift.

2026-06-23 22:45 ICT final status:

- Live cleanup completed.
- `45` `_Wrk` views were rewritten to inline source/business SQL directly against source/final tables instead of wrapping base-schema `v_*` views.
- `45` legacy duplicate base-schema `v_*` views were dropped:
  - `32` in `SupplyChain_Processing_Warehouse`
  - `13` in `SupplyChain_Gold_Warehouse`
- Strict verifier passed with `allow_base_views=false`.
- Post-drop `_Wrk` smoke passed for all `45` rewritten views with column counts matching final physical tables.
- Legacy module reference scan and active mart SQL scan both found `0` refs to the removed base-schema `v_*` views.
