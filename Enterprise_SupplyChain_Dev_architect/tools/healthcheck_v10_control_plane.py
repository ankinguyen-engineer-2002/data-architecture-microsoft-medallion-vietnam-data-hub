#!/usr/bin/env python3
"""
v10 Control Plane healthcheck (live).

This is a lightweight "test" script used in a TDD-like workflow for live Fabric
control-plane changes:
  - Run it first and observe failures (RED)
  - Apply targeted fixes
  - Re-run and expect all checks to pass (GREEN)

It does NOT mutate live state.
"""

from __future__ import annotations

import argparse
import base64
import json
import struct
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

import pyodbc


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
FABRIC_BASE = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}"

SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
SQL_DATABASE = "SupplyChain_Processing_Warehouse"

PIPELINES = {
    "pl_sc_master": "f36f56b8-5668-4a0c-b991-2c28302f1710",
    "pl_sc_mart": "20db5725-80e3-4081-9ef5-01700acdf3b3",
    "pl_sc_staging": "10221fb2-6e30-4911-9d95-d8dd67440d84",
    "pl_sc_silver": "7dc6ecda-56cc-4797-893c-1c502863323f",
    "pl_sc_silver_wave": "797b1a02-f973-4584-bd27-bb0151549d4b",
    "pl_sc_gold": "50ff6263-659d-4b09-9e45-b42a3434e093",
}


def run(cmd: list[str], *, input_text: str | None = None) -> str:
    return subprocess.check_output(cmd, text=True, input=input_text)


def az_token(resource: str) -> str:
    return (
        run(
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
            ]
        )
        .strip()
    )


def sql_conn() -> pyodbc.Connection:
    token = az_token("https://database.windows.net/").encode("utf-16-le")
    token_struct = struct.pack("<I", len(token)) + token
    return pyodbc.connect(
        (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={SQL_SERVER};DATABASE={SQL_DATABASE};"
            "Encrypt=yes;TrustServerCertificate=no;"
        ),
        attrs_before={1256: token_struct},
    )


def fabric_request(method: str, url: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    cmd = [
        "az",
        "rest",
        "--method",
        method,
        "--resource",
        "https://api.fabric.microsoft.com",
        "--url",
        url,
    ]
    input_text = None
    if body is not None:
        cmd.extend(["--body", "@-"])
        input_text = json.dumps(body)
    raw = run(cmd, input_text=input_text).strip()
    if not raw:
        return {}
    return json.loads(raw)


def get_pipeline_content(pipeline_id: str) -> dict[str, Any]:
    definition = fabric_request("POST", f"{FABRIC_BASE}/items/{pipeline_id}/getDefinition")
    part = next(p for p in definition["definition"]["parts"] if p["path"] == "pipeline-content.json")
    payload = base64.b64decode(part["payload"]).decode("utf-8")
    return json.loads(payload)


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    details: str


def check(condition: bool, name: str, details_ok: str, details_fail: str) -> CheckResult:
    return CheckResult(name=name, ok=bool(condition), details=(details_ok if condition else details_fail))


def pipeline_contains(content: dict[str, Any], needle: str) -> bool:
    return needle in json.dumps(content)


def fetch_param_names(conn: pyodbc.Connection, full_object_name: str) -> list[str]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT p.name
        FROM sys.parameters p
        WHERE p.object_id = OBJECT_ID(?)
        ORDER BY p.parameter_id;
        """,
        full_object_name,
    )
    return [str(r[0]).lstrip("@") for r in cur.fetchall()]


def table_dictionary_has(conn: pyodbc.Connection, *, schema: str, table: str) -> bool:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT COUNT(*)
        FROM Meta.TableDictionary
        WHERE SchemaName = ?
          AND TableName = ?;
        """,
        schema,
        table,
    )
    return int(cur.fetchone()[0]) > 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    args = parser.parse_args()

    results: list[CheckResult] = []

    # ── SQL checks ──────────────────────────────────────────────────────────────
    with sql_conn() as conn:
        params = fetch_param_names(conn, "Meta.usp_LogPipelineRun")
        results.append(
            check(
                "project" in {p.lower() for p in params},
                "sql.usp_LogPipelineRun_has_project_param",
                "Meta.usp_LogPipelineRun has @project",
                f"Missing @project in Meta.usp_LogPipelineRun params: {params}",
            )
        )

        results.append(
            check(
                table_dictionary_has(conn, schema="InventoryHistory_Enh", table="Cogs52WWeekly"),
                "sql.TableDictionary_has_Cogs52WWeekly",
                "Meta.TableDictionary contains InventoryHistory_Enh.Cogs52WWeekly",
                "Missing Meta.TableDictionary row for InventoryHistory_Enh.Cogs52WWeekly",
            )
        )
        results.append(
            check(
                table_dictionary_has(conn, schema="InventoryHistory_Enh", table="ItemBalanceHistorical_WithInTransit"),
                "sql.TableDictionary_has_ItemBalanceHistorical_WithInTransit",
                "Meta.TableDictionary contains InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit",
                "Missing Meta.TableDictionary row for InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit",
            )
        )

    # ── Pipeline checks ─────────────────────────────────────────────────────────
    mart = get_pipeline_content(PIPELINES["pl_sc_mart"])
    results.append(
        check(
            pipeline_contains(mart, "usp_LogPipelineRun"),
            "pipeline.pl_sc_mart_has_usp_LogPipelineRun",
            "pl_sc_mart contains Meta.usp_LogPipelineRun logging",
            "pl_sc_mart is missing Meta.usp_LogPipelineRun logging",
        )
    )

    gold = get_pipeline_content(PIPELINES["pl_sc_gold"])
    results.append(
        check(
            pipeline_contains(gold, "usp_LogRun"),
            "pipeline.pl_sc_gold_has_usp_LogRun",
            "pl_sc_gold logs per-table runs via Meta.usp_LogRun",
            "pl_sc_gold does not log per-table runs (Meta.usp_LogRun not found)",
        )
    )
    results.append(
        check(
            pipeline_contains(gold, "next_run_time")
            or pipeline_contains(gold, "ufn_should_run")
            or pipeline_contains(gold, "GETUTCDATE"),
            "pipeline.pl_sc_gold_has_due_gate",
            "pl_sc_gold lookup includes a due gate",
            "pl_sc_gold lookup does not appear to include a due gate",
        )
    )

    silver_wave = get_pipeline_content(PIPELINES["pl_sc_silver_wave"])
    results.append(
        check(
            pipeline_contains(silver_wave, "next_run_time") or pipeline_contains(silver_wave, "ufn_should_run"),
            "pipeline.pl_sc_silver_wave_has_due_gate",
            "pl_sc_silver_wave selects due-only assets",
            "pl_sc_silver_wave does not appear to filter due-only assets",
        )
    )

    ok = all(r.ok for r in results)
    if args.json:
        print(json.dumps({"ok": ok, "results": [r.__dict__ for r in results]}, indent=2))
    else:
        for r in results:
            status = "PASS" if r.ok else "FAIL"
            print(f"[{status}] {r.name} — {r.details}")

    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())

