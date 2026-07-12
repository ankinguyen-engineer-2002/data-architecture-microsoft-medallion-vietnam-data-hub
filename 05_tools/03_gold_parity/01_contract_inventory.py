#!/usr/bin/env python3
"""Module 01 — Contract Inventory (Layer A static contract & lineage capture).

READ-ONLY. For each of the 9 Inventory Health Gold targets, capture from LIVE:
  - physical final-table column contract (INFORMATION_SCHEMA.COLUMNS)
  - _Wrk view definition (sys.sql_modules / OBJECT_DEFINITION)
  - view output columns (INFORMATION_SCHEMA.COLUMNS on the view)
  - column-count / order parity between view and final table
    (the loader uses INSERT ... SELECT *, so drift here breaks the load —
     this is the exact failure class that broke DimWarehouse on 2026-07-03)
  - light static parse of the view SQL: CTE list, ROW_NUMBER, GROUP BY,
    DISTINCT, LEFT/INNER JOIN count, CASE count, latest/as-of ordering markers.

Output: 05_tools/03_gold_parity/contracts/<table>.contract.json  (versioned)
        05_tools/03_gold_parity/runs/<stamp>_contract_inventory.json (run summary)

No mutation. No production object is altered.

Usage:
    python3 05_tools/03_gold_parity/01_contract_inventory.py
    python3 05_tools/03_gold_parity/01_contract_inventory.py --target FactInventoryHealthSnapshot
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import lib_conn as L


def get_view_definition(conn, view_schema: str, view: str) -> str | None:
    sql = """
        SELECT m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE s.name = ? AND o.name = ?
    """
    return L.scalar(conn, sql, (view_schema, view))


def get_columns(conn, schema: str, name: str) -> list[dict]:
    sql = """
        SELECT ORDINAL_POSITION AS pos, COLUMN_NAME AS col, DATA_TYPE AS dtype,
               CHARACTER_MAXIMUM_LENGTH AS maxlen, NUMERIC_PRECISION AS prec,
               NUMERIC_SCALE AS scale, IS_NULLABLE AS is_nullable
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    """
    return L.query(conn, sql, (schema, name))


def object_modify_date(conn, schema: str, name: str) -> str | None:
    sql = """
        SELECT CONVERT(VARCHAR(33), o.modify_date, 126) AS modify_date
        FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE s.name = ? AND o.name = ?
    """
    return L.scalar(conn, sql, (schema, name))


def static_parse(sql_text: str) -> dict:
    if not sql_text:
        return {}
    upper = sql_text.upper()
    ctes = re.findall(r"(?:WITH|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(", sql_text)
    latest_markers = re.findall(
        r"ISLATEST\w*|ROW_NUMBER\s*\(\)\s*OVER|<=\s*\w*ASOFDATE|ORDER\s+BY\s+\w*DATE\w*\s+DESC",
        upper,
    )
    return {
        "cte_names": ctes,
        "cte_count": len(ctes),
        "row_number_count": upper.count("ROW_NUMBER"),
        "group_by_count": upper.count("GROUP BY"),
        "distinct_count": upper.count("DISTINCT"),
        "left_join_count": upper.count("LEFT JOIN"),
        "inner_join_count": len(re.findall(r"(?<!LEFT )(?<!RIGHT )\bJOIN\b", upper))
                            - upper.count("LEFT JOIN") - upper.count("RIGHT JOIN"),
        "case_count": upper.count(" CASE "),
        "coalesce_count": upper.count("COALESCE"),
        "latest_asof_markers": len(latest_markers),
        "reads_islatest_flag": "ISLATEST" in upper,
        "has_partition_dedupe": "ROW_NUMBER" in upper and "PARTITION BY" in upper,
    }


def extract_source_refs(sql_text: str) -> list[str]:
    """Extract 3-part [db].[schema].[table] references from FROM/JOIN clauses."""
    if not sql_text:
        return []
    pat = re.compile(
        r"\[([A-Za-z0-9_]+)\]\.\[([A-Za-z0-9_]+)\]\.\[([A-Za-z0-9_]+)\]"
    )
    refs = {f"{m.group(1)}.{m.group(2)}.{m.group(3)}" for m in pat.finditer(sql_text)}
    return sorted(refs)


def build_contract(conn, t: L.GoldTarget) -> dict:
    view_def = get_view_definition(conn, t.view_schema, t.view)
    table_cols = get_columns(conn, t.schema, t.table)
    view_cols = get_columns(conn, t.view_schema, t.view)

    table_col_names = [c["col"] for c in table_cols]
    view_col_names = [c["col"] for c in view_cols]

    # Loader uses INSERT ... SELECT * -> positional contract must match.
    col_count_match = len(table_col_names) == len(view_col_names)
    order_match = table_col_names == view_col_names
    drift_cols = {
        "in_view_not_table": [c for c in view_col_names if c not in table_col_names],
        "in_table_not_view": [c for c in table_col_names if c not in view_col_names],
    }

    return {
        "step": t.step,
        "wave": t.wave,
        "target_table": t.table_full,
        "source_view": t.view_full,
        "is_hotspot": t.is_hotspot,
        "declared_business_key": list(t.business_key),
        "table_modify_date_utc": object_modify_date(conn, t.schema, t.table),
        "view_modify_date_utc": object_modify_date(conn, t.view_schema, t.view),
        "final_table_columns": table_cols,
        "view_columns": view_cols,
        "loader_positional_contract": {
            "loader": "ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView (INSERT ... SELECT *)",
            "table_column_count": len(table_col_names),
            "view_column_count": len(view_col_names),
            "column_count_match": col_count_match,
            "column_order_match": order_match,
            "drift": drift_cols,
            "load_safe": col_count_match,
        },
        "source_refs": extract_source_refs(view_def),
        "static_parse": static_parse(view_def or ""),
        "view_definition": view_def,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only contract inventory for Inventory Health Gold.")
    ap.add_argument("--target", help="Single target table/view name (optional).")
    ap.add_argument("--no-write", action="store_true", help="Print only, do not write contract files.")
    args = ap.parse_args()

    targets = L.GOLD_TARGETS
    if args.target:
        t = L.target_by_name(args.target)
        if not t:
            print(f"Unknown target: {args.target}")
            return 1
        targets = [t]

    here = Path(__file__).resolve().parent
    contracts_dir = here / "contracts"
    runs_dir = here / "runs"
    contracts_dir.mkdir(exist_ok=True)
    runs_dir.mkdir(exist_ok=True)

    conn = L.connect(L.GOLD_DB)
    summary = {"generated_at_utc": L.utc_stamp(), "server": L.SERVER,
               "database": L.GOLD_DB, "targets": []}

    print(f"{'STEP':>4}  {'TARGET':<48} {'COLS(v/t)':<12} LOAD_SAFE  DRIFT")
    print("-" * 100)
    for t in targets:
        c = build_contract(conn, t)
        lp = c["loader_positional_contract"]
        drift_n = len(lp["drift"]["in_view_not_table"]) + len(lp["drift"]["in_table_not_view"])
        flag = "OK " if lp["load_safe"] else "FAIL"
        print(f"{t.step:>4}  {t.schema+'.'+t.table:<48} "
              f"{str(lp['view_column_count'])+'/'+str(lp['table_column_count']):<12} "
              f"{flag:<9} {drift_n}")
        if drift_n:
            print(f"        drift in_view_not_table={lp['drift']['in_view_not_table']}")
            print(f"        drift in_table_not_view={lp['drift']['in_table_not_view']}")

        summary["targets"].append({
            "target_table": c["target_table"],
            "load_safe": lp["load_safe"],
            "view_cols": lp["view_column_count"],
            "table_cols": lp["table_column_count"],
            "drift_count": drift_n,
            "source_refs": c["source_refs"],
            "static_parse": c["static_parse"],
        })

        if not args.no_write:
            out = contracts_dir / f"{t.table}.contract.json"
            out.write_text(json.dumps(c, indent=2, default=L.json_default), encoding="utf-8")

    conn.close()

    if not args.no_write:
        run_out = runs_dir / f"{summary['generated_at_utc']}_contract_inventory.json"
        run_out.write_text(json.dumps(summary, indent=2, default=L.json_default), encoding="utf-8")
        print(f"\nWrote {len(targets)} contract file(s) to {contracts_dir}")
        print(f"Run summary: {run_out}")

    unsafe = [x for x in summary["targets"] if not x["load_safe"]]
    if unsafe:
        print(f"\n[WARN] {len(unsafe)} target(s) have loader positional drift (view vs table).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
