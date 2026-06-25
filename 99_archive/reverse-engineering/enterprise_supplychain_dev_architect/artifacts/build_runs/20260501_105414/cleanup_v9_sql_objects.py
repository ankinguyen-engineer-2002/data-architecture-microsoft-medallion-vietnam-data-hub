#!/usr/bin/env python3
"""Inventory, drop, and verify v9 SQL objects in SupplyChain_Warehouse.

Scope is intentionally narrow:
- Target schemas: bronze, silver, gold, meta.
- Drop objects inside those schemas only.
- Do not drop schemas, databases, warehouse items, lakehouses, or Fabric items.
"""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Warehouse"
TARGET_SCHEMAS = ("bronze", "silver", "gold", "meta")
DROP_RETRY_PASSES = 5


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def fq(schema_name: str, object_name: str) -> str:
    return f"{quote_name(schema_name)}.{quote_name(object_name)}"


def get_access_token() -> bytes:
    raw = subprocess.run(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--output",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    token = json.loads(raw.stdout)["accessToken"].encode("UTF-16-LE")
    return struct.pack(f"<I{len(token)}s", len(token), token)


def connect() -> pyodbc.Connection:
    token_struct = get_access_token()
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        timeout=30,
        autocommit=True,
    )


def fetch_dicts(cur: pyodbc.Cursor, sql: str, params: Iterable[str] = ()) -> list[dict]:
    cur.execute(sql, tuple(params))
    cols = [col[0] for col in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def inventory(conn: pyodbc.Connection) -> dict:
    cur = conn.cursor()
    placeholders = ",".join("?" for _ in TARGET_SCHEMAS)

    objects = fetch_dicts(
        cur,
        f"""
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            RTRIM(o.type) AS object_type,
            o.type_desc AS object_type_desc,
            o.object_id
        FROM sys.objects o
        JOIN sys.schemas s
            ON s.schema_id = o.schema_id
        WHERE s.name IN ({placeholders})
          AND o.is_ms_shipped = 0
        ORDER BY
            CASE o.type
                WHEN 'V' THEN 10
                WHEN 'P' THEN 20
                WHEN 'FN' THEN 30
                WHEN 'IF' THEN 30
                WHEN 'TF' THEN 30
                WHEN 'U' THEN 90
                ELSE 50
            END,
            s.name,
            o.name;
        """,
        TARGET_SCHEMAS,
    )

    sequences = fetch_dicts(
        cur,
        f"""
        SELECT
            s.name AS schema_name,
            seq.name AS object_name,
            'SO' AS object_type,
            'SEQUENCE_OBJECT' AS object_type_desc,
            seq.object_id
        FROM sys.sequences seq
        JOIN sys.schemas s
            ON s.schema_id = seq.schema_id
        WHERE s.name IN ({placeholders})
        ORDER BY s.name, seq.name;
        """,
        TARGET_SCHEMAS,
    )

    foreign_keys = fetch_dicts(
        cur,
        f"""
        SELECT
            fk.name AS constraint_name,
            ps.name AS parent_schema_name,
            pt.name AS parent_table_name,
            rs.name AS referenced_schema_name,
            rt.name AS referenced_table_name,
            fk.object_id
        FROM sys.foreign_keys fk
        JOIN sys.tables pt
            ON pt.object_id = fk.parent_object_id
        JOIN sys.schemas ps
            ON ps.schema_id = pt.schema_id
        JOIN sys.tables rt
            ON rt.object_id = fk.referenced_object_id
        JOIN sys.schemas rs
            ON rs.schema_id = rt.schema_id
        WHERE ps.name IN ({placeholders})
           OR rs.name IN ({placeholders})
        ORDER BY ps.name, pt.name, fk.name;
        """,
        TARGET_SCHEMAS + TARGET_SCHEMAS,
    )

    counts: dict[str, int] = {}
    for obj in objects + sequences:
        key = f"{obj['schema_name']}.{obj['object_type_desc']}"
        counts[key] = counts.get(key, 0) + 1

    return {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "server": SERVER,
        "database": DATABASE,
        "target_schemas": list(TARGET_SCHEMAS),
        "object_count": len(objects) + len(sequences),
        "foreign_key_count": len(foreign_keys),
        "counts": counts,
        "objects": objects + sequences,
        "foreign_keys": foreign_keys,
    }


def drop_statement(obj: dict) -> str:
    obj_type = obj["object_type"]
    name = fq(obj["schema_name"], obj["object_name"])
    if obj_type == "V":
        return f"DROP VIEW {name};"
    if obj_type == "P":
        return f"DROP PROCEDURE {name};"
    if obj_type in {"FN", "IF", "TF", "FS", "FT"}:
        return f"DROP FUNCTION {name};"
    if obj_type == "U":
        return f"DROP TABLE {name};"
    if obj_type == "SO":
        return f"DROP SEQUENCE {name};"
    if obj_type == "SN":
        return f"DROP SYNONYM {name};"
    raise ValueError(f"Unsupported object type for drop: {obj_type} {name}")


def drop_foreign_keys(conn: pyodbc.Connection, foreign_keys: list[dict]) -> list[dict]:
    cur = conn.cursor()
    results = []
    for fk in foreign_keys:
        stmt = (
            "ALTER TABLE "
            f"{fq(fk['parent_schema_name'], fk['parent_table_name'])} "
            f"DROP CONSTRAINT {quote_name(fk['constraint_name'])};"
        )
        try:
            cur.execute(stmt)
            results.append({"status": "dropped", "statement": stmt, **fk})
        except Exception as exc:  # noqa: BLE001 - evidence should preserve exact failure text.
            results.append(
                {"status": "failed", "statement": stmt, "error": str(exc), **fk}
            )
    return results


def drop_objects(conn: pyodbc.Connection, objects: list[dict]) -> list[dict]:
    pending = [obj for obj in objects if obj["object_type"] not in {"D", "PK", "F"}]
    results: list[dict] = []

    for pass_no in range(1, DROP_RETRY_PASSES + 1):
        if not pending:
            break
        next_pending = []
        for obj in pending:
            try:
                stmt = drop_statement(obj)
            except ValueError as exc:
                results.append({"status": "unsupported", "error": str(exc), **obj})
                continue

            try:
                conn.cursor().execute(stmt)
                results.append({"status": "dropped", "pass": pass_no, "statement": stmt, **obj})
            except Exception as exc:  # noqa: BLE001 - evidence should preserve exact failure text.
                if pass_no == DROP_RETRY_PASSES:
                    results.append(
                        {
                            "status": "failed",
                            "pass": pass_no,
                            "statement": stmt,
                            "error": str(exc),
                            **obj,
                        }
                    )
                else:
                    next_pending.append(obj)
        pending = next_pending

    return results


def write_json(path: Path, payload: dict | list) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["inventory", "cleanup", "verify"], required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    conn = connect()
    before = inventory(conn)

    if args.mode == "inventory":
        write_json(out_dir / "sql_inventory_pre.json", before)
        print(json.dumps({"mode": args.mode, "object_count": before["object_count"]}, sort_keys=True))
        return 0

    if args.mode == "verify":
        write_json(out_dir / "sql_inventory_verify.json", before)
        print(json.dumps({"mode": args.mode, "object_count": before["object_count"]}, sort_keys=True))
        return 0 if before["object_count"] == 0 else 2

    write_json(out_dir / "sql_inventory_pre_cleanup.json", before)
    fk_results = drop_foreign_keys(conn, before["foreign_keys"])
    object_results = drop_objects(conn, before["objects"])
    after = inventory(conn)

    payload = {
        "started_from_object_count": before["object_count"],
        "foreign_key_results": fk_results,
        "object_results": object_results,
        "remaining_object_count": after["object_count"],
        "remaining_objects": after["objects"],
    }
    write_json(out_dir / "sql_cleanup_results.json", payload)
    write_json(out_dir / "sql_inventory_post_cleanup.json", after)

    failed = [r for r in fk_results + object_results if r["status"] in {"failed", "unsupported"}]
    print(
        json.dumps(
            {
                "mode": args.mode,
                "started_from_object_count": before["object_count"],
                "remaining_object_count": after["object_count"],
                "failed_count": len(failed),
            },
            sort_keys=True,
        )
    )
    return 0 if after["object_count"] == 0 and not failed else 2


if __name__ == "__main__":
    raise SystemExit(main())
