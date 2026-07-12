#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SQL_SERVER = os.getenv("FABRIC_SQL_SERVER", "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com")
SQL_COPT_SS_ACCESS_TOKEN = 1256
REF_TABLES = [
    "Calendar",
    "CustomerAccount",
    "CustomerAccountGroup",
    "CustomerGrouping",
    "CustomerShippingLocation",
    "ForecastCycle",
    "ForecastHorizon",
    "ItemMaster",
    "OrderType",
    "Vendor",
    "Warehouse",
]
GOLD_SCHEMAS = {"Shared_DW", "ForecastAccuracy_DW", "InventoryHealth_DW"}


@dataclass(frozen=True)
class Target:
    mart: str
    step: int
    wave: str
    database: str
    schema: str
    table: str
    load_type: str


def get_db_token() -> str:
    r = subprocess.run(
        ["az", "account", "get-access-token", "--resource", "https://database.windows.net/", "--query", "accessToken", "-o", "tsv"],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if r.returncode != 0:
        raise RuntimeError(f"az token failed: {r.stderr.strip()}")
    return r.stdout.strip()


def connect(database: str):
    import pyodbc

    token = get_db_token()
    raw = token.encode("UTF-16-LE")
    token_attr = struct.pack(f"<I{len(raw)}s", len(raw), raw)
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SQL_SERVER};DATABASE={database};Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_attr},
        timeout=300,
        autocommit=True,
    )


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def target_database(schema: str) -> str:
    return "SupplyChain_Gold_Warehouse" if schema in GOLD_SCHEMAS else "SupplyChain_Processing_Warehouse"


def expand_targets(mart: str, manifest: dict[str, Any]) -> list[Target]:
    out: list[Target] = []
    for row in sorted(manifest["sequence"], key=lambda item: item["step"]):
        obj = row["object"]
        if obj.startswith("04_semantic/"):
            continue
        objects = [f"ReferenceMaster_Enh.{name}" for name in REF_TABLES] if obj == "ReferenceMaster_Enh.*" else [obj]
        for full in objects:
            schema, table = full.split(".", 1)
            out.append(Target(
                mart=mart,
                step=int(row["step"]),
                wave=str(row["wave"]),
                database=target_database(schema),
                schema=schema,
                table=table,
                load_type=str(row.get("load_type", "overwrite")),
            ))
    return out


def exec_target(target: Target) -> tuple[bool, str, float]:
    import pyodbc

    proc = "usp_IncrementalTableLoad" if target.load_type == "incremental" else "usp_RefreshCuratedTableFromView"
    if proc == "usp_IncrementalTableLoad":
        sql = (
            "EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad] "
            f"'{target.database}', '{target.schema}', '{target.table}', 'NULL'"
        )
    else:
        sql = (
            "EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] "
            f"'{target.database}', '{target.schema}', '{target.table}'"
        )

    start = time.time()
    try:
        conn = connect(target.database)
        cur = conn.cursor()
        cur.execute("SET LOCK_TIMEOUT 300000")
        cur.execute(sql)
        result_sets = 0
        while True:
            try:
                cur.fetchall()
            except pyodbc.ProgrammingError:
                pass
            result_sets += 1
            if not cur.nextset():
                break
        conn.close()
        return True, f"OK {result_sets} result_sets", time.time() - start
    except Exception as exc:
        return False, str(exc), time.time() - start


def latest_audit(target: Target) -> tuple[Any, Any, Any, Any, Any]:
    conn = connect("ETL_Framework")
    cur = conn.cursor()
    like = f"%{target.database}.{target.schema}.{target.table}%"
    audit = cur.execute(
        """
        SELECT
            MAX(CASE WHEN Command = 'Process Start' THEN [DateTime] END) AS latest_start,
            MAX(CASE WHEN Command = 'Process Complete' THEN [DateTime] END) AS latest_complete,
            MAX(CASE WHEN Command NOT IN ('Process Start','Process Complete') THEN [DateTime] END) AS latest_error,
            MAX(CASE WHEN Command NOT IN ('Process Start','Process Complete') THEN LEFT(Command, 500) END) AS error_text
        FROM DW_Developer.AuditLog
        WHERE Description LIKE ?
        """,
        like,
    ).fetchone()
    td = cur.execute(
        """
        SELECT MAX(Modified) AS modified_at
        FROM DW_Developer.TableDictionary
        WHERE DatabaseName = ? AND SchemaName = ? AND TableName = ?
        """,
        target.database,
        target.schema,
        target.table,
    ).fetchone()
    conn.close()
    return audit.latest_start, audit.latest_complete, audit.latest_error, audit.error_text, td.modified_at


def row_count(database: str, schema: str, table: str) -> Any:
    conn = connect(database)
    cur = conn.cursor()
    value = cur.execute(f"SELECT COUNT_BIG(*) FROM [{schema}].[{table}]").fetchone()[0]
    conn.close()
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Run mart refresh table-by-table, no Fabric pipelines and no wrapper SPs.")
    parser.add_argument("--manifest", action="append", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    all_targets: list[Target] = []
    for path in args.manifest:
        manifest = load_manifest(path)
        all_targets.extend(expand_targets(manifest["name"], manifest))

    print("dry_run=" + str(not args.execute).lower())
    for idx, t in enumerate(all_targets, 1):
        proc = "usp_IncrementalTableLoad" if t.load_type == "incremental" else "usp_RefreshCuratedTableFromView"
        print(f"{idx:03d} | {t.mart:<18} | step={t.step:<3} | wave={t.wave:<16} | {t.database}.{t.schema}.{t.table} | {proc}")

    if not args.execute:
        return 0

    completed: list[Target] = []
    for idx, t in enumerate(all_targets, 1):
        label = f"{idx:03d} {t.mart} {t.database}.{t.schema}.{t.table}"
        print(f"RUN {label}", flush=True)
        ok, message, elapsed = exec_target(t)
        latest_start, latest_complete, latest_error, error_text, modified_at = latest_audit(t)
        clean = bool(latest_start and latest_complete and latest_complete >= latest_start and (modified_at is None or modified_at >= latest_complete))
        status = "OK" if ok and clean else "FAIL"
        print(
            f"{status} {label} elapsed={elapsed:.1f}s audit_start={latest_start} audit_complete={latest_complete} modified={modified_at} message={message}",
            flush=True,
        )
        if latest_error and (not latest_complete or latest_error >= latest_start):
            print(f"ERROR_LOG {label} error_at={latest_error} error={error_text}", flush=True)
        if not ok or not clean:
            print("STOP_ON_FIRST_ERROR", flush=True)
            return 1
        completed.append(t)

    print(f"ALL_OK tables={len(completed)}")
    for db, schema, table in [
        ("SupplyChain_Gold_Warehouse", "ForecastAccuracy_DW", "FactForecastActual"),
        ("SupplyChain_Gold_Warehouse", "ForecastAccuracy_DW", "FactForecastKpi"),
        ("SupplyChain_Gold_Warehouse", "InventoryHealth_DW", "FactInventoryHealthFutureWeekEnding"),
        ("SupplyChain_Gold_Warehouse", "InventoryHealth_DW", "FactInventoryHealthSnapshot"),
    ]:
        print(f"ROWCOUNT {db}.{schema}.{table} rows={row_count(db, schema, table)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
