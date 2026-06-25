#!/usr/bin/env python3
"""Generate build-only SQLPROJ packages for the BOB-aligned SupplyChain runtime.

The generated package is a local source-control/deployment-validation artifact:
- final table DDL is generated from live Fabric Warehouse metadata
- _Wrk view and wrapper proc definitions are copied from the repo
- ETL_Framework tables/modules are exported read-only from live metadata
- no publish/deploy operation is performed
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
BUILD_SQL_VERSION = "2.2.0"
FABRIC_DW_DACPAC_VERSION = "170.0.4"

DATABASES = {
    "etl": "ETL_Framework",
    "enterprise": "Enterprise_Lakehouse",
    "processing": "SupplyChain_Processing_Warehouse",
    "gold": "SupplyChain_Gold_Warehouse",
}

OUT_ROOT = Path("03_operations/deployment/sqlproj")


@dataclass(frozen=True)
class SqlObject:
    database: str
    schema: str
    name: str
    object_type: str


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def az_token_attr() -> bytes:
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


def connect(database: str, token: bytes) -> pyodbc.Connection:
    return pyodbc.connect(
        (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={SERVER};DATABASE={database};"
            "Encrypt=yes;TrustServerCertificate=no;"
        ),
        attrs_before={1256: token},
        timeout=120,
        autocommit=True,
    )


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    columns = [desc[0] for desc in cur.description]
    return [dict(zip(columns, row)) for row in cur.fetchall()]


def bracket(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def safe_filename(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_. -]+", "_", name).strip(" .") or "object"


def sql_type(row: dict[str, Any]) -> str:
    data_type = str(row["data_type"]).lower()
    max_length = int(row["max_length"])
    precision = int(row["precision"])
    scale = int(row["scale"])

    if data_type in {"varchar", "char", "binary", "varbinary"}:
        if max_length == -1:
            return f"{data_type}(max)"
        return f"{data_type}({max_length})"
    if data_type in {"nvarchar", "nchar"}:
        if max_length == -1:
            return f"{data_type}(max)"
        return f"{data_type}({max(1, max_length // 2)})"
    if data_type in {"decimal", "numeric"}:
        return f"{data_type}({precision},{scale})"
    if data_type in {"datetime2", "datetimeoffset", "time"}:
        return f"{data_type}({scale})"
    return data_type


def fetch_table_columns(conn: pyodbc.Connection) -> dict[tuple[str, str], list[dict[str, Any]]]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            c.name AS column_name,
            c.column_id,
            TYPE_NAME(c.user_type_id) AS data_type,
            c.max_length,
            c.precision,
            c.scale,
            c.is_nullable
        FROM sys.columns c
        JOIN sys.objects o ON o.object_id = c.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
          AND o.type = 'U'
        ORDER BY s.name, o.name, c.column_id
        """
    )
    result: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in rows_as_dicts(cur):
        result.setdefault((str(row["schema_name"]), str(row["object_name"])), []).append(row)
    return result


def fetch_modules(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type AS object_type,
            o.type_desc,
            m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY s.name, o.name
        """
    )
    return rows_as_dicts(cur)


def create_table_sql(schema: str, table: str, columns: list[dict[str, Any]], source: str) -> str:
    col_lines = []
    for col in columns:
        nullable = "NULL" if int(col["is_nullable"]) else "NOT NULL"
        col_lines.append(f"    {bracket(str(col['column_name']))} {sql_type(col)} {nullable}")
    return (
        f"-- Generated from live Fabric metadata: {source}\n"
        f"CREATE TABLE {bracket(schema)}.{bracket(table)} (\n"
        + ",\n".join(col_lines)
        + "\n);\n"
    )


def normalize_object_sql(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"(?im)^\s*GO\s*;?\s*$", "", text)
    text = re.sub(r"(?i)\bCREATE\s+OR\s+ALTER\s+PROCEDURE\b", "CREATE PROCEDURE", text)
    text = re.sub(r"(?i)\bCREATE\s+OR\s+ALTER\s+PROC\b", "CREATE PROC", text)
    text = re.sub(r"(?i)\bCREATE\s+OR\s+ALTER\s+VIEW\b", "CREATE VIEW", text)
    text = re.sub(r"(?i)\bCREATE\s+OR\s+ALTER\s+FUNCTION\b", "CREATE FUNCTION", text)
    return text.strip() + "\n"


def normalize_self_database_references(text: str, database_name: str | None) -> str:
    if not database_name:
        return text
    text = re.sub(rf"(?i)\[{re.escape(database_name)}\]\s*\.", "", text)
    text = re.sub(rf"(?i)\b{re.escape(database_name)}\s*\.", "", text)
    return text


def object_folder(schema: str, object_type: str) -> Path:
    if object_type == "table":
        return Path(schema) / "Tables"
    if object_type == "view":
        return Path(schema) / "Views"
    if object_type == "procedure":
        return Path(schema) / "Stored Procedures"
    if object_type == "function":
        return Path(schema) / "Functions"
    return Path(schema) / "Objects"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def parse_final_table_file(path: Path) -> tuple[str, str] | None:
    if not path.name.endswith(".table.sql"):
        return None
    schema = path.parent.name
    table = path.name.removesuffix(".table.sql")
    return schema, table


def active_processing_table_refs(repo_root: Path) -> set[tuple[str, str]]:
    refs: set[tuple[str, str]] = set()
    for mart in ["forecast_accuracy", "inventory_health"]:
        for folder in ["00_source_wrk", "02_silver"]:
            base = repo_root / "02_marts" / mart / folder
            if not base.exists():
                continue
            for path in sorted(base.glob("**/*.table.sql")):
                parsed = parse_final_table_file(path)
                if parsed:
                    refs.add(parsed)
            for path in sorted(base.glob("**/*.sql")):
                if path.name.endswith(".table.sql"):
                    continue
                stem = path.name.removesuffix(".sql")
                if "." in stem and not stem.startswith("Enterprise_Lakehouse."):
                    schema, table = stem.split(".", 1)
                    if not table.startswith("v_"):
                        refs.add((schema, table))
    return refs


def active_gold_table_refs(repo_root: Path) -> set[tuple[str, str]]:
    refs: set[tuple[str, str]] = set()
    for mart in ["forecast_accuracy", "inventory_health"]:
        base = repo_root / "02_marts" / mart / "03_gold"
        for path in sorted(base.glob("**/*.table.sql")):
            parsed = parse_final_table_file(path)
            if parsed:
                refs.add(parsed)
    return refs


def enterprise_lakehouse_refs(repo_root: Path) -> set[tuple[str, str]]:
    refs: set[tuple[str, str]] = set()
    pattern = re.compile(
        r"(?:\[?Enterprise_Lakehouse\]?)\s*\.\s*(?:\[?([A-Za-z_][A-Za-z0-9_]*)\]?)\s*\.\s*(?:\[?([A-Za-z_][A-Za-z0-9_]*)\]?)",
        re.IGNORECASE,
    )
    active_roots = [
        repo_root / "02_marts" / "forecast_accuracy" / "00_source_wrk",
        repo_root / "02_marts" / "forecast_accuracy" / "02_silver",
        repo_root / "02_marts" / "inventory_health" / "00_source_wrk",
        repo_root / "02_marts" / "inventory_health" / "02_silver",
    ]
    for root in active_roots:
        if not root.exists():
            continue
        for path in sorted(root.glob("**/*.sql")):
            if path.name.endswith(".table.sql"):
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for match in pattern.finditer(text):
                refs.add((match.group(1), match.group(2)))
    for path in sorted((repo_root / "02_marts").glob("*/01_bronze/01_enterprise_lakehouse/*.sql")):
        parts = path.name.removesuffix(".sql").split(".")
        if len(parts) == 3:
            refs.add((parts[1], parts[2]))
    return refs


def copy_repo_sql_file(
    source: Path,
    target_root: Path,
    schema: str,
    object_name: str,
    object_type: str,
    manifest: list[dict[str, Any]],
    local_database: str | None = None,
) -> None:
    rel = object_folder(schema, object_type) / f"{safe_filename(object_name)}.sql"
    text = normalize_object_sql(source.read_text(encoding="utf-8", errors="ignore"))
    text = normalize_self_database_references(text, local_database)
    write_text(target_root / rel, text)
    manifest.append(
        {
            "source": str(source),
            "target": str(rel),
            "schema": schema,
            "object": object_name,
            "object_type": object_type,
            "source_kind": "repo_sql",
        }
    )


def copy_processing_repo_modules(repo_root: Path, target_root: Path, manifest: list[dict[str, Any]]) -> None:
    for mart in ["forecast_accuracy", "inventory_health"]:
        for folder in ["00_source_wrk", "02_silver"]:
            base = repo_root / "02_marts" / mart / folder
            if not base.exists():
                continue
            for path in sorted(base.glob("**/*.sql")):
                if path.name.endswith(".table.sql"):
                    continue
                stem = path.name.removesuffix(".sql")
                if "." in stem:
                    schema, object_name = stem.split(".", 1)
                else:
                    schema = path.parent.name
                    object_name = stem
                if object_name.startswith("v_") or schema.endswith("_Wrk"):
                    copy_repo_sql_file(path, target_root, schema, object_name, "view", manifest, DATABASES["processing"])
    for path in sorted((repo_root / "03_operations/orchestration").glob("*/sql/SupplyChain_Processing_Warehouse.*.sql")):
        object_name = path.name.split(".")[-2] if path.name.endswith(".sql") else path.stem
        copy_repo_sql_file(path, target_root, "dbo", object_name, "procedure", manifest, DATABASES["processing"])


def copy_gold_repo_modules(repo_root: Path, target_root: Path, manifest: list[dict[str, Any]]) -> None:
    for mart in ["forecast_accuracy", "inventory_health"]:
        base = repo_root / "02_marts" / mart / "03_gold"
        if not base.exists():
            continue
        for path in sorted(base.glob("**/*.sql")):
            if path.name.endswith(".table.sql"):
                continue
            stem = path.name.removesuffix(".sql")
            schema = path.parent.name
            object_name = stem
            if object_name.startswith("v_") or schema.endswith("_Wrk"):
                copy_repo_sql_file(path, target_root, schema, object_name, "view", manifest, DATABASES["gold"])
    for path in sorted((repo_root / "03_operations/orchestration").glob("*/sql/SupplyChain_Gold_Warehouse.*.sql")):
        object_name = path.name.split(".")[-2] if path.name.endswith(".sql") else path.stem
        copy_repo_sql_file(path, target_root, "dbo", object_name, "procedure", manifest, DATABASES["gold"])


def module_type_folder(object_type: str) -> str:
    if object_type == "V":
        return "view"
    if object_type == "P":
        return "procedure"
    if object_type in {"FN", "IF", "TF", "FS", "FT"}:
        return "function"
    return "sql_object"


def export_etl_framework(conn: pyodbc.Connection, target_root: Path, manifest: list[dict[str, Any]]) -> None:
    tables = fetch_table_columns(conn)
    for (schema, table), columns in sorted(tables.items()):
        if "_BACKUP_" in table or "_RESTORE_" in table or "_semantic_recovery" in table:
            continue
        rel = object_folder(schema, "table") / f"{safe_filename(table)}.sql"
        write_text(target_root / rel, create_table_sql(schema, table, columns, "ETL_Framework"))
        manifest.append({"schema": schema, "object": table, "object_type": "table", "target": str(rel), "source_kind": "live_metadata"})

    for module in fetch_modules(conn):
        schema = str(module["schema_name"])
        name = str(module["object_name"])
        obj_type = module_type_folder(str(module["object_type"]))
        if obj_type == "sql_object":
            continue
        rel = object_folder(schema, obj_type) / f"{safe_filename(name)}.sql"
        write_text(target_root / rel, normalize_object_sql(str(module["definition"])))
        manifest.append({"schema": schema, "object": name, "object_type": obj_type, "target": str(rel), "source_kind": "live_module"})


def write_table_ddls(database: str, conn: pyodbc.Connection, target_root: Path, refs: set[tuple[str, str]], manifest: list[dict[str, Any]]) -> None:
    live_tables = fetch_table_columns(conn)
    live_ci = {(schema.lower(), table.lower()): (schema, table, columns) for (schema, table), columns in live_tables.items()}
    missing = []
    for schema, table in sorted(refs):
        exact = live_tables.get((schema, table))
        resolved = live_ci.get((schema.lower(), table.lower()))
        columns = exact or (resolved[2] if resolved else None)
        if not columns:
            missing.append({"schema": schema, "table": table})
            continue
        rel = object_folder(schema, "table") / f"{safe_filename(table)}.sql"
        write_text(target_root / rel, create_table_sql(schema, table, columns, database))
        manifest.append({"schema": schema, "object": table, "object_type": "table", "target": str(rel), "source_kind": "live_metadata"})
    if missing:
        write_json(target_root / "_package" / "missing_live_tables.json", missing)


def write_schema_files(target_root: Path, manifest: list[dict[str, Any]]) -> None:
    schemas = sorted({str(row["schema"]) for row in manifest if row.get("schema")})
    for schema in schemas:
        if schema.lower() == "dbo":
            continue
        rel = Path(schema) / f"{safe_filename(schema)}.schema.sql"
        if (target_root / rel).exists():
            continue
        write_text(target_root / rel, f"CREATE SCHEMA {bracket(schema)};\n")
        manifest.append({"schema": schema, "object": schema, "object_type": "schema", "target": str(rel), "source_kind": "generated"})


def sqlcmd_variables(project_name: str) -> list[str]:
    values = ["ETL_Framework", "SupplyChain_Processing_Warehouse", "SupplyChain_Gold_Warehouse", "Enterprise_Lakehouse"]
    if project_name != "ETL_Framework":
        values.append("Staging")
    return values


def project_references(project_name: str) -> str:
    refs: list[tuple[str, str, str]] = []
    if project_name == "SupplyChain_Processing_Warehouse":
        refs = [
            ("..\\ETL_Framework\\ETL_Framework.sqlproj", "ETL_Framework", "ETL_Framework"),
            ("..\\Enterprise_Lakehouse_Reference\\Enterprise_Lakehouse_Reference.sqlproj", "Enterprise_Lakehouse_Reference", "Enterprise_Lakehouse"),
        ]
    elif project_name == "SupplyChain_Gold_Warehouse":
        refs = [
            ("..\\ETL_Framework\\ETL_Framework.sqlproj", "ETL_Framework", "ETL_Framework"),
            ("..\\Enterprise_Lakehouse_Reference\\Enterprise_Lakehouse_Reference.sqlproj", "Enterprise_Lakehouse_Reference", "Enterprise_Lakehouse"),
            ("..\\SupplyChain_Processing_Warehouse\\SupplyChain_Processing_Warehouse.sqlproj", "SupplyChain_Processing_Warehouse", "SupplyChain_Processing_Warehouse"),
        ]
    if not refs:
        return ""
    body = "\n".join(
        f"""    <ProjectReference Include="{include}">
      <Name>{name}</Name>
      <DatabaseVariableLiteralValue>{database_name}</DatabaseVariableLiteralValue>
    </ProjectReference>"""
        for include, name, database_name in refs
    )
    return f"""
  <ItemGroup>
{body}
  </ItemGroup>"""


def sqlproj(project_name: str) -> str:
    variables = "\n".join(
        f"""    <SqlCmdVariable Include="{name}">
      <DefaultValue>{name}</DefaultValue>
      <Value>{name}</Value>
    </SqlCmdVariable>"""
        for name in sqlcmd_variables(project_name)
    )
    return f"""<Project DefaultTargets="Build">
  <Sdk Name="Microsoft.Build.Sql" Version="{BUILD_SQL_VERSION}" />
  <PropertyGroup>
    <Name>{project_name}</Name>
    <DSP>Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider</DSP>
    <ModelCollation>1033, CI</ModelCollation>
    <TargetDatabaseSet>True</TargetDatabaseSet>
    <SuppressMissingDependenciesErrors>True</SuppressMissingDependenciesErrors>
    <RunSqlCodeAnalysis>False</RunSqlCodeAnalysis>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.SqlServer.Dacpacs.FabricDw" Version="{FABRIC_DW_DACPAC_VERSION}" />
{variables}
  </ItemGroup>
  <ItemGroup>
    <Build Remove="_package\\**\\*" />
    <None Include="_package\\**\\*" />
  </ItemGroup>{project_references(project_name)}
  <Target Name="BeforeBuild">
    <Delete Files="$(BaseIntermediateOutputPath)\\project.assets.json" />
  </Target>
</Project>
"""


def write_project_readme(path: Path, project_name: str, generated_at: str) -> None:
    write_text(
        path,
        f"""# {project_name}

Build-only SQL Database Project generated from the current BOB-aligned SupplyChain runtime.

Generated at: `{generated_at}`

## Build

```bash
dotnet build {project_name}.sqlproj -c Release
```

## Safety

This project is for local validation and deploy-script review only.
Do not publish this project to Fabric until US/BOB CI-CD ownership, publish profile, service connection, and data-loss policy are approved.
""",
    )


def write_root_readme(out_root: Path, generated_at: str) -> None:
    write_text(
        out_root / "README.md",
        f"""# SQLPROJ Deployment Package

Generated at: `{generated_at}`

This folder contains local, build-only `.sqlproj` packages for the current Phase 1 BOB-aligned runtime.

| Project | Meaning |
|---|---|
| `Enterprise_Lakehouse_Reference` | Build-time reference stubs for active Bronze source tables. |
| `ETL_Framework` | Framework metadata/audit tables, loader procs, helper functions. |
| `SupplyChain_Processing_Warehouse` | Silver/processing final tables, `_Wrk` views, and mart Silver wrappers. |
| `SupplyChain_Gold_Warehouse` | Gold/shared final tables, `_Wrk` views, and mart Gold wrappers. |

## Build All

```bash
./build_all.sh
```

## Non-goals

- No live Fabric publish.
- No CI/CD workflow creation.
- No destructive cleanup.
- No replacement of SQL Agent runtime.

The runtime handoff remains the four wrapper procedures documented in `01_docs/decisions/ADR-010-bob-wrapper-runtime-handoff.md`.
""",
    )
    write_text(
        out_root / "build_all.sh",
        """#!/usr/bin/env bash
set -euo pipefail

dotnet build ETL_Framework/ETL_Framework.sqlproj -c Release
dotnet build Enterprise_Lakehouse_Reference/Enterprise_Lakehouse_Reference.sqlproj -c Release
dotnet build SupplyChain_Processing_Warehouse/SupplyChain_Processing_Warehouse.sqlproj -c Release
dotnet build SupplyChain_Gold_Warehouse/SupplyChain_Gold_Warehouse.sqlproj -c Release
""",
    )


def generate(repo_root: Path, out_root: Path) -> dict[str, Any]:
    generated_at = utc_now()
    token = az_token_attr()
    if out_root.exists() and any(out_root.iterdir()):
        raise SystemExit(
            f"Refusing to overwrite non-empty generated package folder: {out_root}. "
            "Move/archive it explicitly before regenerating."
        )
    out_root.mkdir(parents=True, exist_ok=True)
    manifests: dict[str, list[dict[str, Any]]] = {}

    conns = {key: connect(db, token) for key, db in DATABASES.items()}
    try:
        for project_name, key in [
            ("Enterprise_Lakehouse_Reference", "enterprise"),
            ("ETL_Framework", "etl"),
            ("SupplyChain_Processing_Warehouse", "processing"),
            ("SupplyChain_Gold_Warehouse", "gold"),
        ]:
            project_root = out_root / project_name
            project_root.mkdir(parents=True, exist_ok=True)
            manifest: list[dict[str, Any]] = []
            write_text(project_root / f"{project_name}.sqlproj", sqlproj(project_name))
            if project_name == "Enterprise_Lakehouse_Reference":
                write_table_ddls("Enterprise_Lakehouse", conns[key], project_root, enterprise_lakehouse_refs(repo_root), manifest)
            elif project_name == "ETL_Framework":
                export_etl_framework(conns[key], project_root, manifest)
            elif project_name == "SupplyChain_Processing_Warehouse":
                write_table_ddls(project_name, conns[key], project_root, active_processing_table_refs(repo_root), manifest)
                copy_processing_repo_modules(repo_root, project_root, manifest)
            else:
                write_table_ddls(project_name, conns[key], project_root, active_gold_table_refs(repo_root), manifest)
                copy_gold_repo_modules(repo_root, project_root, manifest)
            write_schema_files(project_root, manifest)
            write_project_readme(project_root / "README.md", project_name, generated_at)
            write_json(project_root / "_package" / "manifest.json", {"generated_at_utc": generated_at, "project": project_name, "objects": manifest})
            manifests[project_name] = manifest
    finally:
        for conn in conns.values():
            conn.close()

    write_root_readme(out_root, generated_at)
    summary = {
        "generated_at_utc": generated_at,
        "output_root": str(out_root),
        "sdk": {"Microsoft.Build.Sql": BUILD_SQL_VERSION, "Microsoft.SqlServer.Dacpacs.FabricDw": FABRIC_DW_DACPAC_VERSION},
        "projects": {name: {"object_count": len(objects)} for name, objects in manifests.items()},
        "safety": "build_only_no_publish",
    }
    write_json(out_root / "package_summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate local build-only SQLPROJ package.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--out-root", default=str(OUT_ROOT), help="Output folder for generated SQLPROJ package.")
    args = parser.parse_args()
    repo_root = Path(args.repo_root).resolve()
    out_root = (repo_root / args.out_root).resolve() if not Path(args.out_root).is_absolute() else Path(args.out_root)
    summary = generate(repo_root, out_root)
    print(json.dumps(summary, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
