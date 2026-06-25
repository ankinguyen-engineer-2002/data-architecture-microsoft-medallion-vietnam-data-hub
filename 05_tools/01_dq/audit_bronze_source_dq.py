#!/usr/bin/env python3
"""Read-only DQ audit for active Bronze Enterprise_Lakehouse source tables.

The source list is derived from the current live mart scan summary, then
optionally extended with source tables that are not yet active but need
re-validation. The audit is intentionally evidence-first: every duplicate check
reports its exact grain, and heavy full-row duplicate scans are bounded.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import struct
import subprocess
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
SUMMARY_PATH = ROOT / "01_docs/runbook/artifacts/20260623_live_scan/summary.json"
OUT_DIR = ROOT / "01_docs/runbook/artifacts/20260623_bronze_source_dq_refresh"

EXTRA_REFS = [
    "Enterprise_Lakehouse.SupplyChain_Enh.SupplyPlanDetailSnapshotWeekly",
]


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
class CheckResult:
    status: str
    value: Any = None
    error: str | None = None
    seconds: float | None = None


@dataclass
class TableProfile:
    ref: Ref
    projects: list[str] = field(default_factory=list)
    exists: bool = False
    row_count_metadata: int | None = None
    column_count: int | None = None
    columns: list[dict[str, Any]] = field(default_factory=list)
    freshness: dict[str, Any] = field(default_factory=dict)
    key_columns: list[str] = field(default_factory=list)
    key_null_blank: CheckResult | None = None
    grain_duplicate: CheckResult | None = None
    full_row_duplicate: CheckResult | None = None
    latest_partition_duplicate: CheckResult | None = None
    warnings: list[str] = field(default_factory=list)


def az_token(resource: str) -> str:
    return subprocess.check_output(
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


def run_timed(
    conn: pyodbc.Connection,
    sql: str,
    *,
    timeout_seconds: int = 120,
    params: tuple[Any, ...] = (),
) -> CheckResult:
    cur = conn.cursor()
    try:
        cur.timeout = timeout_seconds
    except AttributeError:
        # Some pyodbc builds expose only connection/login timeout. Keep the
        # elapsed time in the result and use row-count guards for heavy checks.
        pass
    t0 = time.monotonic()
    try:
        cur.execute(sql, params)
        rows = rows_as_dicts(cur) if cur.description else []
        return CheckResult("PASS", rows, seconds=round(time.monotonic() - t0, 3))
    except Exception as exc:  # noqa: BLE001
        msg = str(exc)
        status = "TIMEOUT" if "timeout" in msg.lower() or "HYT00" in msg else "ERROR"
        return CheckResult(status, error=msg, seconds=round(time.monotonic() - t0, 3))


def normalize_ref(raw: str) -> Ref | None:
    parts = [p.strip(" []") for p in raw.split(".") if p.strip()]
    if len(parts) == 3 and parts[0] == LAKEHOUSE:
        return Ref(parts[0], parts[1], parts[2])
    if len(parts) == 2:
        return Ref(LAKEHOUSE, parts[0], parts[1])
    return None


def load_source_refs(summary_path: Path) -> dict[Ref, set[str]]:
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    refs: dict[Ref, set[str]] = {}
    for project, data in summary.get("projects", {}).items():
        for raw in data.get("live_external_sources_from_code", []):
            ref = normalize_ref(raw)
            if ref and ref.db == LAKEHOUSE:
                refs.setdefault(ref, set()).add(project)
    for raw in EXTRA_REFS:
        ref = normalize_ref(raw)
        if ref:
            refs.setdefault(ref, set()).add("requested_extra")
    return refs


def fetch_columns(conn: pyodbc.Connection, ref: Ref) -> list[dict[str, Any]]:
    sql = """
        SELECT
            COLUMN_NAME AS column_name,
            DATA_TYPE AS data_type,
            ORDINAL_POSITION AS ordinal_position,
            IS_NULLABLE AS is_nullable
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION;
    """
    cur = conn.cursor()
    cur.execute(sql, (ref.schema, ref.table))
    return rows_as_dicts(cur)


def table_exists(conn: pyodbc.Connection, ref: Ref) -> bool:
    sql = """
        SELECT COUNT_BIG(*)
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?;
    """
    cur = conn.cursor()
    cur.execute(sql, (ref.schema, ref.table))
    return bool(cur.fetchone()[0])


def metadata_row_count(conn: pyodbc.Connection, ref: Ref) -> int | None:
    sql = """
        SELECT SUM(p.rows) AS row_count
        FROM Enterprise_Lakehouse.sys.tables AS t
        JOIN Enterprise_Lakehouse.sys.schemas AS s
          ON s.schema_id = t.schema_id
        JOIN Enterprise_Lakehouse.sys.partitions AS p
          ON p.object_id = t.object_id
         AND p.index_id IN (0, 1)
        WHERE s.name = ? AND t.name = ?;
    """
    try:
        cur = conn.cursor()
        cur.execute(sql, (ref.schema, ref.table))
        value = cur.fetchone()[0]
        return None if value is None else int(value)
    except Exception:  # noqa: BLE001
        return None


def col_type(columns: list[dict[str, Any]], col: str) -> str:
    for c in columns:
        if c["column_name"] == col:
            return str(c["data_type"]).lower()
    return ""


def is_text_type(data_type: str) -> bool:
    return data_type.lower() in {"varchar", "nvarchar", "char", "nchar", "text"}


def is_date_type(data_type: str) -> bool:
    return data_type.lower() in {"date", "datetime", "datetime2", "smalldatetime", "datetimeoffset"}


def is_numeric_type(data_type: str) -> bool:
    return data_type.lower() in {
        "int",
        "bigint",
        "smallint",
        "tinyint",
        "decimal",
        "numeric",
        "float",
        "real",
    }


def pick_date_candidates(ref: Ref, columns: list[dict[str, Any]]) -> list[str]:
    names = [str(c["column_name"]) for c in columns]
    types = {str(c["column_name"]): str(c["data_type"]).lower() for c in columns}

    overrides = {
        "SupplyChain_Enh.DemandForecastSnapshotDaily": ["dfcSnapshot"],
        "SupplyChain_Enh.DemandForecastSnapshotWeekly": ["dfcSnapshot"],
        "SupplyChain_Enh.DemandInventorySnapshotDaily": ["dinSnapshot"],
        "SupplyChain_Enh.DemandInventorySnapshotWeekly": ["dinSnapshot"],
        "SupplyChain_Enh.SupplyPlanDetailSnapshotDaily": ["dtea", "spdWeekEnding"],
        "SupplyChain_Enh.SupplyPlanDetailSnapshotWeekly": ["dtea", "spdWeekEnding"],
        "SupplyChain_Enh.PurchaseOrderSnapshot": ["posSnapshot", "posDueDt"],
        "SupplyChain_Enh.ATPWeekEnding": ["InsertedDate", "RunDate", "WeekEnding"],
        "Inventory_Enh_History.ItemBalance": ["DateWeekEnding"],
        "SalesHistory_AFI_Enh.InvoiceHeader": ["InvoiceDate", "OrderDate", "RequestDate"],
        "SalesHistory_AFI_Enh.InvoiceDetail": ["InvoiceDate", "OrderDate", "RequestDate"],
        "MasterData_DW.DimDate": ["Date"],
        "MasterData_DW.DimItemMaster": ["ManufacturingStatusChangeDate", "DiscontinuedDate", "StatusCodeChangeDate"],
        "Manufacturing_Inventory_AFI.TFRDTL": ["DETADT"],
        "Manufacturing_Inventory_AFI.TFRHDR": ["HARRDT"],
        "Manufacturing_ProductionPlanning_AFI.MOMAST": ["ODUDT"],
        "ItemMaster_AFI.ITEMBL": ["LACDT"],
        "ItemMaster_AFI.ITBEXT": ["MFSDT"],
        "ItemMaster_AFI.ITMRVA": ["BZBLDT"],
        "Wholesale_Codis_AFI.EXTORD": ["HDATE"],
        "Wholesale_Codis_AFI.EXTORIT": ["IDATE"],
        "Wholesale_Codis_AFI.AAORDTYP": ["OTDATE"],
        "SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility": ["WeekEnding", "StatusChngDate", "FileDate"],
    }
    picked: list[str] = []
    for c in overrides.get(ref.short, []):
        if c in names and c not in picked:
            picked.append(c)

    patterns = [
        r"(?i)^loaddt$",
        r"(?i)^load.*date$",
        r"(?i).*snapshot.*",
        r"(?i).*week.*end.*",
        r"(?i)^inserteddate$",
        r"(?i)^rundate$",
        r"(?i).*invoice.*date$",
        r"(?i).*order.*date$",
        r"(?i).*change.*date$",
        r"(?i).*(date|dt)$",
    ]
    for pat in patterns:
        for name in names:
            if name in picked:
                continue
            if re.search(pat, name) and (is_date_type(types.get(name, "")) or is_numeric_type(types.get(name, ""))):
                picked.append(name)
    return picked[:5]


def sql_expr_for_date_max(col: str) -> str:
    return f"MAX([{col}]) AS [{col}]"


def max_dates(conn: pyodbc.Connection, ref: Ref, candidates: list[str]) -> dict[str, Any]:
    if not candidates:
        return {}
    exprs = ", ".join(sql_expr_for_date_max(c) for c in candidates)
    result = run_timed(conn, f"SELECT {exprs} FROM {ref.sql};", timeout_seconds=120)
    if result.status != "PASS" or not result.value:
        return {"status": result.status, "error": result.error, "seconds": result.seconds}
    row = result.value[0]
    return {k: stringify(v) for k, v in row.items()}


def stringify(value: Any) -> Any:
    if isinstance(value, dt.datetime):
        return value.isoformat(sep=" ", timespec="seconds")
    if isinstance(value, dt.date):
        return value.isoformat()
    if isinstance(value, Decimal):
        if value == value.to_integral_value():
            return int(value)
        return str(value)
    return value


def known_key_columns(ref: Ref, columns: list[dict[str, Any]]) -> list[str]:
    names = {str(c["column_name"]).lower(): str(c["column_name"]) for c in columns}
    known = {
        "CustomerOrders_AFI.WarehouseMaster": ["Warehouse"],
        "Customers.AccountMaster": ["cmaCustomerNumber"],
        "Customers.ShippingLocations": ["cslCustomerNumber", "cslShiptoNumber"],
        "ItemMaster_AFI.AITMCLS": ["ICLAS"],
        "ItemMaster_AFI.ITMEXT": ["ITEM"],
        "ItemMaster_AFI.ITBEXT": ["ITEM"],
        "ItemMaster_AFI.ITEMBL": ["ITEM", "WHSE"],
        "ItemMaster_AFI.ITMRVA": ["ITEM"],
        "MasterData_DW.DimDate": ["Date"],
        "MasterData_DW.DimItemMaster": ["ItemSKU"],
        "MasterData_ProductKnowledge.Item_ENV": ["Item"],
        "Purchasing_AFI.VendorMaster": ["VendorNumber"],
        "SalesHistory_AFI_Enh.InvoiceHeader": ["InvoiceNumber"],
        "SalesHistory_AFI_Enh.InvoiceDetail": ["InvoiceNumber", "ItemSequence", "LineReleaseNumber", "OriginalSequenceNumber", "ItemSKU"],
        "SupplyChain_Enh.ATPWeekEnding": ["WeekEnding", "RunDate", "InsertedDate", "ItemSKU", "Warehouse", "AFIFinanceDivision"],
        "SupplyChain_Enh.DemandForecastSnapshotDaily": ["dfcSnapshot", "dfcItem", "dfcWarehouse"],
        "SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility": ["WeekEnding", "Item", "Warehouse"],
        "SupplyChain_Enh.DemandInventorySnapshotDaily": ["dinSnapshot", "dinItem", "dinWarehouse"],
        "SupplyChain_Enh.PurchaseOrderSnapshot": ["posSnapshot", "posItNbr", "posWhse", "posVndnr", "posDueDt"],
        "SupplyChain_Enh.SupplyPlanDetailSnapshotDaily": ["dtea", "spdItem", "spdWarehouse", "spdWeekEnding"],
        "SupplyChain_Enh.SupplyPlanDetailSnapshotWeekly": ["dtea", "spdItem", "spdWarehouse", "spdWeekEnding"],
        "Inventory_Enh_History.ItemBalance": ["ItemNumber", "Warehouse", "DateWeekEnding"],
        "Manufacturing_Inventory_AFI.TFRDTL": ["DTFRNO"],
        "Manufacturing_Inventory_AFI.TFRHDR": ["HTFRNO"],
        "Manufacturing_ProductionPlanning_AFI.MOMAST": ["ORDNO"],
        "Wholesale_Codis_AFI.AAORDTYP": ["OTTYPE"],
        "Wholesale_Codis_AFI.COMAST": ["CCUST"],
        "Wholesale_Codis_AFI.EXTORD": ["HORD"],
        "Wholesale_Codis_AFI.EXTORIT": ["IORD", "ISEQ"],
        "Wholesale_Codis_AFI.codatan": ["DCODE"],
        "Wholesale_Codis_AFI.AshleyWarehouseMaster": ["Warehouse"],
        "Wholesale_ProductSourcing.NonPkItems": ["npkitem"],
        "Wholesale_ProductSourcing_AFI.CustomerGrouping": ["CustomerNumber", "CustomerGroup"],
    }
    out: list[str] = []
    for col in known.get(ref.short, []):
        actual = names.get(col.lower())
        if actual and actual not in out:
            out.append(actual)
    if out:
        return out

    priority = [
        r"(?i)^(item|itemsku|sku|itemnumber|itemnbr|itnbr)$",
        r"(?i)^(warehouse|whse|whs|warehousecode)$",
        r"(?i)^(customer|customernumber|custno|accountnumber)$",
        r"(?i)^(vendor|vendornumber|vendornbr)$",
        r"(?i).*(invoice|order|transfer).*(number|num|no|id)$",
        r"(?i).*(snapshot|weekending|date)$",
    ]
    for pat in priority:
        for c in columns:
            name = str(c["column_name"])
            if name in out:
                continue
            if re.search(pat, name):
                out.append(name)
            if len(out) >= 5:
                return out
    return out[:5]


def null_blank_check(conn: pyodbc.Connection, ref: Ref, key_cols: list[str], columns: list[dict[str, Any]]) -> CheckResult:
    if not key_cols:
        return CheckResult("SKIPPED", error="No key columns selected")
    clauses = []
    for col in key_cols:
        data_type = col_type(columns, col)
        if is_text_type(data_type):
            clauses.append(f"([{col}] IS NULL OR LTRIM(RTRIM([{col}])) = '')")
        else:
            clauses.append(f"[{col}] IS NULL")
    sql = f"""
        SELECT COUNT_BIG(*) AS null_blank_key_rows
        FROM {ref.sql}
        WHERE {' OR '.join(clauses)};
    """
    return run_timed(conn, sql, timeout_seconds=120)


def duplicate_check(conn: pyodbc.Connection, ref: Ref, key_cols: list[str], *, timeout_seconds: int) -> CheckResult:
    if not key_cols:
        return CheckResult("SKIPPED", error="No key columns selected")
    cols_sql = ", ".join(f"[{c}]" for c in key_cols)
    sql = f"""
        WITH d AS (
            SELECT {cols_sql}, COUNT_BIG(*) AS row_count
            FROM {ref.sql}
            GROUP BY {cols_sql}
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            COUNT_BIG(*) AS duplicate_groups,
            SUM(row_count - 1) AS duplicate_extra_rows,
            MAX(row_count) AS max_rows_per_key
        FROM d;
    """
    return run_timed(conn, sql, timeout_seconds=timeout_seconds)


def full_row_duplicate_check(
    conn: pyodbc.Connection,
    ref: Ref,
    columns: list[dict[str, Any]],
    *,
    row_count: int | None,
    max_rows: int,
    timeout_seconds: int,
) -> CheckResult:
    if row_count is not None and row_count > max_rows:
        return CheckResult(
            "SKIPPED",
            error=f"row_count_metadata={row_count} exceeds full-row max {max_rows}",
        )
    col_names = [str(c["column_name"]) for c in columns]
    if not col_names:
        return CheckResult("SKIPPED", error="No columns")
    cols_sql = ", ".join(f"[{c}]" for c in col_names)
    sql = f"""
        WITH d AS (
            SELECT {cols_sql}, COUNT_BIG(*) AS row_count
            FROM {ref.sql}
            GROUP BY {cols_sql}
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            COUNT_BIG(*) AS full_row_duplicate_groups,
            SUM(row_count - 1) AS full_row_duplicate_extra_rows,
            MAX(row_count) AS max_rows_per_full_row
        FROM d;
    """
    return run_timed(conn, sql, timeout_seconds=timeout_seconds)


def latest_partition_duplicate_check(
    conn: pyodbc.Connection,
    ref: Ref,
    key_cols: list[str],
    freshness_col: str | None,
    *,
    timeout_seconds: int,
) -> CheckResult:
    if not key_cols or not freshness_col:
        return CheckResult("SKIPPED", error="No key columns or freshness column selected")
    cols_sql = ", ".join(f"[{c}]" for c in key_cols)
    sql = f"""
        WITH latest AS (
            SELECT MAX([{freshness_col}]) AS max_value
            FROM {ref.sql}
        ),
        d AS (
            SELECT {cols_sql}, COUNT_BIG(*) AS row_count
            FROM {ref.sql} AS src
            CROSS JOIN latest
            WHERE src.[{freshness_col}] = latest.max_value
            GROUP BY {cols_sql}
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            COUNT_BIG(*) AS latest_partition_duplicate_groups,
            SUM(row_count - 1) AS latest_partition_duplicate_extra_rows,
            MAX(row_count) AS latest_partition_max_rows_per_key
        FROM d;
    """
    return run_timed(conn, sql, timeout_seconds=timeout_seconds)


def profile_table(
    conn: pyodbc.Connection,
    ref: Ref,
    projects: list[str],
    *,
    deep_max_rows: int,
    full_row_max_rows: int,
    duplicate_timeout_seconds: int,
) -> TableProfile:
    profile = TableProfile(ref=ref, projects=projects)
    profile.exists = table_exists(conn, ref)
    if not profile.exists:
        profile.warnings.append("MISSING_ON_ENTERPRISE_LAKEHOUSE")
        return profile

    profile.row_count_metadata = metadata_row_count(conn, ref)
    profile.columns = fetch_columns(conn, ref)
    profile.column_count = len(profile.columns)

    candidates = pick_date_candidates(ref, profile.columns)
    date_maxes = max_dates(conn, ref, candidates)
    freshness_col = candidates[0] if candidates else None
    profile.freshness = {
        "candidate_columns": candidates,
        "max_values": date_maxes,
        "primary_column": freshness_col,
        "primary_max": date_maxes.get(freshness_col) if isinstance(date_maxes, dict) and freshness_col else None,
    }

    profile.key_columns = known_key_columns(ref, profile.columns)
    if profile.row_count_metadata is not None and profile.row_count_metadata > deep_max_rows:
        reason = f"row_count_metadata={profile.row_count_metadata} exceeds deep max {deep_max_rows}"
        profile.key_null_blank = CheckResult("SKIPPED", error=reason)
        profile.grain_duplicate = CheckResult("SKIPPED", error=reason)
        profile.latest_partition_duplicate = CheckResult("SKIPPED", error=reason)
    else:
        profile.key_null_blank = null_blank_check(conn, ref, profile.key_columns, profile.columns)
        profile.grain_duplicate = duplicate_check(
            conn,
            ref,
            profile.key_columns,
            timeout_seconds=duplicate_timeout_seconds,
        )
        profile.latest_partition_duplicate = latest_partition_duplicate_check(
            conn,
            ref,
            profile.key_columns,
            freshness_col,
            timeout_seconds=duplicate_timeout_seconds,
        )
    profile.full_row_duplicate = full_row_duplicate_check(
        conn,
        ref,
        profile.columns,
        row_count=profile.row_count_metadata,
        max_rows=full_row_max_rows,
        timeout_seconds=duplicate_timeout_seconds,
    )
    return profile


def check_to_dict(result: CheckResult | None) -> dict[str, Any] | None:
    if result is None:
        return None
    return {
        "status": result.status,
        "value": stringify_nested(result.value),
        "error": result.error,
        "seconds": result.seconds,
    }


def stringify_nested(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: stringify_nested(v) for k, v in value.items()}
    if isinstance(value, list):
        return [stringify_nested(v) for v in value]
    return stringify(value)


def profile_to_dict(profile: TableProfile) -> dict[str, Any]:
    return {
        "ref": profile.ref.full,
        "projects": profile.projects,
        "exists": profile.exists,
        "row_count_metadata": profile.row_count_metadata,
        "column_count": profile.column_count,
        "columns": profile.columns,
        "freshness": stringify_nested(profile.freshness),
        "key_columns": profile.key_columns,
        "key_null_blank": check_to_dict(profile.key_null_blank),
        "grain_duplicate": check_to_dict(profile.grain_duplicate),
        "latest_partition_duplicate": check_to_dict(profile.latest_partition_duplicate),
        "full_row_duplicate": check_to_dict(profile.full_row_duplicate),
        "warnings": profile.warnings,
    }


def first_metric(result: CheckResult | None, key: str) -> Any:
    if not result or result.status != "PASS" or not result.value:
        return None
    row = result.value[0]
    return row.get(key)


def status_for(profile: TableProfile) -> str:
    if not profile.exists:
        return "MISSING"
    severe = []
    if profile.grain_duplicate and profile.grain_duplicate.status == "PASS":
        if (first_metric(profile.grain_duplicate, "duplicate_extra_rows") or 0) > 0:
            severe.append("GRAIN_DUP")
    if profile.latest_partition_duplicate and profile.latest_partition_duplicate.status == "PASS":
        if (first_metric(profile.latest_partition_duplicate, "latest_partition_duplicate_extra_rows") or 0) > 0:
            severe.append("LATEST_DUP")
    if profile.key_null_blank and profile.key_null_blank.status == "PASS":
        if (first_metric(profile.key_null_blank, "null_blank_key_rows") or 0) > 0:
            severe.append("NULL_BLANK_KEY")
    if severe:
        return "REVIEW"
    if any(
        r and r.status in {"TIMEOUT", "ERROR"}
        for r in [profile.key_null_blank, profile.grain_duplicate, profile.latest_partition_duplicate, profile.full_row_duplicate]
    ):
        return "PARTIAL"
    return "PASS"


def write_outputs(results: list[TableProfile], out_dir: Path, metadata: dict[str, Any]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "metadata": metadata,
        "tables": [profile_to_dict(r) for r in results],
    }
    (out_dir / "results.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    csv_fields = [
        "status",
        "ref",
        "projects",
        "exists",
        "row_count_metadata",
        "column_count",
        "freshness_primary_column",
        "freshness_primary_max",
        "key_columns",
        "null_blank_key_rows",
        "grain_duplicate_groups",
        "grain_duplicate_extra_rows",
        "latest_partition_duplicate_groups",
        "latest_partition_duplicate_extra_rows",
        "full_row_duplicate_status",
        "full_row_duplicate_groups",
        "full_row_duplicate_extra_rows",
        "warnings",
    ]
    with (out_dir / "results.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for r in results:
            writer.writerow(
                {
                    "status": status_for(r),
                    "ref": r.ref.full,
                    "projects": ";".join(r.projects),
                    "exists": r.exists,
                    "row_count_metadata": r.row_count_metadata,
                    "column_count": r.column_count,
                    "freshness_primary_column": r.freshness.get("primary_column"),
                    "freshness_primary_max": r.freshness.get("primary_max"),
                    "key_columns": ";".join(r.key_columns),
                    "null_blank_key_rows": first_metric(r.key_null_blank, "null_blank_key_rows"),
                    "grain_duplicate_groups": first_metric(r.grain_duplicate, "duplicate_groups"),
                    "grain_duplicate_extra_rows": first_metric(r.grain_duplicate, "duplicate_extra_rows"),
                    "latest_partition_duplicate_groups": first_metric(r.latest_partition_duplicate, "latest_partition_duplicate_groups"),
                    "latest_partition_duplicate_extra_rows": first_metric(r.latest_partition_duplicate, "latest_partition_duplicate_extra_rows"),
                    "full_row_duplicate_status": r.full_row_duplicate.status if r.full_row_duplicate else None,
                    "full_row_duplicate_groups": first_metric(r.full_row_duplicate, "full_row_duplicate_groups"),
                    "full_row_duplicate_extra_rows": first_metric(r.full_row_duplicate, "full_row_duplicate_extra_rows"),
                    "warnings": ";".join(r.warnings),
                }
            )

    lines = [
        "# Bronze Source DQ Refresh",
        "",
        f"- Generated at ICT: `{metadata['generated_at_ict']}`",
        f"- Server: `{metadata['server']}`",
        f"- Source summary: `{metadata['summary_path']}`",
        f"- Tables checked: `{len(results)}`",
        f"- Deep aggregate max rows: `{metadata['deep_max_rows']}`",
        f"- Full-row duplicate max rows: `{metadata['full_row_max_rows']}`",
        "",
        "## Status Summary",
        "",
    ]
    counts: dict[str, int] = {}
    for r in results:
        counts[status_for(r)] = counts.get(status_for(r), 0) + 1
    for k in sorted(counts):
        lines.append(f"- `{k}`: `{counts[k]}`")
    lines.extend(["", "## Table Results", ""])
    for r in results:
        fd = r.freshness
        lines.append(f"### `{r.ref.full}`")
        lines.append(f"- Status: `{status_for(r)}`")
        lines.append(f"- Projects: `{', '.join(r.projects)}`")
        lines.append(f"- Exists: `{r.exists}`; row_count_metadata: `{r.row_count_metadata}`; columns: `{r.column_count}`")
        lines.append(f"- Freshness/date: `{fd.get('primary_column')}` max=`{fd.get('primary_max')}`; all candidates=`{fd.get('max_values')}`")
        lines.append(f"- Grain key: `{r.key_columns}`")
        lines.append(f"- Null/blank key rows: `{first_metric(r.key_null_blank, 'null_blank_key_rows')}` ({r.key_null_blank.status if r.key_null_blank else None})")
        lines.append(
            "- Grain duplicates: "
            f"groups=`{first_metric(r.grain_duplicate, 'duplicate_groups')}`, "
            f"extra_rows=`{first_metric(r.grain_duplicate, 'duplicate_extra_rows')}` "
            f"({r.grain_duplicate.status if r.grain_duplicate else None})"
        )
        lines.append(
            "- Latest-partition grain duplicates: "
            f"groups=`{first_metric(r.latest_partition_duplicate, 'latest_partition_duplicate_groups')}`, "
            f"extra_rows=`{first_metric(r.latest_partition_duplicate, 'latest_partition_duplicate_extra_rows')}` "
            f"({r.latest_partition_duplicate.status if r.latest_partition_duplicate else None})"
        )
        lines.append(
            "- Full-row duplicates: "
            f"groups=`{first_metric(r.full_row_duplicate, 'full_row_duplicate_groups')}`, "
            f"extra_rows=`{first_metric(r.full_row_duplicate, 'full_row_duplicate_extra_rows')}` "
            f"({r.full_row_duplicate.status if r.full_row_duplicate else None}; "
            f"{r.full_row_duplicate.error if r.full_row_duplicate else ''})"
        )
        if r.warnings:
            lines.append(f"- Warnings: `{r.warnings}`")
        lines.append("")
    (out_dir / "README.md").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit active Bronze source DQ from live Enterprise_Lakehouse.")
    parser.add_argument("--summary", type=Path, default=SUMMARY_PATH)
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR)
    parser.add_argument("--limit", type=int, default=0, help="Optional limit for smoke testing.")
    parser.add_argument("--full-row-max-rows", type=int, default=2_000_000)
    parser.add_argument("--deep-max-rows", type=int, default=75_000_000)
    parser.add_argument("--duplicate-timeout-seconds", type=int, default=180)
    args = parser.parse_args()

    refs = load_source_refs(args.summary)
    ordered = sorted(refs)
    if args.limit:
        ordered = ordered[: args.limit]

    metadata = {
        "generated_at_ict": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "server": SERVER,
        "database": DATABASE,
        "lakehouse": LAKEHOUSE,
        "summary_path": str(args.summary),
        "full_row_max_rows": args.full_row_max_rows,
        "deep_max_rows": args.deep_max_rows,
        "duplicate_timeout_seconds": args.duplicate_timeout_seconds,
        "extra_refs": EXTRA_REFS,
    }

    results: list[TableProfile] = []
    with connect() as conn:
        for i, ref in enumerate(ordered, start=1):
            projects = sorted(refs[ref])
            print(f"[{i}/{len(ordered)}] {ref.full} ({', '.join(projects)})", flush=True)
            results.append(
                profile_table(
                    conn,
                    ref,
                    projects,
                    deep_max_rows=args.deep_max_rows,
                    full_row_max_rows=args.full_row_max_rows,
                    duplicate_timeout_seconds=args.duplicate_timeout_seconds,
                )
            )
            write_outputs(results, args.out_dir, metadata)

    write_outputs(results, args.out_dir, metadata)
    print(f"Wrote {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
