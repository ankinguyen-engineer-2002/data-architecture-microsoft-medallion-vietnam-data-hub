#!/usr/bin/env python3
"""Read-only freshness RANGE audit for active Bronze Enterprise_Lakehouse sources.

Supplements the existing latest-partition DQ audit with a historical depth check:
for every Bronze source that exposes at least one date/datetime-like freshness
column, capture MIN/MAX per freshness column and decide whether the table spans
the minimum required window (2023-01-01 -> first day of current month).

Pass criterion (per table):
    At least ONE freshness column has normalized MIN <= 2023-01-01
    AND normalized MAX >= 2026-06-01 (current-month floor).

Tables without freshness columns: NOT_APPLICABLE for this specific check
(previous audit PASS/REVIEW status is preserved separately).

Numeric date formats normalized:
    7-digit  CYYMMDD   (century digit: 0=19xx, 1=20xx, 2=21xx)
    8-digit  CCYYMMDD  (standard)
    6-digit  YYMMDD    (assume 20xx)
    Sentinel values 0, 9999999, 99999999 -> None
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Any

import pyodbc

ROOT = Path(__file__).resolve().parents[2]
SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Processing_Warehouse"
LAKEHOUSE = "Enterprise_Lakehouse"

CONTRACT_PATHS = [
    ROOT / "02_marts/inventory_health/04_dq/contracts/bronze_sources.json",
    ROOT / "02_marts/forecast_accuracy/04_dq/contracts/bronze_sources.json",
]

# Extra table seen in the prior audit report but not in mart contracts.
EXTRA_REFS = [
    {
        "asset_key": "enterprise_lakehouse.supplychain_enh.supplyplandetailsnapshotweekly",
        "display": "Enterprise_Lakehouse.SupplyChain_Enh.SupplyPlanDetailSnapshotWeekly",
        "freshness_columns": ["dtea", "spdWeekEnding"],
        "key_columns": ["dtea", "spdItem", "spdWarehouse", "spdWeekEnding"],
        "marts": ["requested_extra"],
    },
]

# Pass-window floor (user-specified minimum historical depth).
MIN_FLOOR_DATE = dt.date(2023, 1, 1)
MAX_FLOOR_DATE = dt.date(2026, 6, 1)

# Sentinels that represent null/placeholder dates in Mapics numeric date columns.
NUMERIC_DATE_SENTINELS = {0, 9999999, 99999999, 999999, 99999}


# --------------------------------------------------------------------------- #
# Connection helpers (mirror audit_bronze_source_dq.py)
# --------------------------------------------------------------------------- #

def az_token(resource: str) -> str:
    return subprocess.check_output(
        [
            "az", "account", "get-access-token",
            "--resource", resource,
            "--query", "accessToken",
            "-o", "tsv",
        ],
        text=True,
    ).strip()


def connect(database: str = DATABASE) -> pyodbc.Connection:
    token = az_token("https://database.windows.net/").encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token)}s", len(token), token)
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{SERVER},1433;"
        f"DATABASE={database};"
        "Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        autocommit=True,
    )


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


# --------------------------------------------------------------------------- #
# Ref / contract loading
# --------------------------------------------------------------------------- #

@dataclass(frozen=True, order=True)
class Ref:
    db: str
    schema: str
    table: str

    @property
    def full(self) -> str:
        return f"{self.db}.{self.schema}.{self.table}"

    @property
    def short(self) -> str:
        return f"{self.schema}.{self.table}"

    @property
    def sql(self) -> str:
        return f"[{self.db}].[{self.schema}].[{self.table}]"


@dataclass
class SourceContract:
    ref: Ref
    marts: list[str]
    freshness_columns: list[str]
    key_columns: list[str]
    previous_dq_status: str
    display: str


def parse_display(display: str) -> Ref:
    parts = [p.strip(" []") for p in display.split(".") if p.strip()]
    if len(parts) == 3:
        return Ref(parts[0], parts[1], parts[2])
    if len(parts) == 2:
        return Ref(LAKEHOUSE, parts[0], parts[1])
    raise ValueError(f"Cannot parse display: {display}")


def load_contracts() -> dict[Ref, SourceContract]:
    sources: dict[Ref, SourceContract] = {}
    for path in CONTRACT_PATHS:
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        mart = data.get("mart", "unknown")
        for src in data.get("sources", []):
            ref = parse_display(src["display"])
            existing = sources.get(ref)
            marts = sorted(set((existing.marts if existing else []) + [mart]))
            freshness_columns = src.get("freshness_columns") or []
            key_columns = src.get("key_columns") or []
            # Union freshness/key columns if same table appears in both marts.
            if existing:
                freshness_columns = sorted(set(existing.freshness_columns + freshness_columns))
                key_columns = sorted(set(existing.key_columns + key_columns))
            sources[ref] = SourceContract(
                ref=ref,
                marts=marts,
                freshness_columns=freshness_columns,
                key_columns=key_columns,
                previous_dq_status=src.get("dq_status", "UNKNOWN"),
                display=src["display"],
            )
    # Add extras not in contracts.
    for extra in EXTRA_REFS:
        ref = parse_display(extra["display"])
        existing = sources.get(ref)
        marts = sorted(set((existing.marts if existing else []) + extra["marts"]))
        freshness_columns = sorted(set((existing.freshness_columns if existing else []) + extra["freshness_columns"]))
        key_columns = sorted(set((existing.key_columns if existing else []) + extra["key_columns"]))
        sources[ref] = SourceContract(
            ref=ref,
            marts=marts,
            freshness_columns=freshness_columns,
            key_columns=key_columns,
            previous_dq_status="EXTRA",
            display=extra["display"],
        )
    return sources


# --------------------------------------------------------------------------- #
# Column type lookup
# --------------------------------------------------------------------------- #

def fetch_column_types(conn: pyodbc.Connection, ref: Ref) -> dict[str, str]:
    sql = """
        SELECT COLUMN_NAME AS column_name, DATA_TYPE AS data_type
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
    """
    cur = conn.cursor()
    cur.execute(sql, (ref.schema, ref.table))
    return {row[0]: str(row[1]).lower() for row in cur.fetchall()}


def table_exists(conn: pyodbc.Connection, ref: Ref) -> bool:
    sql = """
        SELECT COUNT_BIG(*)
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?;
    """
    cur = conn.cursor()
    cur.execute(sql, (ref.schema, ref.table))
    return bool(cur.fetchone()[0])


# --------------------------------------------------------------------------- #
# Date normalization
# --------------------------------------------------------------------------- #

def normalize_date_value(value: Any, *, data_type: str) -> dt.date | None:
    """Normalize a raw SQL value to a date, or None if sentinel/unknown."""
    if value is None:
        return None
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    if isinstance(value, Decimal):
        value = int(value)
    if isinstance(value, int):
        if value in NUMERIC_DATE_SENTINELS:
            return None
        s = str(value)
        try:
            if len(s) == 8:  # CCYYMMDD
                year, month, day = int(s[0:4]), int(s[4:6]), int(s[6:8])
            elif len(s) == 7:  # CYYMMDD (century digit)
                century = int(s[0])
                year = 1900 + century * 100 + int(s[1:3])
                month, day = int(s[3:5]), int(s[5:7])
            elif len(s) == 6:  # YYMMDD (assume 20xx)
                year, month, day = 2000 + int(s[0:2]), int(s[2:4]), int(s[4:6])
            else:
                return None
            return dt.date(year, month, day)
        except (ValueError, IndexError):
            return None
    if isinstance(value, str):
        s = value.strip()
        if not s or s in {"0", "9999999", "99999999"}:
            return None
        for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%Y/%m/%d", "%m/%d/%Y"):
            try:
                return dt.datetime.strptime(s, fmt).date()
            except ValueError:
                continue
        # Numeric string
        if s.isdigit():
            return normalize_date_value(int(s), data_type=data_type)
    return None


# --------------------------------------------------------------------------- #
# Range audit
# --------------------------------------------------------------------------- #

@dataclass
class ColumnRange:
    column: str
    data_type: str
    raw_min: Any = None
    raw_max: Any = None
    norm_min: dt.date | None = None
    norm_max: dt.date | None = None
    status: str = "PASS"
    error: str | None = None
    seconds: float | None = None


@dataclass
class TableRangeAudit:
    ref: Ref
    marts: list[str]
    display: str
    exists: bool
    previous_dq_status: str
    freshness_columns: list[str]
    key_columns: list[str]
    column_ranges: list[ColumnRange] = field(default_factory=list)
    table_error: str | None = None

    @property
    def range_pass(self) -> str:
        if not self.exists:
            return "MISSING"
        if self.table_error:
            return "ERROR"
        if not self.freshness_columns:
            return "NOT_APPLICABLE"
        # Need at least one column with a valid MIN and MAX.
        candidates = [c for c in self.column_ranges if c.norm_min and c.norm_max]
        if not candidates:
            return "NO_VALID_DATES"
        for c in candidates:
            if c.norm_min <= MIN_FLOOR_DATE and c.norm_max >= MAX_FLOOR_DATE:
                return "PASS"
        return "FAIL"

    @property
    def best_span_days(self) -> int | None:
        best: int | None = None
        for c in self.column_ranges:
            if c.norm_min and c.norm_max and c.norm_max > c.norm_min:
                span = (c.norm_max - c.norm_min).days
                if best is None or span > best:
                    best = span
        return best


def query_min_max(conn: pyodbc.Connection, ref: Ref, col: str, *, data_type: str, timeout_seconds: int) -> ColumnRange:
    # For numeric date columns (Mapics CYYMMDD/CCYYMMDD), filter out sentinels
    # 0, 9999999, 99999999 that represent "no date" before aggregating.
    numeric_types = {"int", "bigint", "smallint", "tinyint", "decimal", "numeric", "float", "real"}
    if data_type in numeric_types:
        expr = f"NULLIF(NULLIF(NULLIF([{col}], 0), 9999999), 99999999)"
    else:
        expr = f"[{col}]"
    sql = f"SELECT MIN({expr}) AS min_v, MAX({expr}) AS max_v FROM {ref.sql};"
    cur = conn.cursor()
    try:
        cur.timeout = timeout_seconds
    except AttributeError:
        pass
    t0 = time.monotonic()
    try:
        cur.execute(sql)
        row = cur.fetchone()
        return ColumnRange(
            column=col,
            data_type=data_type,
            raw_min=row[0],
            raw_max=row[1],
            seconds=round(time.monotonic() - t0, 3),
        )
    except Exception as exc:  # noqa: BLE001
        return ColumnRange(
            column=col,
            data_type=data_type,
            status="ERROR",
            error=str(exc),
            seconds=round(time.monotonic() - t0, 3),
        )


def audit_table(conn: pyodbc.Connection, contract: SourceContract) -> TableRangeAudit:
    audit = TableRangeAudit(
        ref=contract.ref,
        marts=contract.marts,
        display=contract.display,
        exists=False,
        previous_dq_status=contract.previous_dq_status,
        freshness_columns=contract.freshness_columns,
        key_columns=contract.key_columns,
    )
    try:
        audit.exists = table_exists(conn, contract.ref)
        if not audit.exists:
            return audit
        if not contract.freshness_columns:
            return audit
        col_types = fetch_column_types(conn, contract.ref)
        for col in contract.freshness_columns:
            dtype = col_types.get(col.lower()) or col_types.get(col) or ""
            # Re-lookup case-insensitive
            if not dtype:
                for k, v in col_types.items():
                    if k.lower() == col.lower():
                        dtype = v
                        break
            cr = query_min_max(conn, contract.ref, col, data_type=dtype, timeout_seconds=300)
            cr.data_type = dtype
            cr.norm_min = normalize_date_value(cr.raw_min, data_type=dtype)
            cr.norm_max = normalize_date_value(cr.raw_max, data_type=dtype)
            audit.column_ranges.append(cr)
    except Exception as exc:  # noqa: BLE001
        audit.table_error = str(exc)
    return audit


# --------------------------------------------------------------------------- #
# Serialization
# --------------------------------------------------------------------------- #

def serialize_value(v: Any) -> Any:
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ", timespec="seconds")
    if isinstance(v, dt.date):
        return v.isoformat()
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else str(v)
    return v


def audit_to_dict(audit: TableRangeAudit) -> dict[str, Any]:
    return {
        "ref": audit.ref.full,
        "display": audit.display,
        "marts": audit.marts,
        "previous_dq_status": audit.previous_dq_status,
        "exists": audit.exists,
        "freshness_columns": audit.freshness_columns,
        "key_columns": audit.key_columns,
        "range_pass": audit.range_pass,
        "best_span_days": audit.best_span_days,
        "table_error": audit.table_error,
        "column_ranges": [
            {
                "column": c.column,
                "data_type": c.data_type,
                "raw_min": serialize_value(c.raw_min),
                "raw_max": serialize_value(c.raw_max),
                "norm_min": c.norm_min.isoformat() if c.norm_min else None,
                "norm_max": c.norm_max.isoformat() if c.norm_max else None,
                "status": c.status,
                "error": c.error,
                "seconds": c.seconds,
            }
            for c in audit.column_ranges
        ],
    }


# --------------------------------------------------------------------------- #
# Report writers
# --------------------------------------------------------------------------- #

def write_reports(audits: list[TableRangeAudit], out_dir: Path, metadata: dict[str, Any]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "metadata": metadata,
        "pass_window": {
            "min_floor": MIN_FLOOR_DATE.isoformat(),
            "max_floor": MAX_FLOOR_DATE.isoformat(),
        },
        "tables": [audit_to_dict(a) for a in audits],
    }
    (out_dir / "freshness_range_results.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # CSV
    csv_fields = [
        "range_pass",
        "previous_dq_status",
        "ref",
        "marts",
        "freshness_columns",
        "best_column",
        "norm_min",
        "norm_max",
        "span_days",
        "table_error",
    ]
    with (out_dir / "freshness_range_results.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for a in audits:
            best_col = None
            best_span = None
            for c in a.column_ranges:
                if c.norm_min and c.norm_max and c.norm_max > c.norm_min:
                    span = (c.norm_max - c.norm_min).days
                    if best_span is None or span > best_span:
                        best_span = span
                        best_col = c
            writer.writerow({
                "range_pass": a.range_pass,
                "previous_dq_status": a.previous_dq_status,
                "ref": a.ref.full,
                "marts": ";".join(a.marts),
                "freshness_columns": ";".join(a.freshness_columns),
                "best_column": best_col.column if best_col else "",
                "norm_min": best_col.norm_min.isoformat() if best_col and best_col.norm_min else "",
                "norm_max": best_col.norm_max.isoformat() if best_col and best_col.norm_max else "",
                "span_days": best_span if best_span is not None else "",
                "table_error": a.table_error or "",
            })

    # Markdown
    counts: dict[str, int] = {}
    for a in audits:
        counts[a.range_pass] = counts.get(a.range_pass, 0) + 1

    lines = [
        "# Bronze Source Freshness RANGE Audit",
        "",
        f"- Generated at ICT: `{metadata['generated_at_ict']}`",
        f"- Server: `{metadata['server']}`",
        f"- Lakehouse: `{metadata['lakehouse']}`",
        f"- Tables audited: `{len(audits)}`",
        f"- Pass window (minimum required historical depth): "
        f"`{MIN_FLOOR_DATE.isoformat()}` -> `{MAX_FLOOR_DATE.isoformat()}`",
        "",
        "## Status Summary",
        "",
        "| Status | Count | Meaning |",
        "|---|---:|---|",
        f"| `PASS` | {counts.get('PASS', 0)} | At least one freshness column spans the required window. |",
        f"| `FAIL` | {counts.get('FAIL', 0)} | Has freshness columns but none spans the required window. |",
        f"| `NOT_APPLICABLE` | {counts.get('NOT_APPLICABLE', 0)} | No freshness columns; range check does not apply. |",
        f"| `NO_VALID_DATES` | {counts.get('NO_VALID_DATES', 0)} | Freshness columns exist but no MIN/MAX produced usable dates. |",
        f"| `MISSING` | {counts.get('MISSING', 0)} | Table not found on Enterprise_Lakehouse. |",
        f"| `ERROR` | {counts.get('ERROR', 0)} | Query/audit error. |",
        "",
        "## Detail",
        "",
        "| # | Range | Prev DQ | Table | Marts | Best column | MIN | MAX | Span days | Notes |",
        "|---:|---|---|---|---|---|---|---|---:|---|",
    ]
    for idx, a in enumerate(audits, start=1):
        best_col = None
        best_span = None
        for c in a.column_ranges:
            if c.norm_min and c.norm_max and c.norm_max > c.norm_min:
                span = (c.norm_max - c.norm_min).days
                if best_span is None or span > best_span:
                    best_span = span
                    best_col = c
        notes = a.table_error or ""
        if not a.freshness_columns:
            notes = "no freshness column in contract"
        lines.append(
            "| " + " | ".join([
                str(idx),
                f"`{a.range_pass}`",
                f"`{a.previous_dq_status}`",
                f"`{a.ref.full}`",
                ", ".join(a.marts),
                best_col.column if best_col else "",
                best_col.norm_min.isoformat() if best_col and best_col.norm_min else "",
                best_col.norm_max.isoformat() if best_col and best_col.norm_max else "",
                str(best_span) if best_span is not None else "",
                notes,
            ]) + " |"
        )

    lines.extend([
        "",
        "## Per-Column Freshness Range",
        "",
    ])
    for a in audits:
        if not a.column_ranges:
            continue
        lines.append(f"### `{a.ref.full}`  —  range=`{a.range_pass}`")
        lines.append("| Column | Data type | Raw MIN | Raw MAX | Norm MIN | Norm MAX | Status |")
        lines.append("|---|---|---|---|---|---|---|")
        for c in a.column_ranges:
            lines.append("| " + " | ".join([
                c.column,
                c.data_type,
                str(serialize_value(c.raw_min)),
                str(serialize_value(c.raw_max)),
                c.norm_min.isoformat() if c.norm_min else "",
                c.norm_max.isoformat() if c.norm_max else "",
                c.status,
            ]) + " |")
        lines.append("")

    lines.extend([
        "## Interpretation Notes",
        "",
        "- Numeric date columns are normalized: 7-digit CYYMMDD (century digit), 8-digit CCYYMMDD, 6-digit YYMMDD (assumed 20xx).",
        "- Sentinel values `0`, `9999999`, `99999999` are treated as null dates.",
        "- `NOT_APPLICABLE` tables (no freshness column in the prior DQ contract) preserve their previous audit status; this check does not override them.",
        "- A `FAIL` here means the Bronze source cannot demonstrate the minimum 2023-01-01 -> 2026-06-01 historical depth. This does not automatically invalidate downstream ETL but is a data-coverage risk that DE/business should confirm.",
        "- This audit is read-only and does not modify any Fabric/SQL resource.",
    ])
    (out_dir / "freshness_range_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read-only freshness RANGE audit for active Bronze Enterprise_Lakehouse sources."
    )
    parser.add_argument(
        "--out-dir",
        default=str(ROOT / "01_docs/runbook/artifacts/20260629_bronze_source_freshness_range_audit"),
        help="Output directory for JSON/CSV/Markdown reports.",
    )
    parser.add_argument("--limit", type=int, default=0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    contracts = load_contracts()
    ordered = sorted(contracts.values(), key=lambda c: c.ref)
    if args.limit:
        ordered = ordered[: args.limit]

    metadata = {
        "generated_at_ict": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "server": SERVER,
        "database": DATABASE,
        "lakehouse": LAKEHOUSE,
        "contract_paths": [str(p) for p in CONTRACT_PATHS],
        "extra_refs": [e["display"] for e in EXTRA_REFS],
        "min_floor_date": MIN_FLOOR_DATE.isoformat(),
        "max_floor_date": MAX_FLOOR_DATE.isoformat(),
    }

    audits: list[TableRangeAudit] = []
    with connect() as conn:
        for i, contract in enumerate(ordered, start=1):
            print(f"[{i}/{len(ordered)}] {contract.ref.full} (cols={len(contract.freshness_columns)})", flush=True)
            audit = audit_table(conn, contract)
            audits.append(audit)
            write_reports(audits, out_dir, metadata)

    write_reports(audits, out_dir, metadata)
    print(out_dir / "freshness_range_report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
