#!/usr/bin/env python3
"""Stability scan for SupplyChain_Gold_Warehouse.

Checks:
  1. Schema inventory — only ForecastAccuracy_DW should exist (not old ForecastAccuracy)
  2. Table scan — COUNT(*) + columns for all 7 tables, PascalCase check
  3. View validation — SELECT TOP 1 from all 7 views in ForecastAccuracy_DW
  4. Star schema FK alignment check
  5. Snake_case column audit across all tables
"""

from __future__ import annotations

import struct
import subprocess
import json

import pyodbc

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DB = "SupplyChain_Gold_Warehouse"

EXPECTED_TABLES = [
    "FactForecastActual",
    "FactForecastKpi",
    "DimCalendar",
    "DimCustomerGrouping",
    "DimWarehouse",
    "DimProduct",
    "DimForecastHorizon",
]

# Expected FK -> PK alignments: (fact_table, fk_col, dim_table, pk_col)
STAR_SCHEMA_LINKS = [
    ("FactForecastActual", "ItemSKU",          "DimProduct",         "ItemSKU"),
    ("FactForecastActual", "CalendarDate",      "DimCalendar",        "CalendarDate"),
    ("FactForecastActual", "WarehouseCode",     "DimWarehouse",       "WarehouseCode"),
    ("FactForecastActual", "CustomerGroupKey",  "DimCustomerGrouping","CustomerGroupKey"),
    ("FactForecastActual", "HorizonBucket",     "DimForecastHorizon", "HorizonBucket"),
    ("FactForecastKpi",    "ItemSKU",           "DimProduct",         "ItemSKU"),
    ("FactForecastKpi",    "CalendarDate",      "DimCalendar",        "CalendarDate"),
    ("FactForecastKpi",    "WarehouseCode",     "DimWarehouse",       "WarehouseCode"),
    ("FactForecastKpi",    "CustomerGroupKey",  "DimCustomerGrouping","CustomerGroupKey"),
    ("FactForecastKpi",    "HorizonBucket",     "DimForecastHorizon", "HorizonBucket"),
]


def get_token_struct() -> bytes:
    raw = subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
    ).decode().strip()
    token_bytes = raw.encode("UTF-16-LE")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


def get_conn() -> pyodbc.Connection:
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={SERVER};DATABASE={DB};Encrypt=Yes;TrustServerCertificate=No",
        attrs_before={1256: get_token_struct()},
        timeout=60,
    )


def fetchall_dicts(cur: pyodbc.Cursor, sql: str, params: tuple = ()) -> list[dict]:
    cur.execute(sql, params)
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def scalar(cur: pyodbc.Cursor, sql: str, params: tuple = ()) -> object:
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


# ─────────────────────────────────────────────
# CHECK 1: Schema inventory
# ─────────────────────────────────────────────
def check_schemas(cur: pyodbc.Cursor) -> None:
    print("\n" + "=" * 60)
    print("CHECK 1: SCHEMA INVENTORY")
    print("=" * 60)
    schemas = fetchall_dicts(cur, """
        SELECT name AS schema_name
        FROM sys.schemas
        WHERE principal_id = 1          -- dbo-owned, excludes sys/INFORMATION_SCHEMA
           OR name IN ('ForecastAccuracy','ForecastAccuracy_DW','dbo')
        ORDER BY name;
    """)
    # Widen: list ALL non-system schemas
    all_schemas = fetchall_dicts(cur, """
        SELECT s.name AS schema_name,
               dp.name AS owner
        FROM sys.schemas s
        JOIN sys.database_principals dp ON dp.principal_id = s.principal_id
        WHERE s.name NOT IN (
            'sys','INFORMATION_SCHEMA','db_owner','db_accessadmin',
            'db_securityadmin','db_ddladmin','db_backupoperator',
            'db_datareader','db_datawriter','db_denydatareader','db_denydatawriter'
        )
        ORDER BY s.name;
    """)
    print(f"\n{'Schema':<30} {'Owner':<20}")
    print("-" * 50)
    for r in all_schemas:
        flag = ""
        if r["schema_name"] == "ForecastAccuracy":
            flag = "  <-- OLD — SHOULD NOT EXIST"
        elif r["schema_name"] == "ForecastAccuracy_DW":
            flag = "  <-- EXPECTED"
        print(f"{r['schema_name']:<30} {r['owner']:<20}{flag}")

    has_old   = any(r["schema_name"] == "ForecastAccuracy"    for r in all_schemas)
    has_new   = any(r["schema_name"] == "ForecastAccuracy_DW" for r in all_schemas)
    result    = "PASS" if (not has_old and has_new) else "FAIL"
    print(f"\nOld schema ForecastAccuracy present : {has_old}")
    print(f"New schema ForecastAccuracy_DW present: {has_new}")
    print(f"Schema check result: {result}")


# ─────────────────────────────────────────────
# CHECK 2: Table scan
# ─────────────────────────────────────────────
def check_tables(cur: pyodbc.Cursor) -> dict[str, list[str]]:
    print("\n" + "=" * 60)
    print("CHECK 2: TABLE SCAN (row count + columns)")
    print("=" * 60)

    # First discover what schema the tables live in
    present = fetchall_dicts(cur, """
        SELECT s.name AS schema_name, t.name AS table_name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.name IN ({})
        ORDER BY t.name;
    """.format(",".join(f"'{n}'" for n in EXPECTED_TABLES)))

    table_schema_map = {r["table_name"]: r["schema_name"] for r in present}
    present_names    = set(table_schema_map.keys())
    missing          = set(EXPECTED_TABLES) - present_names

    if missing:
        print(f"\nMISSING TABLES: {sorted(missing)}")

    print(f"\n{'Table':<30} {'Schema':<22} {'Rows':>8} {'Cols':>5}  {'PascalCase?':<12}  Columns")
    print("-" * 140)

    table_columns: dict[str, list[str]] = {}

    for tbl in EXPECTED_TABLES:
        if tbl not in table_schema_map:
            print(f"{tbl:<30} {'NOT FOUND':<22}")
            table_columns[tbl] = []
            continue

        schema = table_schema_map[tbl]
        fq = f"[{schema}].[{tbl}]"

        try:
            row_count = scalar(cur, f"SELECT COUNT(*) FROM {fq}")
        except Exception as e:
            row_count = f"ERR:{e}"

        cols = fetchall_dicts(cur, """
            SELECT c.name AS col_name
            FROM sys.columns c
            JOIN sys.tables t  ON t.object_id  = c.object_id
            JOIN sys.schemas s ON s.schema_id  = t.schema_id
            WHERE t.name = ? AND s.name = ?
            ORDER BY c.column_id;
        """, (tbl, schema))

        col_names = [c["col_name"] for c in cols]
        table_columns[tbl] = col_names

        # PascalCase check: no underscores, starts with uppercase
        snake_cols  = [c for c in col_names if "_" in c]
        lower_start = [c for c in col_names if c and c[0].islower()]
        pascal_ok   = "YES" if not snake_cols and not lower_start else "NO"

        cols_str = ", ".join(col_names)
        print(f"{tbl:<30} {schema:<22} {str(row_count):>8} {len(col_names):>5}  {pascal_ok:<12}  {cols_str}")

    return table_columns


# ─────────────────────────────────────────────
# CHECK 3: View validation
# ─────────────────────────────────────────────
def check_views(cur: pyodbc.Cursor) -> None:
    print("\n" + "=" * 60)
    print("CHECK 3: VIEW VALIDATION (SELECT TOP 1)")
    print("=" * 60)

    views = fetchall_dicts(cur, """
        SELECT s.name AS schema_name, v.name AS view_name
        FROM sys.views v
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE s.name = 'ForecastAccuracy_DW'
        ORDER BY v.name;
    """)

    if not views:
        print("  No views found in schema ForecastAccuracy_DW")
        return

    print(f"\n{'View':<40} {'Schema':<22} {'Status':<10}  Note")
    print("-" * 100)

    for v in views:
        fq = f"[{v['schema_name']}].[{v['view_name']}]"
        try:
            cur.execute(f"SELECT TOP 1 * FROM {fq}")
            cur.fetchall()
            status = "OK"
            note   = ""
        except Exception as e:
            status = "FAIL"
            note   = str(e)[:80]
        print(f"{v['view_name']:<40} {v['schema_name']:<22} {status:<10}  {note}")

    if len(views) < 7:
        print(f"\n  WARNING: only {len(views)} view(s) found, expected 7.")


# ─────────────────────────────────────────────
# CHECK 4: Star schema FK alignment
# ─────────────────────────────────────────────
def check_star_schema(cur: pyodbc.Cursor, table_columns: dict[str, list[str]]) -> None:
    print("\n" + "=" * 60)
    print("CHECK 4: STAR SCHEMA FK ALIGNMENT")
    print("=" * 60)

    print(f"\n{'Fact Table':<25} {'FK Col':<22} {'Dim Table':<25} {'Dim PK Col':<22} {'Aligned?'}")
    print("-" * 105)

    for fact_tbl, fk_col, dim_tbl, pk_col in STAR_SCHEMA_LINKS:
        fact_cols = table_columns.get(fact_tbl, [])
        dim_cols  = table_columns.get(dim_tbl,  [])
        fk_present = fk_col in fact_cols
        pk_present = pk_col in dim_cols
        aligned    = "YES" if fk_present and pk_present else "NO"
        detail     = ""
        if not fk_present:
            detail += f"  FK '{fk_col}' missing from {fact_tbl}"
        if not pk_present:
            detail += f"  PK '{pk_col}' missing from {dim_tbl}"
        print(f"{fact_tbl:<25} {fk_col:<22} {dim_tbl:<25} {pk_col:<22} {aligned}{detail}")


# ─────────────────────────────────────────────
# CHECK 5: Snake_case column audit
# ─────────────────────────────────────────────
def check_snake_case(cur: pyodbc.Cursor) -> None:
    print("\n" + "=" * 60)
    print("CHECK 5: SNAKE_CASE COLUMN AUDIT (all tables)")
    print("=" * 60)

    snake_hits = fetchall_dicts(cur, """
        SELECT
            s.name   AS schema_name,
            t.name   AS table_name,
            c.name   AS column_name,
            c.column_id
        FROM sys.columns c
        JOIN sys.tables  t ON t.object_id  = c.object_id
        JOIN sys.schemas s ON s.schema_id  = t.schema_id
        WHERE c.name LIKE '%[_]%'
          AND s.name NOT IN (
              'sys','INFORMATION_SCHEMA','db_owner','db_accessadmin',
              'db_securityadmin','db_ddladmin','db_backupoperator',
              'db_datareader','db_datawriter','db_denydatareader','db_denydatawriter'
          )
        ORDER BY s.name, t.name, c.column_id;
    """)

    if not snake_hits:
        print("\n  PASS — no snake_case columns found across any table.")
    else:
        print(f"\n  FAIL — {len(snake_hits)} snake_case column(s) found:\n")
        print(f"  {'Schema':<22} {'Table':<30} {'Column':<40}")
        print("  " + "-" * 92)
        for r in snake_hits:
            print(f"  {r['schema_name']:<22} {r['table_name']:<30} {r['column_name']:<40}")


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
def main() -> None:
    print(f"Connecting to {DB} on {SERVER[:40]}...")
    conn = get_conn()
    cur  = conn.cursor()
    print("Connected.")

    check_schemas(cur)
    table_columns = check_tables(cur)
    check_views(cur)
    check_star_schema(cur, table_columns)
    check_snake_case(cur)

    print("\n" + "=" * 60)
    print("SCAN COMPLETE")
    print("=" * 60)
    conn.close()


if __name__ == "__main__":
    main()
