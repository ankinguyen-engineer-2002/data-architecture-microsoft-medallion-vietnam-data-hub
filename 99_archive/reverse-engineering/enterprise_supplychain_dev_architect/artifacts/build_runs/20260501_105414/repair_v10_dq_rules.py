#!/usr/bin/env python3
"""Repair v10 DQ rule seed when v9 rule_id values are duplicated by target."""

from __future__ import annotations

import csv
import json
import struct
import subprocess
from pathlib import Path

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Processing_Warehouse"
SOURCE_CSV = Path(
    "Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/sql/meta_tables/dq_rules.csv"
)


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


def connect() -> pyodbc.Connection:
    token_struct = get_access_token()
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        timeout=30,
        autocommit=True,
    )


def nullable_bit(value: str) -> int | None:
    if value in ("", None):
        return None
    return 1 if str(value).lower() in {"1", "true", "yes"} else 0


def main() -> int:
    conn = connect()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT COUNT(*)
        FROM sys.columns c
        JOIN sys.tables t ON t.object_id = c.object_id
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'Meta'
          AND t.name = 'DQRule'
          AND c.name = 'source_row_number';
        """
    )
    if cur.fetchone()[0] == 0:
        cur.execute("ALTER TABLE Meta.DQRule ADD source_row_number INT NULL;")

    inserted = 0
    updated = 0

    with SOURCE_CSV.open(newline="", encoding="utf-8-sig") as f:
        for source_row_number, row in enumerate(csv.DictReader(f), start=1):
            cur.execute("SELECT COUNT(*) FROM Meta.DQRule WHERE source_row_number = ?;", (source_row_number,))
            if cur.fetchone()[0]:
                continue

            params = (
                int(row["rule_id"]),
                row["rule_name"],
                row["target_schema"],
                row["target_table"],
                row["check_type"],
                row["column_name"],
                row["layer"],
            )
            cur.execute(
                """
                SELECT COUNT(*)
                FROM Meta.DQRule
                WHERE source_row_number IS NULL
                  AND rule_id = ?
                  AND rule_name = ?
                  AND target_schema = ?
                  AND target_table = ?
                  AND check_type = ?
                  AND column_name = ?
                  AND layer = ?;
                """,
                params,
            )
            if cur.fetchone()[0]:
                cur.execute(
                    """
                    UPDATE Meta.DQRule
                    SET source_row_number = ?
                    WHERE source_row_number IS NULL
                      AND rule_id = ?
                      AND rule_name = ?
                      AND target_schema = ?
                      AND target_table = ?
                      AND check_type = ?
                      AND column_name = ?
                      AND layer = ?;
                    """,
                    (source_row_number, *params),
                )
                updated += 1
                continue

            cur.execute(
                """
                INSERT INTO Meta.DQRule
                (source_row_number, rule_id, rule_name, target_schema, target_table, check_type, column_name,
                 severity, threshold, params, is_active, layer)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                (
                    source_row_number,
                    int(row["rule_id"]),
                    row["rule_name"],
                    row["target_schema"],
                    row["target_table"],
                    row["check_type"],
                    row["column_name"],
                    row["severity"],
                    row["threshold"],
                    row["params"],
                    nullable_bit(row["is_active"]),
                    row["layer"],
                ),
            )
            inserted += 1

    cur.execute("SELECT COUNT(*) FROM Meta.DQRule;")
    total = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM Meta.DQRule WHERE source_row_number IS NOT NULL;")
    with_source_rows = cur.fetchone()[0]
    print(
        json.dumps(
            {
                "dq_rules_inserted": inserted,
                "dq_rules_total": total,
                "dq_rules_updated_with_source_row": updated,
                "dq_rules_with_source_row": with_source_rows,
            },
            sort_keys=True,
        )
    )
    return 0 if total == 54 else 2


if __name__ == "__main__":
    raise SystemExit(main())
