#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import struct
import subprocess
from pathlib import Path
from typing import Any, Iterable

import pyodbc


SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)
DATABASE = "SupplyChain_Processing_Warehouse"
LAKEHOUSE = "Enterprise_Lakehouse"
SCHEMA = "Inventory_Enh_History"
TABLE = "ItemBalance"


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


def connect() -> pyodbc.Connection:
    token = _az_token("https://database.windows.net/")
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER=tcp:{SERVER},1433;"
        f"DATABASE={DATABASE};"
        "Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        autocommit=True,
    )


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def _as_iso(v: Any) -> str | None:
    if v is None:
        return None
    if isinstance(v, dt.datetime):
        return v.date().isoformat()
    if isinstance(v, dt.date):
        return v.isoformat()
    return str(v)


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return

    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: _as_iso(v) for k, v in r.items()})


def _in_params(values: Iterable[Any]) -> tuple[str, list[Any]]:
    values = list(values)
    if not values:
        raise ValueError("dates list must not be empty")
    return ", ".join(["?"] * len(values)), values


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--dates",
        nargs="+",
        default=["2025-07-26", "2023-09-16"],
        help="DateWeekEnding values (YYYY-MM-DD) to extract dup details from",
    )
    ap.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent),
        help="Output folder (defaults to this script directory)",
    )
    args = ap.parse_args()

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    table_fq = f"[{LAKEHOUSE}].[{SCHEMA}].[{TABLE}]"
    in_sql, in_vals = _in_params(args.dates)

    with connect() as cn:
        cur = cn.cursor()

        # Full-row dup groups (within selected dates)
        sql_full_groups = f"""
            SELECT
                ItemNumber,
                Warehouse,
                DateWeekEnding,
                OnHandQty,
                ItemStatus,
                COUNT_BIG(*) AS cnt
            FROM {table_fq}
            WHERE DateWeekEnding IN ({in_sql})
            GROUP BY ItemNumber, Warehouse, DateWeekEnding, OnHandQty, ItemStatus
            HAVING COUNT_BIG(*) > 1
            ORDER BY cnt DESC, DateWeekEnding, ItemNumber, Warehouse;
        """
        cur.execute(sql_full_groups, tuple(in_vals))
        full_groups = rows_as_dicts(cur)
        _write_csv(out_dir / "full_row_dups_groups.csv", full_groups)

        # Full-row dup rows (materialize both copies)
        sql_full_rows = f"""
            WITH base AS (
                SELECT
                    ItemNumber,
                    Warehouse,
                    DateWeekEnding,
                    OnHandQty,
                    ItemStatus,
                    CONCAT('[', ItemNumber, ']') AS ItemNumber_bracket,
                    CONCAT('[', Warehouse, ']') AS Warehouse_bracket,
                    CONCAT('[', ItemStatus, ']') AS ItemStatus_bracket,
                    LEN(ItemNumber) AS ItemNumber_len,
                    DATALENGTH(ItemNumber) AS ItemNumber_bytes,
                    LEN(Warehouse) AS Warehouse_len,
                    DATALENGTH(Warehouse) AS Warehouse_bytes,
                    LEN(ItemStatus) AS ItemStatus_len,
                    DATALENGTH(ItemStatus) AS ItemStatus_bytes,
                    ROW_NUMBER() OVER (
                        PARTITION BY ItemNumber, Warehouse, DateWeekEnding, OnHandQty, ItemStatus
                        ORDER BY (SELECT NULL)
                    ) AS rn,
                    COUNT_BIG(*) OVER (
                        PARTITION BY ItemNumber, Warehouse, DateWeekEnding, OnHandQty, ItemStatus
                    ) AS cnt
                FROM {table_fq}
                WHERE DateWeekEnding IN ({in_sql})
            )
            SELECT *
            FROM base
            WHERE cnt > 1
            ORDER BY DateWeekEnding, ItemNumber, Warehouse, rn;
        """
        cur.execute(sql_full_rows, tuple(in_vals))
        full_rows = rows_as_dicts(cur)
        _write_csv(out_dir / "full_row_dups_rows.csv", full_rows)

        # Grain dup groups (trim keys)
        sql_grain_groups = f"""
            WITH base AS (
                SELECT
                    LTRIM(RTRIM(ItemNumber)) AS ItemNumber_trim,
                    LTRIM(RTRIM(Warehouse)) AS Warehouse_trim,
                    DateWeekEnding,
                    ItemNumber,
                    Warehouse,
                    OnHandQty,
                    ItemStatus
                FROM {table_fq}
                WHERE DateWeekEnding IN ({in_sql})
            )
            SELECT
                ItemNumber_trim,
                Warehouse_trim,
                DateWeekEnding,
                COUNT_BIG(*) AS cnt,
                COUNT(DISTINCT ItemNumber) AS distinct_itemnumber_raw,
                COUNT(DISTINCT Warehouse) AS distinct_warehouse_raw,
                COUNT(DISTINCT OnHandQty) AS distinct_onhandqty,
                COUNT(DISTINCT ItemStatus) AS distinct_itemstatus
            FROM base
            GROUP BY ItemNumber_trim, Warehouse_trim, DateWeekEnding
            HAVING COUNT_BIG(*) > 1
            ORDER BY DateWeekEnding, ItemNumber_trim, Warehouse_trim;
        """
        cur.execute(sql_grain_groups, tuple(in_vals))
        grain_groups = rows_as_dicts(cur)
        _write_csv(out_dir / "grain_dups_groups.csv", grain_groups)

        # Grain dup rows (2 rows per grain key expected)
        sql_grain_rows = f"""
            WITH base AS (
                SELECT
                    LTRIM(RTRIM(ItemNumber)) AS ItemNumber_trim,
                    LTRIM(RTRIM(Warehouse)) AS Warehouse_trim,
                    DateWeekEnding,
                    ItemNumber,
                    Warehouse,
                    OnHandQty,
                    ItemStatus,
                    CONCAT('[', ItemNumber, ']') AS ItemNumber_bracket,
                    CONCAT('[', Warehouse, ']') AS Warehouse_bracket,
                    CONCAT('[', ItemStatus, ']') AS ItemStatus_bracket,
                    LEN(ItemNumber) AS ItemNumber_len,
                    DATALENGTH(ItemNumber) AS ItemNumber_bytes,
                    LEN(Warehouse) AS Warehouse_len,
                    DATALENGTH(Warehouse) AS Warehouse_bytes,
                    LEN(ItemStatus) AS ItemStatus_len,
                    DATALENGTH(ItemStatus) AS ItemStatus_bytes,
                    ROW_NUMBER() OVER (
                        PARTITION BY LTRIM(RTRIM(ItemNumber)), LTRIM(RTRIM(Warehouse)), DateWeekEnding
                        ORDER BY (SELECT NULL)
                    ) AS rn,
                    COUNT_BIG(*) OVER (
                        PARTITION BY LTRIM(RTRIM(ItemNumber)), LTRIM(RTRIM(Warehouse)), DateWeekEnding
                    ) AS cnt
                FROM {table_fq}
                WHERE DateWeekEnding IN ({in_sql})
            )
            SELECT *
            FROM base
            WHERE cnt > 1
            ORDER BY DateWeekEnding, ItemNumber_trim, Warehouse_trim, rn;
        """
        cur.execute(sql_grain_rows, tuple(in_vals))
        grain_rows = rows_as_dicts(cur)
        _write_csv(out_dir / "grain_dups_rows.csv", grain_rows)

    print(f"[ok] wrote: {out_dir / 'full_row_dups_groups.csv'}")
    print(f"[ok] wrote: {out_dir / 'full_row_dups_rows.csv'}")
    print(f"[ok] wrote: {out_dir / 'grain_dups_groups.csv'}")
    print(f"[ok] wrote: {out_dir / 'grain_dups_rows.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

