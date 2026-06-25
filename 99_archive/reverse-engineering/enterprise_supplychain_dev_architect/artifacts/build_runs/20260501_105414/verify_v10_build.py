#!/usr/bin/env python3
"""Verify v9 cleanup and v10 scaffold state."""

from __future__ import annotations

import json
import struct
import subprocess
from pathlib import Path

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
FABRIC_BASE = "https://api.fabric.microsoft.com/v1"
OUT = Path("Enterprise_SupplyChain_Dev_architect/build_runs/20260501_105414/v10_final_verification.json")


DELETED_TARGETS = {
    "SC_Control_Tower",
    "pl_sc_master",
    "pl_sc_mart",
    "pl_sc_bronze",
    "pl_sc_silver",
    "pl_sc_silver_wave",
    "pl_sc_gold",
    "pl_dq_check",
}

PROTECTED_TARGETS = {
    "Forecast Accuracy Gold",
    "SupplyChain_Gold",
    "Supply Chain Control Tower",
    "Enterprise_Lakehouse",
    "SupplyChain_Warehouse",
    "SupplyChain_Lakehouse",
    "df_brz_SalesHistory_AFI_InvoiceDetail",
    "df_brz_SalesHistory_AFI_InvoiceHeader",
    "df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1",
    "df_ref_product",
}

CREATED_TARGETS = {
    "SupplyChain_Processing_Warehouse",
    "SupplyChain_Gold_Warehouse",
}


def get_access_token() -> bytes:
    raw = subprocess.run(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--output",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    token = json.loads(raw.stdout)["accessToken"].encode("UTF-16-LE")
    return struct.pack(f"<I{len(token)}s", len(token), token)


def connect(database: str) -> pyodbc.Connection:
    token_struct = get_access_token()
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};"
        f"DATABASE={database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        timeout=30,
    )


def scalar(cur: pyodbc.Cursor, sql: str, params: tuple = ()) -> int:
    cur.execute(sql, params)
    return cur.fetchone()[0]


def rows(cur: pyodbc.Cursor, sql: str, params: tuple = ()) -> list[dict]:
    cur.execute(sql, params)
    cols = [col[0] for col in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def fabric_items() -> dict:
    raw = subprocess.run(
        [
            "az",
            "rest",
            "--method",
            "GET",
            "--resource",
            "https://api.fabric.microsoft.com",
            "--url",
            f"{FABRIC_BASE}/workspaces/{WORKSPACE_ID}/items",
            "--output",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    items = json.loads(raw.stdout)["value"]
    names = {item["displayName"] for item in items}
    return {
        "deleted_targets_remaining": sorted(DELETED_TARGETS & names),
        "protected_targets_present": sorted(PROTECTED_TARGETS & names),
        "protected_targets_missing": sorted(PROTECTED_TARGETS - names),
        "created_targets_present": sorted(CREATED_TARGETS & names),
        "created_targets_missing": sorted(CREATED_TARGETS - names),
        "created_items": [
            {k: item.get(k) for k in ("displayName", "type", "id")}
            for item in items
            if item["displayName"] in CREATED_TARGETS
        ],
    }


def verify_old_warehouse() -> dict:
    conn = connect("SupplyChain_Warehouse")
    cur = conn.cursor()
    return {
        "remaining_v9_scoped_objects": scalar(
            cur,
            """
            SELECT COUNT(*)
            FROM sys.objects o
            JOIN sys.schemas s ON s.schema_id = o.schema_id
            WHERE s.name IN ('bronze','silver','gold','meta')
              AND o.is_ms_shipped = 0;
            """,
        )
    }


def verify_processing() -> dict:
    conn = connect("SupplyChain_Processing_Warehouse")
    cur = conn.cursor()
    return {
        "schemas": rows(
            cur,
            """
            SELECT name AS schema_name
            FROM sys.schemas
            WHERE name IN ('Meta','Staging','ReferenceMaster','SalesHistory','ForecastHistory','OpenOrderHistory')
            ORDER BY name;
            """,
        ),
        "tables_by_schema": rows(
            cur,
            """
            SELECT s.name AS schema_name, COUNT(*) AS table_count
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name IN ('Meta','Staging','ReferenceMaster','SalesHistory','ForecastHistory','OpenOrderHistory')
            GROUP BY s.name
            ORDER BY s.name;
            """,
        ),
        "meta_views": scalar(
            cur,
            "SELECT COUNT(*) FROM sys.views v JOIN sys.schemas s ON s.schema_id=v.schema_id WHERE s.name='Meta';",
        ),
        "meta_procs": scalar(
            cur,
            "SELECT COUNT(*) FROM sys.procedures p JOIN sys.schemas s ON s.schema_id=p.schema_id WHERE s.name='Meta';",
        ),
        "meta_counts": rows(
            cur,
            """
            SELECT 'AssetRegistryV10' AS object_name, COUNT(*) AS row_count FROM Meta.AssetRegistryV10
            UNION ALL SELECT 'SourceFeed', COUNT(*) FROM Meta.SourceFeed
            UNION ALL SELECT 'SourceContract', COUNT(*) FROM Meta.SourceContract
            UNION ALL SELECT 'DQRule', COUNT(*) FROM Meta.DQRule
            UNION ALL SELECT 'DQRuleWithSourceRow', COUNT(*) FROM Meta.DQRule WHERE source_row_number IS NOT NULL
            UNION ALL SELECT 'LineageEdge', COUNT(*) FROM Meta.LineageEdge
            UNION ALL SELECT 'SemanticModelContract', COUNT(*) FROM Meta.SemanticModelContract
            UNION ALL SELECT 'SilverDagWaveRuntime', COUNT(*) FROM Meta.SilverDagWaveRuntime
            UNION ALL SELECT 'ReconciliationRule', COUNT(*) FROM Meta.ReconciliationRule;
            """,
        ),
        "table_dictionary_columns": scalar(
            cur,
            """
            SELECT COUNT(*)
            FROM sys.columns c
            JOIN sys.views v ON v.object_id = c.object_id
            JOIN sys.schemas s ON s.schema_id = v.schema_id
            WHERE s.name = 'Meta'
              AND v.name = 'vw_TableDictionary';
            """,
        ),
    }


def verify_gold() -> dict:
    conn = connect("SupplyChain_Gold_Warehouse")
    cur = conn.cursor()
    return {
        "schemas": rows(
            cur,
            "SELECT name AS schema_name FROM sys.schemas WHERE name = 'ForecastAccuracy';",
        ),
        "tables": rows(
            cur,
            """
            SELECT s.name AS schema_name, t.name AS table_name
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = 'ForecastAccuracy'
            ORDER BY t.name;
            """,
        ),
    }


def main() -> int:
    result = {
        "fabric": fabric_items(),
        "old_warehouse": verify_old_warehouse(),
        "processing_warehouse": verify_processing(),
        "gold_warehouse": verify_gold(),
    }
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    failed = []
    if result["fabric"]["deleted_targets_remaining"]:
        failed.append("deleted_targets_remaining")
    if result["fabric"]["protected_targets_missing"]:
        failed.append("protected_targets_missing")
    if result["fabric"]["created_targets_missing"]:
        failed.append("created_targets_missing")
    if result["old_warehouse"]["remaining_v9_scoped_objects"] != 0:
        failed.append("remaining_v9_scoped_objects")
    return 0 if not failed else 2


if __name__ == "__main__":
    raise SystemExit(main())
