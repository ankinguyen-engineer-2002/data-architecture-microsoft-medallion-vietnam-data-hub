#!/usr/bin/env python3
"""Module 03 — Baseline capture pack (READ-ONLY) for Inventory Health Gold.

Freezes the behavioural oracle of system A so any future candidate B can be
reconciled coarse->fine (plan section 5.2). Per Gold target it captures from LIVE:

  - row count
  - business-key uniqueness profile (distinct key count, dup groups, max mult)
  - date coverage (min/max on each DATE/DATETIME column)
  - grand-total SUM of every numeric measure column (exact, as string)
  - category distribution for status/classification/flag columns
  - per-week reconciliation (row count + key measure sums by the primary date)

Also captures Query Insights (elapsed / cpu / rows / scans) for recent loads of
each target view, when queryinsights is accessible.

Output:
  contracts/<table>.baseline.json         (per-target frozen baseline)
  runs/<stamp>_baseline_summary.json       (run index + Query Insights)

No mutation. Read-only intent connection. Snapshot is labelled with capture
timestamp + max business date so it is only compared against an equivalent state.

Usage:
  python3 05_tools/03_gold_parity/03_baseline_capture.py
  python3 05_tools/03_gold_parity/03_baseline_capture.py --target FactInventoryHealthSnapshot
  python3 05_tools/03_gold_parity/03_baseline_capture.py --skip-query-insights
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import lib_conn as L

HERE = Path(__file__).resolve().parent
CONTRACTS = HERE / "contracts"
RUNS = HERE / "runs"

NUMERIC_TYPES = {"decimal", "numeric", "int", "bigint", "smallint", "tinyint",
                 "float", "real", "money", "smallmoney"}
DATE_TYPES = {"date", "datetime", "datetime2", "smalldatetime", "datetimeoffset"}

# Columns treated as low-cardinality categoricals for distribution capture.
CATEGORY_HINTS = ("status", "class", "isshortage", "outage", "substatus",
                  "makebuycode", "afistatus", "isactive")

# Primary date column per target (the reconciliation axis).
PRIMARY_DATE = {
    "DimCalendar": None,
    "DimProduct": None,
    "DimWarehouse": None,
    "DimVendor": None,
    "ProjectedInventoryHealthSubStatus": "FactAsOfDate",
    "InventoryHealthSubStatusWeekly": "SnapshotWeekEnding",
    "InventoryClassificationQtyWeekly": "SnapshotWeekEnding",
    "FactInventoryHealthFutureWeekEnding": "SnapshotDate",
    "FactInventoryHealthSnapshot": "SnapshotWeekEndingDate",
}


def b(col: str) -> str:
    return "[" + col.replace("]", "]]") + "]"


def classify_columns(cols: list[dict]) -> tuple[list[str], list[str], list[str]]:
    date_cols, num_cols, cat_cols = [], [], []
    for c in cols:
        name, dt = c["col"], (c["dtype"] or "").lower()
        if dt in DATE_TYPES:
            date_cols.append(name)
        elif dt in NUMERIC_TYPES:
            # ints that look like flags still summed; also flag as category if hinted
            num_cols.append(name)
        if any(h in name.lower() for h in CATEGORY_HINTS):
            cat_cols.append(name)
    return date_cols, num_cols, cat_cols


def capture_rowcount(conn, tf: str) -> int:
    return L.scalar(conn, f"SELECT COUNT(*) FROM {tf}")


def capture_key_profile(conn, tf: str, keys: list[str]) -> dict:
    if not keys:
        return {}
    kl = ", ".join(b(k) for k in keys)
    sql = f"""
        SELECT COUNT(*) AS distinct_keys,
               COALESCE(SUM(CASE WHEN c > 1 THEN 1 ELSE 0 END), 0) AS dup_groups,
               COALESCE(MAX(c), 0) AS max_mult
        FROM (SELECT {kl}, COUNT(*) AS c FROM {tf} GROUP BY {kl}) g
    """
    r = L.query(conn, sql)[0]
    return {"keys": keys, "distinct_keys": r["distinct_keys"],
            "dup_groups": r["dup_groups"], "max_mult": r["max_mult"],
            "unique_at_grain": r["dup_groups"] == 0}


def capture_date_coverage(conn, tf: str, date_cols: list[str]) -> dict:
    if not date_cols:
        return {}
    parts = []
    for c in date_cols:
        parts.append(f"MIN({b(c)}) AS [min_{c}]")
        parts.append(f"MAX({b(c)}) AS [max_{c}]")
    sql = f"SELECT {', '.join(parts)} FROM {tf}"
    return L.query(conn, sql)[0]


def capture_measure_sums(conn, tf: str, num_cols: list[str]) -> dict:
    if not num_cols:
        return {}
    # Cast to DECIMAL(38,4) to avoid overflow on big sums; keep exactness as string.
    parts = [f"CAST(SUM(CAST({b(c)} AS DECIMAL(38,6))) AS DECIMAL(38,6)) AS {b('sum_'+c)}"
             for c in num_cols]
    sql = f"SELECT {', '.join(parts)} FROM {tf}"
    row = L.query(conn, sql)[0]
    return {k: (str(v) if v is not None else None) for k, v in row.items()}


def capture_distribution(conn, tf: str, cat_cols: list[str], max_card: int = 60) -> dict:
    out = {}
    for c in cat_cols:
        sql = f"""
            SELECT CAST({b(c)} AS VARCHAR(100)) AS val, COUNT(*) AS n
            FROM {tf} GROUP BY CAST({b(c)} AS VARCHAR(100))
            ORDER BY n DESC
        """
        try:
            rows = L.query(conn, sql)
            if len(rows) <= max_card:
                out[c] = {(r["val"] if r["val"] is not None else "<NULL>"): r["n"] for r in rows}
            else:
                out[c] = {"__cardinality__": len(rows), "__note__": "too high, skipped values"}
        except Exception as e:
            out[c] = {"__error__": str(e)[:120]}
    return out


def capture_weekly_recon(conn, tf: str, date_col: str, num_cols: list[str],
                         max_measures: int = 8) -> list[dict]:
    if not date_col:
        return []
    measures = num_cols[:max_measures]
    msum = ", ".join(
        f"CAST(SUM(CAST({b(c)} AS DECIMAL(38,6))) AS DECIMAL(38,6)) AS {b('sum_'+c)}"
        for c in measures)
    sel = f"{b(date_col)} AS period, COUNT(*) AS n"
    if msum:
        sel += ", " + msum
    sql = f"SELECT {sel} FROM {tf} GROUP BY {b(date_col)} ORDER BY {b(date_col)}"
    rows = L.query(conn, sql)
    for r in rows:
        for k in list(r.keys()):
            if k.startswith("sum_") and r[k] is not None:
                r[k] = str(r[k])
    return rows


def capture_query_insights(conn, view_name: str, days: int = 30) -> list[dict]:
    """Best-effort: recent executions referencing the target view/table."""
    sql = f"""
        SELECT TOP 10
            distributed_statement_id, start_time, end_time,
            DATEDIFF(second, start_time, end_time) AS elapsed_sec,
            total_elapsed_time_ms, allocated_cpu_time_ms,
            data_scanned_remote_storage_mb, data_scanned_memory_mb,
            data_scanned_disk_mb, [status], command
        FROM queryinsights.exec_requests_history
        WHERE command LIKE ?
          AND start_time >= DATEADD(day, -{days}, SYSUTCDATETIME())
        ORDER BY start_time DESC
    """
    try:
        return L.query(conn, sql, (f"%{view_name}%",))
    except Exception as e:
        return [{"__error__": str(e)[:200]}]


def baseline_target(conn, t: L.GoldTarget, skip_qi: bool) -> dict:
    contract_path = CONTRACTS / f"{t.table}.contract.json"
    cols = json.loads(contract_path.read_text())["final_table_columns"]
    date_cols, num_cols, cat_cols = classify_columns(cols)
    tf = f"[{t.db}].[{t.schema}].[{t.table}]"
    pdate = PRIMARY_DATE.get(t.table)

    base = {
        "target_table": t.table_full,
        "captured_at_utc": L.utc_stamp(),
        "row_count": capture_rowcount(conn, tf),
        "key_profile": capture_key_profile(conn, tf, list(t.business_key)),
        "date_coverage": capture_date_coverage(conn, tf, date_cols),
        "measure_sums": capture_measure_sums(conn, tf, num_cols),
        "distribution": capture_distribution(conn, tf, cat_cols),
        "weekly_recon": capture_weekly_recon(conn, tf, pdate, num_cols),
        "columns_classified": {"date": date_cols, "numeric": num_cols, "categorical": cat_cols},
    }
    if not skip_qi:
        base["query_insights"] = capture_query_insights(conn, t.view)
    return base


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only baseline capture for Inventory Health Gold.")
    ap.add_argument("--target")
    ap.add_argument("--skip-query-insights", action="store_true")
    args = ap.parse_args()

    targets = L.GOLD_TARGETS
    if args.target:
        t = L.target_by_name(args.target)
        if not t:
            print(f"Unknown target: {args.target}")
            return 1
        targets = [t]

    RUNS.mkdir(exist_ok=True)
    conn = L.connect(L.GOLD_DB, timeout=600)
    index = {"generated_at_utc": L.utc_stamp(), "server": L.SERVER, "targets": []}

    print(f"{'STEP':>4}  {'TARGET':<48} {'ROWS':>13} {'DISTINCT_KEY':>13} {'UNIQUE':>7}")
    print("-" * 92)
    for t in targets:
        base = baseline_target(conn, t, args.skip_query_insights)
        kp = base["key_profile"]
        uniq = kp.get("unique_at_grain")
        print(f"{t.step:>4}  {t.schema+'.'+t.table:<48} "
              f"{base['row_count']:>13,} {kp.get('distinct_keys', 0):>13,} "
              f"{str(uniq):>7}")
        out = CONTRACTS / f"{t.table}.baseline.json"
        out.write_text(json.dumps(base, indent=2, default=L.json_default), encoding="utf-8")
        index["targets"].append({
            "target_table": t.table_full,
            "row_count": base["row_count"],
            "distinct_keys": kp.get("distinct_keys"),
            "unique_at_grain": uniq,
            "date_coverage": base["date_coverage"],
        })

    conn.close()
    idx_out = RUNS / f"{index['generated_at_utc']}_baseline_summary.json"
    idx_out.write_text(json.dumps(index, indent=2, default=L.json_default), encoding="utf-8")
    print(f"\nWrote {len(targets)} baseline file(s) to {CONTRACTS}")
    print(f"Run index: {idx_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
