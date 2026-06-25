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

    @property
    def fq_name(self) -> str:
        return f"[{self.schema}].[{self.name}]"


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
        "Encrypt=yes;TrustServerCertificate=no;",
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
    return text.replace("\r\n", "\n").replace("\r", "\n")


def patch_catch_rollback_before_audit(definition: str) -> str:
    text = _to_lf(definition)
    start = text.rfind("\nBEGIN CATCH")
    if start < 0:
        start = text.find("BEGIN CATCH")
    if start < 0:
        raise RuntimeError("BEGIN CATCH not found")

    end = text.find("END CATCH", start)
    if end < 0:
        raise RuntimeError("END CATCH not found")

    catch_block = text[start:end]
    lines = catch_block.splitlines(keepends=True)

    rollback_if_idx: int | None = None
    insert_idx: int | None = None

    for idx, line in enumerate(lines):
        if insert_idx is None and "insert into dw_developer.auditlog" in line.lower():
            insert_idx = idx
        if rollback_if_idx is None and re.match(r"^\s*IF\s+@@TRANCOUNT\s*>\s*0\b", line, flags=re.IGNORECASE):
            rollback_if_idx = idx

    if rollback_if_idx is None:
        raise RuntimeError("Rollback IF @@TRANCOUNT line not found in CATCH block")
    if rollback_if_idx + 1 >= len(lines):
        raise RuntimeError("Rollback statement line missing after IF @@TRANCOUNT > 0")
    if insert_idx is None:
        raise RuntimeError("AuditLog insert not found in CATCH block")

    rollback_lines = [lines[rollback_if_idx], lines[rollback_if_idx + 1]]
    del lines[rollback_if_idx : rollback_if_idx + 2]

    insert_idx = None
    for idx, line in enumerate(lines):
        if "insert into dw_developer.auditlog" in line.lower():
            insert_idx = idx
            break
    if insert_idx is None:
        raise RuntimeError("AuditLog insert not found in CATCH block after rollback removal")

    lines[insert_idx:insert_idx] = rollback_lines
    patched_catch = "".join(lines)
    return text[:start] + patched_catch + text[end:]


def replace_create_with_alter(definition: str, proc: ProcRef) -> str:
    text = _to_lf(definition).lstrip("\ufeff")
    if text.lstrip().upper().startswith("CREATE PROC"):
        return re.sub(r"^\s*CREATE\s+PROC", "ALTER PROC", text, count=1, flags=re.IGNORECASE)
    if text.lstrip().upper().startswith("CREATE PROCEDURE"):
        return re.sub(r"^\s*CREATE\s+PROCEDURE", "ALTER PROCEDURE", text, count=1, flags=re.IGNORECASE)
    raise RuntimeError(f"Unexpected proc header for {proc.fq_name}: expected CREATE PROC/PROCEDURE")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", default="DW_Developer")
    parser.add_argument("--name", default="usp_IncrementalTableLoad")
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--apply", action="store_true", help="Execute ALTER PROC against live ETL_Framework")
    args = parser.parse_args()

    proc = ProcRef(schema=args.schema, name=args.name)

    conn = connect(ETL_DB)
    try:
        current = fetch_proc_definition(conn, proc)
    finally:
        conn.close()

    altered = replace_create_with_alter(current, proc)
    patched = patch_catch_rollback_before_audit(altered)

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

    print(
        {
            "proc": f"{proc.schema}.{proc.name}",
            "out": str(args.out) if args.out else None,
            "apply": bool(args.apply),
            "patched_len": len(patched),
        }
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
