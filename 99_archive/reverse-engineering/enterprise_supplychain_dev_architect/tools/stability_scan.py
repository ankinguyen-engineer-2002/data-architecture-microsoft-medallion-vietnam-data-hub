#!/usr/bin/env python3
"""Comprehensive stability scan for SupplyChain_Processing_Warehouse (v10)."""

from __future__ import annotations

import json
import struct
import subprocess
import sys
import traceback

import pyodbc

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DB = "SupplyChain_Processing_Warehouse"

OLD_SCHEMAS = {"Staging", "ReferenceMaster", "SalesHistory", "ForecastHistory", "OpenOrderHistory", "ForecastAccuracy"}
# Bob-aligned PascalCase per ADR-008 (2026-05-10): _Enh / _Wrk (was _ENH / _WRK pre-rebuild)
NEW_SCHEMAS = {"Staging_Wrk", "ReferenceMaster_Enh", "SalesHistory_Enh", "ForecastHistory_Enh", "OpenOrderHistory_Enh", "Meta"}


def get_token_struct() -> bytes:
    raw = subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
    ).decode().strip()
    token_bytes = raw.encode("UTF-16-LE")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


def connect() -> pyodbc.Connection:
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DB};"
        "Encrypt=Yes;TrustServerCertificate=No",
        attrs_before={1256: get_token_struct()},
        timeout=60,
    )


def scalar(cur, sql, params=(), retries: int = 3):
    import time
    for attempt in range(retries):
        try:
            cur.execute(sql, params)
            row = cur.fetchone()
            return row[0] if row else None
        except pyodbc.Error as e:
            if "1205" in str(e) and attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise


def fetchall(cur, sql, params=(), retries: int = 3):
    import time
    for attempt in range(retries):
        try:
            cur.execute(sql, params)
            cols = [c[0] for c in cur.description]
            return [dict(zip(cols, r)) for r in cur.fetchall()]
        except pyodbc.Error as e:
            if "1205" in str(e) and attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise


def print_table(rows: list[dict], title: str = ""):
    if title:
        print(f"\n### {title}")
    if not rows:
        print("  (no rows)")
        return
    keys = list(rows[0].keys())
    col_widths = {k: max(len(str(k)), max(len(str(r.get(k, ""))) for r in rows)) for k in keys}
    header = "  " + " | ".join(str(k).ljust(col_widths[k]) for k in keys)
    sep = "  " + "-+-".join("-" * col_widths[k] for k in keys)
    print(header)
    print(sep)
    for r in rows:
        print("  " + " | ".join(str(r.get(k, "")).ljust(col_widths[k]) for k in keys))


def check_snake_case_columns(cur, schema: str, table: str) -> tuple[bool, int]:
    """Returns (has_snake_case, column_count). snake_case = contains underscore in non-system column names."""
    sql = """
        SELECT c.name
        FROM sys.columns c
        JOIN sys.objects o ON o.object_id = c.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE s.name = ? AND o.name = ?
    """
    cur.execute(sql, (schema, table))
    cols = [row[0] for row in cur.fetchall()]
    # System/meta columns that legitimately have underscores are allowed
    system_prefixes = {"_", "row_hash", "dw_", "etl_", "src_", "meta_"}
    snake = [c for c in cols if "_" in c and not any(c.startswith(p) for p in system_prefixes)]
    return bool(snake), len(cols)


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1 — Schema inventory
# ─────────────────────────────────────────────────────────────────────────────
def check_schemas(cur):
    print("\n" + "=" * 70)
    print("CHECK 1 — Schema Inventory")
    print("=" * 70)
    all_schemas = fetchall(cur, """
        SELECT name AS schema_name
        FROM sys.schemas
        WHERE name NOT IN ('dbo','sys','INFORMATION_SCHEMA','guest',
                           'db_owner','db_accessadmin','db_securityadmin',
                           'db_ddladmin','db_backupoperator','db_datareader',
                           'db_datawriter','db_denydatareader','db_denydatawriter')
        ORDER BY name
    """)

    results = []
    for s in all_schemas:
        name = s["schema_name"]
        is_expected = name in NEW_SCHEMAS
        is_old = name in OLD_SCHEMAS
        flag = "FLAG_OLD" if is_old else ("OK" if is_expected else "UNEXPECTED")
        results.append({"schema_name": name, "expected": str(is_expected), "status": flag})

    print_table(results, "All Non-System Schemas")

    old_found = [r for r in results if r["status"] == "FLAG_OLD"]
    missing_new = [s for s in NEW_SCHEMAS if s not in {r["schema_name"] for r in results}]
    if old_found:
        print(f"\n  [FLAG] Old schemas still present: {[r['schema_name'] for r in old_found]}")
    else:
        print("\n  [OK] No old schemas detected.")
    if missing_new:
        print(f"  [FLAG] Expected new schemas missing: {missing_new}")
    else:
        print("  [OK] All expected new schemas present.")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2 — Table scan (_Enh and _Wrk schemas)
# ─────────────────────────────────────────────────────────────────────────────
def check_tables(cur):
    print("\n" + "=" * 70)
    print("CHECK 2 — Table Scan (_Enh and _Wrk schemas)")
    print("=" * 70)

    tables = fetchall(cur, """
        SELECT s.name AS schema_name, t.name AS table_name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE LOWER(s.name) LIKE '%[_]enh' OR LOWER(s.name) LIKE '%[_]wrk'
        ORDER BY s.name, t.name
    """)

    results = []
    for tbl in tables:
        schema = tbl["schema_name"]
        table = tbl["table_name"]
        try:
            row_count = scalar(cur, f"SELECT COUNT(*) FROM [{schema}].[{table}]")
            has_snake, col_count = check_snake_case_columns(cur, schema, table)
            results.append({
                "schema": schema,
                "table": table,
                "row_count": row_count,
                "has_snake_case": str(has_snake),
                "col_count": col_count,
            })
        except Exception as e:
            results.append({
                "schema": schema,
                "table": table,
                "row_count": "ERROR",
                "has_snake_case": "ERROR",
                "col_count": f"{e}",
            })

    print_table(results, f"Tables in _Enh/_Wrk schemas ({len(results)} total)")
    snake_flagged = [r for r in results if r["has_snake_case"] == "True"]
    if snake_flagged:
        print(f"\n  [FLAG] Tables with snake_case columns: {[(r['schema'], r['table']) for r in snake_flagged]}")
    else:
        print("\n  [OK] No snake_case columns detected in _Enh/_Wrk tables.")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3 — View validation (_Enh and _Wrk schemas)
# ─────────────────────────────────────────────────────────────────────────────
def check_views(cur):
    print("\n" + "=" * 70)
    print("CHECK 3 — View Validation (_Enh and _Wrk schemas)")
    print("=" * 70)

    views = fetchall(cur, """
        SELECT s.name AS schema_name, v.name AS view_name
        FROM sys.views v
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE LOWER(s.name) LIKE '%[_]enh' OR LOWER(s.name) LIKE '%[_]wrk'
        ORDER BY s.name, v.name
    """)

    results = []
    for vw in views:
        schema = vw["schema_name"]
        view = vw["view_name"]
        try:
            cur.execute(f"SELECT TOP 1 * FROM [{schema}].[{view}]")
            cols = [c[0] for c in cur.description]
            cur.fetchall()
            results.append({
                "schema": schema,
                "view": view,
                "status": "OK",
                "col_1": cols[0] if len(cols) > 0 else "",
                "col_2": cols[1] if len(cols) > 1 else "",
                "col_3": cols[2] if len(cols) > 2 else "",
            })
        except Exception as e:
            results.append({
                "schema": schema,
                "view": view,
                "status": f"ERROR: {str(e)[:80]}",
                "col_1": "",
                "col_2": "",
                "col_3": "",
            })

    print_table(results, f"Views in _Enh/_Wrk schemas ({len(results)} total)")
    errors = [r for r in results if r["status"].startswith("ERROR")]
    if errors:
        print(f"\n  [FLAG] {len(errors)} view(s) with errors: {[r['view'] for r in errors]}")
    else:
        print(f"\n  [OK] All {len(results)} views validated successfully.")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4 — Meta tables scan
# ─────────────────────────────────────────────────────────────────────────────
def check_meta_tables(cur):
    print("\n" + "=" * 70)
    print("CHECK 4 — Meta Schema Table Scan")
    print("=" * 70)

    meta_tables = fetchall(cur, """
        SELECT t.name AS table_name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'Meta'
        ORDER BY t.name
    """)

    results = []
    key_tables = {"AssetRegistry", "DQRule", "LineageEdge", "RunLog", "PipelineRunLog",
                  "SourceContract", "SilverDagWaveRuntime"}

    for tbl in meta_tables:
        table = tbl["table_name"]
        try:
            row_count = scalar(cur, f"SELECT COUNT(*) FROM [Meta].[{table}]")
            is_key = table in key_tables
            results.append({
                "table": table,
                "row_count": row_count,
                "key_table": str(is_key),
            })
        except Exception as e:
            results.append({
                "table": table,
                "row_count": "ERROR",
                "key_table": str(table in key_tables),
            })

    print_table(results, f"Meta schema tables ({len(results)} total)")

    missing_key = [t for t in key_tables if t not in {r["table"] for r in results}]
    if missing_key:
        print(f"\n  [FLAG] Key Meta tables missing: {missing_key}")
    else:
        print("\n  [OK] All key Meta tables present.")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5 — AssetRegistry consistency
# ─────────────────────────────────────────────────────────────────────────────
def check_asset_registry(cur):
    print("\n" + "=" * 70)
    print("CHECK 5 — AssetRegistry Consistency")
    print("=" * 70)

    # Try both AssetRegistry and AssetRegistryV10 naming
    ar_table = None
    for candidate in ("AssetRegistry", "AssetRegistryV10"):
        try:
            scalar(cur, f"SELECT COUNT(*) FROM [Meta].[{candidate}]")
            ar_table = candidate
            break
        except Exception:
            pass

    if not ar_table:
        print("  [FLAG] Neither Meta.AssetRegistry nor Meta.AssetRegistryV10 found.")
        return

    print(f"  Using table: Meta.{ar_table}")

    try:
        schema_dist = fetchall(cur, f"""
            SELECT physical_schema, COUNT(*) AS asset_count
            FROM [Meta].[{ar_table}]
            GROUP BY physical_schema
            ORDER BY physical_schema
        """)
        print_table(schema_dist, "physical_schema distribution")

        old_schema_assets = fetchall(cur, f"""
            SELECT physical_schema, asset_name, asset_type
            FROM [Meta].[{ar_table}]
            WHERE physical_schema IN ('Staging','ReferenceMaster','SalesHistory',
                                      'ForecastHistory','OpenOrderHistory','ForecastAccuracy')
            ORDER BY physical_schema, asset_name
        """)
        if old_schema_assets:
            print_table(old_schema_assets, "[FLAG] Assets with OLD schema names")
        else:
            print("\n  [OK] No assets reference old schema names.")
    except Exception as e:
        # Fallback: try without physical_schema column
        print(f"  [WARN] physical_schema column query failed: {e}")
        try:
            cols = fetchall(cur, f"""
                SELECT c.name AS col_name
                FROM sys.columns c
                JOIN sys.objects o ON o.object_id = c.object_id
                JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE s.name = 'Meta' AND o.name = '{ar_table}'
                ORDER BY c.column_id
            """)
            col_names = [c["col_name"] for c in cols]
            print(f"  Available columns: {col_names}")
        except Exception as e2:
            print(f"  [ERROR] Cannot inspect columns: {e2}")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 6 — DQRule consistency
# ─────────────────────────────────────────────────────────────────────────────
def check_dq_rules(cur):
    print("\n" + "=" * 70)
    print("CHECK 6 — DQRule Consistency")
    print("=" * 70)

    try:
        schema_dist = fetchall(cur, """
            SELECT target_schema, COUNT(*) AS rule_count
            FROM [Meta].[DQRule]
            GROUP BY target_schema
            ORDER BY target_schema
        """)
        print_table(schema_dist, "target_schema distribution")

        old_schema_rules = fetchall(cur, """
            SELECT target_schema, rule_name, column_name
            FROM [Meta].[DQRule]
            WHERE target_schema IN ('Staging','ReferenceMaster','SalesHistory',
                                    'ForecastHistory','OpenOrderHistory','ForecastAccuracy')
            ORDER BY target_schema, rule_name
        """)
        if old_schema_rules:
            print_table(old_schema_rules, "[FLAG] DQRules with OLD schema names")
        else:
            print("\n  [OK] No DQRules reference old schema names.")

        # Check column_name for snake_case (underscore = snake case for business columns)
        snake_cols = fetchall(cur, """
            SELECT rule_name, column_name, target_schema, target_table
            FROM [Meta].[DQRule]
            WHERE column_name LIKE '%[_]%'
              AND column_name NOT IN ('source_row_number','row_hash','dw_insert_ts','etl_batch_id')
            ORDER BY target_schema, rule_name
        """)
        if snake_cols:
            print_table(snake_cols, "[FLAG] DQRules with snake_case column_name")
        else:
            print("\n  [OK] No snake_case column_name values detected in DQRule.")

    except Exception as e:
        print(f"  [ERROR] DQRule check failed: {e}")
        traceback.print_exc()


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 7 — SP / Function inventory
# ─────────────────────────────────────────────────────────────────────────────
def check_sp_functions(cur):
    print("\n" + "=" * 70)
    print("CHECK 7 — Stored Procedures & Functions")
    print("=" * 70)

    sps = fetchall(cur, """
        SELECT s.name AS schema_name, p.name AS proc_name, p.type_desc
        FROM sys.procedures p
        JOIN sys.schemas s ON s.schema_id = p.schema_id
        WHERE s.name NOT IN ('sys')
        ORDER BY s.name, p.name
    """)
    print_table(sps, f"Stored Procedures ({len(sps)} total)")

    funcs = fetchall(cur, """
        SELECT s.name AS schema_name, o.name AS func_name, o.type_desc
        FROM sys.objects o
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.type IN ('FN','IF','TF')
          AND s.name NOT IN ('sys')
        ORDER BY s.name, o.name
    """)
    print_table(funcs, f"Functions ({len(funcs)} total)")

    # Verify usp_RefreshEdwTables
    target_sp = next(
        (p for p in sps if p["schema_name"] == "Staging_Wrk" and p["proc_name"] == "usp_RefreshEdwTables"),
        None
    )
    if target_sp:
        print("\n  [OK] Staging_Wrk.usp_RefreshEdwTables exists.")
    else:
        print("\n  [FLAG] Staging_Wrk.usp_RefreshEdwTables NOT FOUND.")


# ─────────────────────────────────────────────────────────────────────────────
# CHECK 8 — RunLog latest 5 entries
# ─────────────────────────────────────────────────────────────────────────────
def check_runlog(cur):
    print("\n" + "=" * 70)
    print("CHECK 8 — RunLog Latest 5 Entries")
    print("=" * 70)

    # Try RunLog first, then PipelineRunLog
    for table in ("RunLog", "PipelineRunLog"):
        try:
            cols_info = fetchall(cur, f"""
                SELECT c.name
                FROM sys.columns c
                JOIN sys.objects o ON o.object_id = c.object_id
                JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE s.name = 'Meta' AND o.name = '{table}'
                ORDER BY c.column_id
            """)
            col_names = [c["name"] for c in cols_info]

            # Pick timestamp column heuristically
            ts_col = next(
                (c for c in col_names if any(kw in c.lower() for kw in ["ts", "time", "date", "start", "end", "created"])),
                col_names[0] if col_names else None
            )

            if ts_col:
                rows_data = fetchall(cur, f"""
                    SELECT TOP 5 *
                    FROM [Meta].[{table}]
                    ORDER BY [{ts_col}] DESC
                """)
            else:
                rows_data = fetchall(cur, f"SELECT TOP 5 * FROM [Meta].[{table}]")

            print_table(rows_data, f"Meta.{table} — latest 5 rows (ordered by {ts_col})")
            break
        except Exception as e:
            print(f"  [WARN] Meta.{table} not accessible: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
def main():
    print("=" * 70)
    print(f"STABILITY SCAN — {DB}")
    print(f"Server: {SERVER}")
    print("=" * 70)

    try:
        conn = connect()
        cur = conn.cursor()
        print("  [OK] Connected successfully.\n")
    except Exception as e:
        print(f"  [FATAL] Connection failed: {e}")
        sys.exit(1)

    check_schemas(cur)
    check_tables(cur)
    check_views(cur)
    check_meta_tables(cur)
    check_asset_registry(cur)
    check_dq_rules(cur)
    check_sp_functions(cur)
    check_runlog(cur)

    print("\n" + "=" * 70)
    print("SCAN COMPLETE")
    print("=" * 70)
    conn.close()


if __name__ == "__main__":
    main()
