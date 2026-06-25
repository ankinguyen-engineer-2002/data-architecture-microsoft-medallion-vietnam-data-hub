#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
import subprocess
from dataclasses import dataclass
from typing import Any, Iterable

import pyodbc


SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)
ETL_DB = "ETL_Framework"


@dataclass(frozen=True)
class IncrementalTarget:
    database: str
    schema: str
    table: str
    operation_name: str

    @property
    def description(self) -> str:
        if self.operation_name.strip().upper() == "NULL":
            return f"{self.database}.{self.schema}.{self.table}"
        return f"{self.database}.{self.schema}.{self.table} ({self.operation_name})"


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


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def run(cur: pyodbc.Cursor, sql: str, params: Iterable[Any] = ()) -> None:
    cur.execute(sql, tuple(params))


def repro(target: IncrementalTarget) -> dict[str, Any]:
    exec_error: str | None = None
    exec_ok = False

    conn = connect(ETL_DB)
    cur = conn.cursor()
    try:
        run(
            cur,
            "EXEC DW_Developer.usp_IncrementalTableLoad ?, ?, ?, ?",
            (target.database, target.schema, target.table, target.operation_name),
        )
        while True:
            try:
                cur.fetchall()
            except pyodbc.ProgrammingError:
                pass
            if not cur.nextset():
                break
        exec_ok = True
    except Exception as e:  # noqa: BLE001
        exec_error = str(e)
    finally:
        cur.close()
        conn.close()

    conn = connect(ETL_DB)
    cur = conn.cursor()
    try:
        run(
            cur,
            """
            SELECT TOP (10)
                Description,
                DateTime,
                [User],
                Command
            FROM DW_Developer.AuditLog
            WHERE Description = ?
            ORDER BY DateTime DESC;
            """,
            (target.description,),
        )
        audit_tail = rows_as_dicts(cur)
    finally:
        cur.close()
        conn.close()

    return {
        "target": {
            "database": target.database,
            "schema": target.schema,
            "table": target.table,
            "operation_name": target.operation_name,
            "audit_description": target.description,
        },
        "exec_ok": exec_ok,
        "exec_error": exec_error,
        "audit_tail": audit_tail,
    }


def _is_error_3930(message: str | None) -> bool:
    if not message:
        return False
    lowered = message.lower()
    return "(3930)" in message or " 3930" in message or "write to the log file" in lowered


def _has_audit_error_row(audit_tail: list[dict[str, Any]]) -> bool:
    for row in audit_tail:
        cmd = str(row.get("Command") or "")
        if cmd and cmd not in {"Process Start", "Process Complete"}:
            return True
    return False


def _is_missing_metadata_error(message: str | None) -> bool:
    if not message:
        return False
    return "missing values in metadata for data feed to" in message.lower()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", default="SupplyChain_Processing_Warehouse")
    parser.add_argument("--schema", default="InventoryHistory_Enh")
    parser.add_argument("--table", default="HoldingTransferSnapshotDaily")
    parser.add_argument("--operation-name", default="NULL")
    parser.add_argument(
        "--assert-unmasked",
        action="store_true",
        help="Exit 0 only if the failure is not masked by 3930 and an AuditLog error row is written.",
    )
    parser.add_argument(
        "--assert-no-metadata-error",
        action="store_true",
        help="Exit 0 only if execution succeeds or the error is not 'Missing values in Metadata...'.",
    )
    args = parser.parse_args()

    result = repro(
        IncrementalTarget(
            database=args.database,
            schema=args.schema,
            table=args.table,
            operation_name=args.operation_name,
        )
    )

    print(result)
    if not (args.assert_unmasked or args.assert_no_metadata_error):
        return 0 if result["exec_ok"] else 2

    if not result["exec_ok"] and args.assert_unmasked:
        if _is_error_3930(result.get("exec_error")):
            return 2
        if not _has_audit_error_row(result.get("audit_tail") or []):
            return 2

    if not result["exec_ok"] and args.assert_no_metadata_error:
        if _is_missing_metadata_error(result.get("exec_error")):
            return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
