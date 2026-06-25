#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import re
import struct
import subprocess
import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import pyodbc


SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)
DATABASE = "SupplyChain_Processing_Warehouse"
LAKEHOUSE = "Enterprise_Lakehouse"


@dataclass(frozen=True)
class TableRef:
    schema: str
    table: str

    @property
    def display(self) -> str:
        return f"{self.schema}.{self.table}"

    @property
    def fq_sql(self) -> str:
        return f"[{LAKEHOUSE}].[{self.schema}].[{self.table}]"


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


def run_scalar(cur: pyodbc.Cursor, sql: str, params: Iterable[Any] = ()) -> Any:
    cur.execute(sql, tuple(params))
    row = cur.fetchone()
    return None if row is None else row[0]


def try_select_one(conn_holder: dict[str, Any], ref: TableRef) -> tuple[bool, str | None]:
    try:
        cur = execute_with_reconnect(conn_holder, f"SELECT TOP (1) 1 AS one FROM {ref.fq_sql};")
        cur.fetchone()
        return True, None
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def fetch_columns(conn_holder: dict[str, Any], ref: TableRef) -> tuple[list[str], str | None]:
    try:
        cur = execute_with_reconnect(conn_holder, f"SELECT TOP (0) * FROM {ref.fq_sql};")
        cols = [d[0] for d in (cur.description or [])]
        return cols, None
    except Exception as e:  # noqa: BLE001
        return [], str(e)


def find_tables(conn_holder: dict[str, Any], name_or_like: str) -> list[TableRef]:
    # First: exact TABLE_NAME
    sql_exact = """
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = ?
        ORDER BY TABLE_SCHEMA, TABLE_NAME;
    """
    cur = execute_with_reconnect(conn_holder, sql_exact, params=(name_or_like,))
    out = [TableRef(r[0], r[1]) for r in cur.fetchall()]
    if out:
        return out

    # Fallback: LIKE search (case-insensitive-ish by lowering both sides)
    like = f"%{name_or_like}%"
    sql_like = """
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES
        WHERE LOWER(TABLE_NAME) LIKE LOWER(?)
        ORDER BY TABLE_SCHEMA, TABLE_NAME;
    """
    cur = execute_with_reconnect(conn_holder, sql_like, params=(like,))
    return [TableRef(r[0], r[1]) for r in cur.fetchall()]


def parse_ref(raw: str, conn_holder: dict[str, Any]) -> list[TableRef]:
    raw = (raw or "").strip()
    if not raw:
        return []
    parts = [p for p in raw.split(".") if p]
    if len(parts) == 2:
        return [TableRef(parts[0], parts[1])]
    if len(parts) == 3:
        # allow Enterprise_Lakehouse.<schema>.<table> inputs
        return [TableRef(parts[1], parts[2])]
    if len(parts) == 1:
        return find_tables(conn_holder, parts[0])
    return []


def fetch_column_types(conn_holder: dict[str, Any], ref: TableRef) -> dict[str, str]:
    sql = """
        SELECT COLUMN_NAME, DATA_TYPE
        FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION;
    """
    cur = execute_with_reconnect(conn_holder, sql, params=(ref.schema, ref.table))
    return {str(r[0]): str(r[1]) for r in cur.fetchall()}


def pick_freshness_col(columns: list[str], col_types: dict[str, str]) -> str | None:
    if not columns:
        return None

    def is_dateish(c: str) -> bool:
        t = (col_types.get(c) or "").lower()
        return t in {"date", "datetime", "datetime2", "smalldatetime", "datetimeoffset"}

    def is_numeric_dateish(c: str) -> bool:
        t = (col_types.get(c) or "").lower()
        return t in {"int", "bigint", "decimal", "numeric", "smallint", "tinyint"}

    cols_lower = {c.lower(): c for c in columns}
    preferred_exact = [
        "loaddt",
        "loaddate",
        "load_date",
        "snapshot",
        "snapshotdate",
        "dfcsnapshot",
        "possnapshot",
        "dinsnapshot",
        "weekending",
        "weekendingdate",
        "invoicedate",
        "orderdate",
        "transdate",
        "transactiondate",
        "recorddate",
        "effectivedate",
        "createddate",
        "createdon",
        "modifiedon",
        "updatedt",
        "updatedate",
    ]
    for key in preferred_exact:
        c = cols_lower.get(key)
        if not c:
            continue
        if is_dateish(c) or is_numeric_dateish(c):
            return c

    # Prefer date/datetime columns that look like dates
    patterns = [
        r"(?i)^load.*(dt|date|datetime)$",
        r"(?i)^.*snapshot.*(dt|date|datetime)?$",
        r"(?i)^.*(week.*end|weekending).*(dt|date)?$",
        r"(?i)^.*invoice.*date$",
        r"(?i)^.*order.*date$",
        r"(?i)^.*trans.*date$",
        r"(?i)^.*(created|modified|update).*(dt|date|datetime)$",
    ]
    for pat in patterns:
        for c in columns:
            if re.match(pat, c) and (is_dateish(c) or is_numeric_dateish(c)):
                return c

    # Final fallback: any *Date/*DT column with a date or numeric type
    for c in columns:
        if re.search(r"(?i)(date|dt|datetime)$", c) and (is_dateish(c) or is_numeric_dateish(c)):
            return c
    return None


def as_iso(v: Any) -> str | None:
    if v is None:
        return None
    if isinstance(v, (dt.datetime, dt.date)):
        if isinstance(v, dt.datetime):
            return v.isoformat(sep=" ", timespec="seconds")
        return v.isoformat()
    return str(v)


def _try_parse_yyyymmdd(n: int) -> dt.date | None:
    if n <= 0:
        return None
    if 10000101 <= n <= 99991231:
        y, m, d = n // 10000, (n // 100) % 100, n % 100
        try:
            return dt.date(y, m, d)
        except ValueError:
            return None
    return None


def _try_parse_cyymmdd(n: int) -> dt.date | None:
    # AS/400 style: CYYMMDD (7 digits)
    if n <= 0:
        return None
    if 1000000 <= n <= 1999999:
        c = n // 1000000
        yy = (n // 10000) % 100
        mm = (n // 100) % 100
        dd = n % 100
        year = (1900 if c == 0 else 2000) + yy
        try:
            return dt.date(year, mm, dd)
        except ValueError:
            return None
    return None


def coerce_to_date(v: Any) -> dt.date | None:
    if v is None:
        return None
    if isinstance(v, dt.datetime):
        return v.date()
    if isinstance(v, dt.date):
        return v
    # numeric dates sometimes come back as Decimal
    try:
        n = int(v)
    except Exception:  # noqa: BLE001
        return None
    return _try_parse_yyyymmdd(n) or _try_parse_cyymmdd(n)


def days_since(v: Any, today: dt.date) -> int | None:
    d = coerce_to_date(v)
    if d is None:
        return None
    return (today - d).days


def duplicate_summary(
    cur: pyodbc.Cursor, ref: TableRef, key_cols: list[str]
) -> dict[str, Any]:
    if not key_cols:
        return {"dup_key_cols": [], "dup_groups": None, "dup_extra_rows": None}

    keys_sql = ", ".join(f"[{c}]" for c in key_cols)
    sql = f"""
        SELECT
            COUNT_BIG(*) AS dup_groups,
            SUM(cnt - 1) AS dup_extra_rows
        FROM (
            SELECT COUNT_BIG(*) AS cnt
            FROM {ref.fq_sql}
            GROUP BY {keys_sql}
            HAVING COUNT_BIG(*) > 1
        ) d;
    """
    try:
        cur.execute(sql)
        row = cur.fetchone()
        return {
            "dup_key_cols": key_cols,
            "dup_groups": int(row[0] or 0),
            "dup_extra_rows": int(row[1] or 0),
        }
    except Exception as e:  # noqa: BLE001
        return {"dup_key_cols": key_cols, "dup_groups": None, "dup_extra_rows": None, "dup_error": str(e)}


def count_future_dated(
    cur: pyodbc.Cursor,
    ref: TableRef,
    date_col: str,
    today: dt.date,
) -> dict[str, Any]:
    sql = f"""
        SELECT
            COUNT_BIG(*) AS future_rows,
            MAX([{date_col}]) AS max_date
        FROM {ref.fq_sql}
        WHERE [{date_col}] > ?;
    """
    try:
        cur.execute(sql, (today,))
        row = cur.fetchone()
        return {"future_date_col": date_col, "future_rows": int(row[0] or 0), "future_max_date": as_iso(row[1])}
    except Exception as e:  # noqa: BLE001
        return {"future_date_col": date_col, "future_rows": None, "future_error": str(e)}


def key_candidates(columns: list[str], patterns: list[str]) -> list[str]:
    out: list[str] = []
    for pat in patterns:
        for c in columns:
            if re.search(pat, c, flags=re.IGNORECASE) and c not in out:
                out.append(c)
    return out


def _looks_like_link_failure(e: Exception) -> bool:
    msg = str(e).lower()
    return (
        "communication link failure" in msg
        or "08s01" in msg
        or "connection is broken" in msg
        or "unrecoverable" in msg
        or "imc06" in msg
    )


def execute_with_reconnect(
    conn_holder: dict[str, Any],
    sql: str,
    params: Iterable[Any] = (),
) -> pyodbc.Cursor:
    # Keep a single connection but retry once on link failure.
    for attempt in (1, 2):
        try:
            cn: pyodbc.Connection = conn_holder["cn"]
            cur = cn.cursor()
            cur.execute(sql, tuple(params))
            return cur
        except Exception as e:  # noqa: BLE001
            if attempt == 1 and _looks_like_link_failure(e):
                conn_holder["cn"].close()
                conn_holder["cn"] = connect()
                continue
            raise


def exists_where(
    conn_holder: dict[str, Any],
    ref: TableRef,
    where_sql: str,
    params: Iterable[Any] = (),
) -> tuple[bool | None, str | None]:
    sql = f"SELECT TOP (1) 1 FROM {ref.fq_sql} WHERE {where_sql};"
    try:
        cur = execute_with_reconnect(conn_holder, sql, params=params)
        return (cur.fetchone() is not None), None
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def main() -> int:
    ap = argparse.ArgumentParser(description="Verify DE US status table against Enterprise_Lakehouse live data.")
    ap.add_argument("--mode", choices=["light", "deep"], default="light", help="light=fast signals; deep=counts/dup/orphans")
    args = ap.parse_args()

    today = dt.date.today()
    run_id = dt.datetime.now().strftime("%Y%m%d_%H%M%S") + "_de_us_status_verify"
    out_dir = Path(__file__).resolve().parents[1] / "artifacts" / "build_runs" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    items: list[dict[str, Any]] = [
        {
            "ref": "SupplyChain_Enh_1.DemandForecastSnapshotDaily",
            "issue": "Snapshot chậm 85 ngày (MAX Snapshot = 2026-02-24)",
            "claimed": "✅ Hoàn thành",
        },
        {
            "ref": "SupplyChain_DW.DimAFIWarehouses",
            "issue": "Data freshness (194 ngày stale)",
            "claimed": "✅ Hoàn thành",
        },
        {"ref": "Customers.AccountMaster", "issue": "Data freshness (169 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Customers.ShippingLocations", "issue": "Data freshness (169 ngày stale)", "claimed": "✅ Hoàn thành"},
        {
            "ref": "Wholesale_ProductSourcing_AFI.CustomerGrouping",
            "issue": "Data freshness (161 ngày stale)",
            "claimed": "✅ Hoàn thành",
        },
        {"ref": "Wholesale_Codis_AFI.COMAST", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Wholesale_Codis_AFI.Codatan", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Wholesale_Codis_AFI.EXTORD", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Wholesale_Codis_AFI.EXTORIT", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Wholesale_Codis_AFI.AAORDTYP", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {
            "ref": "Manufacturing_ProductionPlanning_AFI.MOMAST",
            "issue": "Data freshness (169 ngày stale)",
            "claimed": "✅ Hoàn thành",
        },
        {"ref": "Manufacturing_Inventory_AFI.TFRDTL", "issue": "Data freshness (161 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "Manufacturing_Inventory_AFI.TFRHDR", "issue": "Data freshness (161 ngày stale)", "claimed": "✅ Hoàn thành"},
        {
            "ref": "Wholesale_Codis_AFI.AshleyWarehouseMaster",
            "issue": "Data freshness (98 ngày stale)",
            "claimed": "✅ Hoàn thành",
        },
        {"ref": "Wholesale_Purchasing_AFI.ATPSUM", "issue": "Data freshness (98 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "ItemMaster_AFI.ITBEXT", "issue": "Data freshness (71 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "ItemMaster_AFI.ITMRVA", "issue": "Data freshness (66 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "ItemMaster_AFI.ITEMBL", "issue": "Data freshness (58 ngày stale)", "claimed": "✅ Hoàn thành"},
        {"ref": "SupplyChain_Enh.CurFcstSnapshotWeekly", "issue": "Cần pull/load table", "claimed": "✅ Hoàn thành"},
        {
            "ref": "SalesHistory_AFI.InvoiceHeader",
            "issue": "Thiếu dữ liệu lịch sử (~4M vs ~25M records)",
            "claimed": "🟡 Cần Analytics kiểm tra lại",
            "need_rowcount": True,
        },
        {
            "ref": "SupplyChain_Enh.PurchaseOrderSnapshot",
            "issue": "Chưa được promote lên Enterprise Lakehouse",
            "claimed": "🟡 Cần Analytics kiểm tra lại",
        },
        {
            "ref": "SupplyChain_Enh.ATPWeekEnding",
            "issue": "Duplicate records + AFIFinanceDivision null",
            "claimed": "🟡 Cần Analytics kiểm tra lại",
            "null_cols": ["AFIFinanceDivision"],
            "dup_key_patterns": [r"week.*end", r"(item|itm)", r"(warehouse|whse|whs)", r"division"],
        },
        {
            "ref": "Manufacturing_Inventory_AFI.IMHIST",
            "issue": "Future-dated records",
            "claimed": "🟠 Cần xác nhận nghiệp vụ",
            "future_date_patterns": [r"(trans|tran|trx|post|record).*(date|dt)$", r".*(date|dt)$"],
        },
        {
            "pair": ["Wholesale_ProductSourcing_AFI.PoDetail", "Wholesale_ProductSourcing_AFI.PoMaster"],
            "issue": "481 orphan detail rows, 20 warehouse mismatch",
            "claimed": "🟠 Cần xác nhận nghiệp vụ",
        },
        {
            "pair": ["Manufacturing_Inventory_AFI.TFRDTL", "Manufacturing_Inventory_AFI.TFRHDR"],
            "issue": "188 orphan detail records",
            "claimed": "🟠 Cần xác nhận nghiệp vụ",
        },
        {
            "ref": "Inventory_Enh_History.ItemBalance",
            "issue": "Chưa được promote lên EL, đang dùng workaround Dataflow Gen2 (~49M rows)",
            "claimed": "🔴 DE chưa hoàn thành",
        },
        {"ref": "DemandForecastSnapshotWeekly", "issue": "Snapshot refresh dừng từ 2024-03-25", "claimed": "🔴 DE chưa hoàn thành"},
        {"ref": "MasterData_DW.DimDate", "issue": "Data stale (204 ngày)", "claimed": "🔴 DE chưa hoàn thành"},
        {"ref": "MasterData_DW.DimItemMaster", "issue": "Data stale (204 ngày)", "claimed": "🔴 DE chưa hoàn thành"},
        {"ref": "DemandInventorySnapshotWeekly", "issue": "Snapshot refresh dừng từ 2026-03-02", "claimed": "🔴 DE chưa hoàn thành"},
        {
            "ref": "DemandFulfillmentCommonContainer_Logility",
            "issue": "9,128 duplicate groups; chưa có canonical dedupe rule",
            "claimed": "🔴 DE chưa hoàn thành",
        },
        {
            "ref": "SupplyChain_Enh_1.SupplyPlanDetailSnapshotDaily",
            "issue": "Missing snapshots 2025-12-20..2026-02-14 (IsActiveItemWhIn14DNext/7DNext)",
            "claimed": "🔴 DE chưa hoàn thành",
            "missing_range": ["2025-12-20", "2026-02-14"],
        },
    ]

    results: dict[str, Any] = {
        "run_id": run_id,
        "timestamp_local": dt.datetime.now().isoformat(sep=" ", timespec="seconds"),
        "today": today.isoformat(),
        "server": SERVER,
        "database": DATABASE,
        "lakehouse": LAKEHOUSE,
        "mode": args.mode,
        "items": [],
    }
    conn_holder: dict[str, Any] = {"cn": connect()}

    for idx, item in enumerate(items, start=1):
        print(f"[{idx}/{len(items)}] {item.get('ref') or 'PAIR'}", flush=True)
        if "pair" in item:
            refs_raw = item["pair"]
            lefts = parse_ref(refs_raw[0], conn_holder)
            rights = parse_ref(refs_raw[1], conn_holder)
            entry: dict[str, Any] = {
                "pair": refs_raw,
                "issue": item["issue"],
                "claimed": item["claimed"],
                "resolved_left": [r.display for r in lefts],
                "resolved_right": [r.display for r in rights],
            }
            if len(lefts) != 1 or len(rights) != 1:
                entry["error"] = "Unable to resolve pair to single tables"
                results["items"].append(entry)
                continue

            left, right = lefts[0], rights[0]
            ok_l, err_l = try_select_one(conn_holder, left)
            ok_r, err_r = try_select_one(conn_holder, right)
            entry["left_exists"] = ok_l
            entry["right_exists"] = ok_r
            entry["left_error"] = err_l
            entry["right_error"] = err_r
            if not ok_l or not ok_r:
                results["items"].append(entry)
                continue

            left_cols, _ = fetch_columns(conn_holder, left)
            right_cols, _ = fetch_columns(conn_holder, right)
            entry["left_cols"] = left_cols
            entry["right_cols"] = right_cols

            # Heuristic join keys: intersection of common PO/transfer identifiers + warehouse
            candidates = [
                r"(?i)^(po|ponum|ponumber|po_no|poid|pohdr|pomas|pode|ordno|order).*",
                r"(?i).*(warehouse|whse|whs).*",
                r"(?i).*(company|division|plant|site).*",
                r"(?i)^(trf|tfr|transfer).*",
                r"(?i).*(id|key)$",
            ]
            common = [c for c in left_cols if c in set(right_cols)]
            key_cols: list[str] = []
            for pat in candidates:
                for c in common:
                    if re.search(pat, c) and c not in key_cols:
                        key_cols.append(c)
            # If still empty, fall back to first common column
            if not key_cols and common:
                key_cols = [common[0]]
            entry["join_key_cols"] = key_cols
            if not key_cols:
                entry["orphan_detail_rows"] = None
                entry["orphan_error"] = "No join keys found"
                results["items"].append(entry)
                continue

            keys_sql = " AND ".join(f"d.[{c}] = m.[{c}]" for c in key_cols)
            null_probe = " OR ".join(f"m.[{c}] IS NULL" for c in key_cols)
            try:
                if args.mode == "deep":
                    sql_orphans = f"""
                        SELECT COUNT_BIG(*) AS orphan_rows
                        FROM {left.fq_sql} d
                        LEFT JOIN {right.fq_sql} m
                          ON {keys_sql}
                        WHERE {null_probe};
                    """
                    cur_orph = execute_with_reconnect(conn_holder, sql_orphans)
                    entry["orphan_detail_rows"] = int(cur_orph.fetchone()[0] or 0)
                else:
                    sql_orphans = f"""
                        SELECT TOP (1) 1
                        FROM {left.fq_sql} d
                        LEFT JOIN {right.fq_sql} m
                          ON {keys_sql}
                        WHERE {null_probe};
                    """
                    cur_orph = execute_with_reconnect(conn_holder, sql_orphans)
                    entry["orphan_exists"] = cur_orph.fetchone() is not None
            except Exception as e:  # noqa: BLE001
                entry["orphan_detail_rows"] = None
                entry["orphan_error"] = str(e)

            results["items"].append(entry)
            continue

        ref_raw = item["ref"]
        resolved = parse_ref(ref_raw, conn_holder)
        entry = {
            "ref": ref_raw,
            "issue": item["issue"],
            "claimed": item["claimed"],
            "resolved": [r.display for r in resolved],
        }
        if len(resolved) != 1:
            entry["error"] = "Unable to resolve to a single table"
            results["items"].append(entry)
            continue

        ref = resolved[0]
        exists, err = try_select_one(conn_holder, ref)
        entry["exists"] = exists
        entry["exists_error"] = err
        if not exists:
            results["items"].append(entry)
            continue

        cols, cols_err = fetch_columns(conn_holder, ref)
        entry["columns"] = cols
        entry["columns_error"] = cols_err
        col_types: dict[str, str] = {}
        try:
            col_types = fetch_column_types(conn_holder, ref) if cols else {}
        except Exception as e:  # noqa: BLE001
            entry["column_types_error"] = str(e)
        entry["column_types"] = col_types

        freshness_col = pick_freshness_col(cols, col_types)
        entry["freshness_col"] = freshness_col
        if freshness_col:
            try:
                cur_max = execute_with_reconnect(
                    conn_holder, f"SELECT MAX([{freshness_col}]) FROM {ref.fq_sql};"
                )
                (max_v,) = cur_max.fetchone()
                entry["freshness_max"] = as_iso(max_v)
                entry["freshness_days_since_max"] = days_since(max_v, today)
            except Exception as e:  # noqa: BLE001
                entry["freshness_error"] = str(e)

        if item.get("need_rowcount"):
            try:
                if args.mode == "deep":
                    cur_cnt = execute_with_reconnect(conn_holder, f"SELECT COUNT_BIG(*) FROM {ref.fq_sql};")
                    (cnt,) = cur_cnt.fetchone()
                    entry["row_count"] = int(cnt or 0)
                else:
                    entry["row_count"] = None
            except Exception as e:  # noqa: BLE001
                entry["row_count"] = None
                entry["row_count_error"] = str(e)

        null_cols = item.get("null_cols") or []
        if null_cols:
            present = [c for c in null_cols if c in set(cols)]
            entry["null_cols_present"] = present
            if present:
                try:
                    if args.mode == "deep":
                        select_expr = ", ".join(
                            f"SUM(CASE WHEN [{c}] IS NULL THEN 1 ELSE 0 END) AS null_{c}" for c in present
                        )
                        sql_nulls = f"SELECT COUNT_BIG(*) AS total, {select_expr} FROM {ref.fq_sql};"
                        cur_null = execute_with_reconnect(conn_holder, sql_nulls)
                        row = cur_null.fetchone()
                        entry["null_total_rows"] = int(row[0] or 0)
                        for idx, c in enumerate(present, start=1):
                            entry[f"null_{c}"] = int(row[idx] or 0)
                    else:
                        # light: existence check only
                        entry["null_any"] = {}
                        for c in present:
                            ok, e = exists_where(conn_holder, ref, f"[{c}] IS NULL")
                            entry["null_any"][c] = ok
                            if e:
                                entry.setdefault("null_any_errors", {})[c] = e
                except Exception as e:  # noqa: BLE001
                    entry["null_error"] = str(e)

        if "dup_key_patterns" in item:
            keys = key_candidates(cols, item["dup_key_patterns"])
            # Use up to 5 keys to keep query stable
            if args.mode == "deep":
                entry["dup"] = duplicate_summary(conn_holder["cn"].cursor(), ref, keys[:5])
            else:
                entry["dup"] = {"dup_key_cols": keys[:5], "dup_groups": None, "dup_extra_rows": None}

        if "future_date_patterns" in item and cols:
            candidates = key_candidates(cols, item["future_date_patterns"])
            # pick first candidate as "date column" for future-dated probe
            if candidates:
                if args.mode == "deep":
                    entry["future"] = count_future_dated(conn_holder["cn"].cursor(), ref, candidates[0], today)
                else:
                    ok, e = exists_where(conn_holder, ref, f"[{candidates[0]}] > ?", params=(today,))
                    entry["future"] = {"future_date_col": candidates[0], "future_any": ok, "future_error": e}

        if "missing_range" in item and freshness_col:
            start_s, end_s = item["missing_range"]
            start = dt.date.fromisoformat(start_s)
            end = dt.date.fromisoformat(end_s)
            try:
                if args.mode == "deep":
                    sql = f"""
                        SELECT
                            COUNT_BIG(*) AS rows_in_range,
                            COUNT_BIG(DISTINCT CAST([{freshness_col}] AS date)) AS distinct_days_in_range,
                            MIN([{freshness_col}]) AS min_in_range,
                            MAX([{freshness_col}]) AS max_in_range
                        FROM {ref.fq_sql}
                        WHERE CAST([{freshness_col}] AS date) BETWEEN ? AND ?;
                    """
                    cur_rng = execute_with_reconnect(conn_holder, sql, params=(start, end))
                    r = cur_rng.fetchone()
                    entry["missing_range"] = {
                        "start": start_s,
                        "end": end_s,
                        "rows_in_range": int(r[0] or 0),
                        "distinct_days_in_range": int(r[1] or 0),
                        "min_in_range": as_iso(r[2]),
                        "max_in_range": as_iso(r[3]),
                    }
                else:
                    ok, e = exists_where(
                        conn_holder,
                        ref,
                        f"CAST([{freshness_col}] AS date) BETWEEN ? AND ?",
                        params=(start, end),
                    )
                    entry["missing_range"] = {"start": start_s, "end": end_s, "any_rows_in_range": ok, "error": e}
            except Exception as e:  # noqa: BLE001
                entry["missing_range_error"] = str(e)

        results["items"].append(entry)

    (out_dir / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # Also emit a minimal markdown summary for quick scanning
    lines: list[str] = []
    lines.append(f"# DE US status verification — {run_id}")
    lines.append("")
    lines.append(f"- Server: `{SERVER}`")
    lines.append(f"- Database: `{DATABASE}`")
    lines.append(f"- Lakehouse: `{LAKEHOUSE}`")
    lines.append(f"- Today: `{today.isoformat()}`")
    lines.append("")
    for e in results["items"]:
        if "pair" in e:
            lines.append(f"## {e['pair'][0]} vs {e['pair'][1]}")
            lines.append(f"- Claimed: {e.get('claimed')}")
            lines.append(f"- Issue: {e.get('issue')}")
            lines.append(f"- Resolved left: {e.get('resolved_left')}")
            lines.append(f"- Resolved right: {e.get('resolved_right')}")
            if e.get("orphan_detail_rows") is not None:
                lines.append(f"- Orphan detail rows: {e['orphan_detail_rows']}")
            if e.get("error") or e.get("orphan_error"):
                lines.append(f"- Error: {e.get('error') or e.get('orphan_error')}")
            lines.append("")
            continue

        lines.append(f"## {e.get('ref')}")
        lines.append(f"- Claimed: {e.get('claimed')}")
        lines.append(f"- Issue: {e.get('issue')}")
        lines.append(f"- Resolved: {e.get('resolved')}")
        lines.append(f"- Exists: {e.get('exists')}")
        if e.get("freshness_col"):
            lines.append(
                f"- Freshness: `{e['freshness_col']}` max={e.get('freshness_max')} (days_since={e.get('freshness_days_since_max')})"
            )
        if e.get("row_count") is not None:
            lines.append(f"- Row count: {e.get('row_count')}")
        if e.get("dup"):
            lines.append(f"- Duplicates: {e['dup']}")
        if e.get("future"):
            lines.append(f"- Future-dated: {e['future']}")
        if e.get("missing_range"):
            lines.append(f"- Missing-range probe: {e['missing_range']}")
        if e.get("exists_error") or e.get("columns_error") or e.get("freshness_error"):
            lines.append(f"- Errors: {e.get('exists_error') or e.get('columns_error') or e.get('freshness_error')}")
        lines.append("")

    (out_dir / "results.md").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(str(out_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
