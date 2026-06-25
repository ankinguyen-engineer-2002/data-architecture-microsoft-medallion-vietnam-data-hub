#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pyodbc


SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)
ETL_DB = "ETL_Framework"


@dataclass(frozen=True)
class ProcRef:
    schema: str
    name: str


def _az_token(resource: str) -> str:
    return (
        subprocess.check_output(
            [
                "az",
                "account",
                "get-access-token",
                "--resource",
                resource,
                "--query",
                "accessToken",
                "-o",
                "tsv",
            ],
            text=True,
        )
        .strip()
    )


def connect(database: str) -> pyodbc.Connection:
    token = _az_token("https://database.windows.net/")
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER=tcp:{SERVER},1433;"
        f"DATABASE={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;",
        attrs_before={1256: token_struct},
        autocommit=True,
    )


def fetch_proc_definition(conn: pyodbc.Connection, proc: ProcRef) -> str:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE s.name = ? AND o.name = ?;
        """,
        (proc.schema, proc.name),
    )
    row = cur.fetchone()
    cur.close()
    if not row or not row[0]:
        raise RuntimeError(f"Missing proc definition for {proc.schema}.{proc.name}")
    return str(row[0])


def _to_lf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").lstrip("\ufeff")


def replace_create_with_alter(definition: str) -> str:
    text = _to_lf(definition)
    if text.lstrip().upper().startswith("CREATE PROC"):
        return re.sub(r"^\s*CREATE\s+PROC", "ALTER PROC", text, count=1, flags=re.IGNORECASE)
    if text.lstrip().upper().startswith("CREATE PROCEDURE"):
        return re.sub(r"^\s*CREATE\s+PROCEDURE", "ALTER PROCEDURE", text, count=1, flags=re.IGNORECASE)
    raise RuntimeError("Unexpected proc header (expected CREATE PROC/PROCEDURE)")


def patch_remove_as_insertcolumns(definition: str) -> str:
    text = _to_lf(definition)
    if "auto-patch: compute @InsertColumns" not in text:
        raise RuntimeError("InsertColumns auto-patch marker not found; aborting.")

    before = text
    text = text.replace(
        "WITHIN GROUP (ORDER BY column_id) AS InsertColumns ",
        "WITHIN GROUP (ORDER BY column_id) ",
    )
    if text == before:
        raise RuntimeError("No change applied (pattern not found).")
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", default="DW_Developer")
    parser.add_argument("--name", default="usp_IncrementalTableLoad")
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    proc = ProcRef(schema=args.schema, name=args.name)
    conn = connect(ETL_DB)
    try:
        current = fetch_proc_definition(conn, proc)
    finally:
        conn.close()

    altered = replace_create_with_alter(current)
    patched = patch_remove_as_insertcolumns(altered)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(patched, encoding="utf-8")

    if args.apply:
        conn = connect(ETL_DB)
        cur = conn.cursor()
        try:
            cur.execute(patched)
        finally:
            cur.close()
            conn.close()

    print({"proc": f"{proc.schema}.{proc.name}", "out": str(args.out) if args.out else None, "apply": bool(args.apply)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

