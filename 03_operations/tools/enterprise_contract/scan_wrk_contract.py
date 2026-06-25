#!/usr/bin/env python3
"""Read-only scan for the Enterprise curated `_Wrk` view contract."""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import subprocess
import time
from typing import Any

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"

DEFAULT_DATABASES = {
    "processing": "SupplyChain_Processing_Warehouse",
    "gold": "SupplyChain_Gold_Warehouse",
    "etl": "ETL_Framework",
}


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


def connect(database: str, token: bytes):
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


def fetch_all(cur, sql: str) -> list[dict[str, Any]]:
    cur.execute(sql)
    columns = [d[0] for d in cur.description]
    return [dict(zip(columns, row)) for row in cur.fetchall()]


def object_map(objects: list[dict[str, Any]]) -> dict[str, dict[str, list[str]]]:
    result: dict[str, dict[str, list[str]]] = {}
    for obj in objects:
        result.setdefault(obj["schema_name"], {}).setdefault(obj["type_desc"], []).append(obj["object_name"])
    for by_type in result.values():
        for names in by_type.values():
            names.sort()
    return result


def is_framework_final_table(table_name: str) -> bool:
    backup_markers = ("_BACKUP_", "_RESTORE_", "_semantic_recovery")
    return not any(marker in table_name for marker in backup_markers)


def scan_database(database: str, token: bytes) -> dict[str, Any]:
    conn = connect(database, token)
    cur = conn.cursor()
    objects = fetch_all(
        cur,
        """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc,
            CONVERT(varchar(33), o.create_date, 126) AS create_date,
            CONVERT(varchar(33), o.modify_date, 126) AS modify_date
        FROM sys.objects o
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY s.name, o.type_desc, o.name
        """,
    )
    modules = fetch_all(
        cur,
        """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc,
            m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY s.name, o.name
        """,
    )
    columns = fetch_all(
        cur,
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
          AND o.type IN ('U', 'V')
        ORDER BY s.name, o.name, c.column_id
        """,
    )
    by_schema = object_map(objects)
    schema_pairs: list[dict[str, Any]] = []
    for wrk_schema in sorted(s for s in by_schema if s.endswith("_Wrk")):
        base_schema = wrk_schema[:-4]
        if base_schema not in by_schema:
            continue
        base_tables = [name for name in by_schema[base_schema].get("USER_TABLE", []) if is_framework_final_table(name)]
        base_views = by_schema[base_schema].get("VIEW", [])
        wrk_views = by_schema[wrk_schema].get("VIEW", [])
        expected_wrk = [f"v_{table}" for table in base_tables]
        schema_pairs.append(
            {
                "base_schema": base_schema,
                "wrk_schema": wrk_schema,
                "base_tables": base_tables,
                "base_views": base_views,
                "wrk_views": wrk_views,
                "expected_wrk_views_missing": sorted(set(expected_wrk) - set(wrk_views)),
                "duplicate_base_views": sorted(set(base_views) & set(wrk_views)),
                "base_view_only": sorted(set(base_views) - set(wrk_views)),
                "wrk_view_only": sorted(set(wrk_views) - set(base_views)),
            }
        )
    return {
        "database": database,
        "objects": objects,
        "columns": columns,
        "schema_object_map": by_schema,
        "modules": modules,
        "schema_pairs": schema_pairs,
    }


def scan_tabledictionary(token: bytes) -> dict[str, Any]:
    conn = connect("ETL_Framework", token)
    cur = conn.cursor()
    rows = fetch_all(
        cur,
        """
        SELECT
            DatabaseName,
            SchemaName,
            TableName,
            ObjectType,
            UpdateMethod,
            UpdateQuery,
            DateKey,
            DateRangeDays,
            Modified
        FROM DW_Developer.TableDictionary
        WHERE DatabaseName IN ('SupplyChain_Processing_Warehouse', 'SupplyChain_Gold_Warehouse')
        ORDER BY DatabaseName, SchemaName, TableName
        """,
    )
    final_table_rows = [
        row
        for row in rows
        if row.get("ObjectType") == "Table"
        and not row["TableName"].startswith("v_")
        and not row["SchemaName"].endswith("_Wrk")
    ]
    bad_rows = [
        row
        for row in final_table_rows
        if not row.get("UpdateQuery") and not any(marker in row["TableName"] for marker in ("BACKUP", "RESTORE"))
    ]
    non_canonical_rows = [
        row
        for row in rows
        if row["SchemaName"].endswith("_Wrk") or row["TableName"].startswith("v_")
    ]
    return {
        "rows": rows,
        "final_table_rows": final_table_rows,
        "bad_rows": bad_rows,
        "non_canonical_rows": non_canonical_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    token = token_attr()
    result = {
        "checked_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "server": SERVER,
        "databases": {key: scan_database(db, token) for key, db in DEFAULT_DATABASES.items()},
        "tabledictionary": scan_tabledictionary(token),
    }
    out = out_dir / "contract_scan.json"
    out.write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")

    compact = {
        key: {
            "database": value["database"],
            "schema_pairs": [
                {
                    "base_schema": pair["base_schema"],
                    "base_views": len(pair["base_views"]),
                    "wrk_views": len(pair["wrk_views"]),
                    "duplicate_base_views": len(pair["duplicate_base_views"]),
                    "missing_wrk_views": len(pair["expected_wrk_views_missing"]),
                }
                for pair in value["schema_pairs"]
            ],
        }
        for key, value in result["databases"].items()
    }
    compact["tabledictionary_bad_rows"] = len(result["tabledictionary"]["bad_rows"])
    print(json.dumps(compact, indent=2))
    print("RESULT", out)


if __name__ == "__main__":
    main()
