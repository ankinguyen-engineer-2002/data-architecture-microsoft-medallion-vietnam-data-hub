#!/usr/bin/env python3
"""Export read-only v9 baseline evidence for the v10 readiness pack.

This script intentionally avoids DDL/DML and production mutations. It exports:
- Fabric Warehouse metadata and meta-control-plane tables via read-only SELECTs.
- Fabric item inventory and Data Pipeline definitions via read-only REST calls.
- A small verification summary for smart skip, DQ gates, and Phase 3 objects.
"""

from __future__ import annotations

import argparse
import base64
import csv
import datetime as dt
import json
import os
import pathlib
import struct
import subprocess
import sys
import urllib.error
import urllib.request
from typing import Any

import pyodbc


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Warehouse"

PIPELINES = {
    "pl_sc_master": "319a8160-3f3a-4b87-8ad6-75ac4f3ec184",
    "pl_sc_mart": "9a1e7a12-30ab-465c-a45d-b051619193ac",
    "pl_sc_bronze": "1bdbaebb-7222-4e9c-a45d-3e632bba846d",
    "pl_sc_silver": "46437ae6-3a15-4697-957d-f1f44ba10633",
    "pl_sc_silver_wave": "57a09720-21a2-49b5-a472-1e19abd14f76",
    "pl_sc_gold": "94fc130e-f327-46a9-b7ba-cd2aa328c0da",
    "pl_dq_check": "c32dc18d-d027-4672-9872-f73404cd7c6f",
}


SQL_EXPORTS: dict[str, str] = {
    "00_object_inventory.csv": """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type,
            o.type_desc,
            o.create_date,
            o.modify_date
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        WHERE s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
        ORDER BY s.name, o.type_desc, o.name;
    """,
    "01_table_row_counts.csv": """
        SELECT
            s.name AS schema_name,
            t.name AS table_name,
            SUM(p.rows) AS row_count
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.partitions p
            ON p.object_id = t.object_id
           AND p.index_id IN (0, 1)
        GROUP BY s.name, t.name
        ORDER BY s.name, t.name;
    """,
    "02_columns.csv": """
        SELECT
            table_schema,
            table_name,
            column_name,
            ordinal_position,
            data_type,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            is_nullable
        FROM INFORMATION_SCHEMA.COLUMNS
        ORDER BY table_schema, table_name, ordinal_position;
    """,
    "03_sp_registry.csv": "SELECT * FROM meta.sp_registry ORDER BY layer, project, target_schema, target_table;",
    "04_sp_registry_summary.csv": """
        SELECT
            layer,
            target_schema,
            project,
            load_type,
            frequency,
            is_active,
            COUNT(*) AS object_count
        FROM meta.sp_registry
        GROUP BY layer, target_schema, project, load_type, frequency, is_active
        ORDER BY layer, target_schema, project, load_type, frequency, is_active;
    """,
    "05_smart_skip_registry.csv": """
        SELECT
            sp_name,
            target_schema,
            target_table,
            layer,
            project,
            is_active,
            frequency,
            cron_expression,
            next_run_time,
            CASE
                WHEN is_active = 0 THEN 0
                WHEN next_run_time IS NULL THEN 1
                WHEN next_run_time <= GETUTCDATE() THEN 1
                ELSE 0
            END AS should_run_now
        FROM meta.sp_registry
        ORDER BY layer, project, target_schema, target_table;
    """,
    "06_lineage.csv": "SELECT * FROM meta.sp_lineage ORDER BY source_schema, source_table, target_schema, target_table;",
    "07_dq_rules.csv": "SELECT * FROM meta.dq_rules ORDER BY layer, target_schema, target_table, rule_id;",
    "08_dq_rules_summary.csv": """
        SELECT
            layer,
            check_type,
            severity,
            is_active,
            COUNT(*) AS rule_count
        FROM meta.dq_rules
        GROUP BY layer, check_type, severity, is_active
        ORDER BY layer, check_type, severity, is_active;
    """,
    "09_dq_results_recent.csv": """
        SELECT TOP 200 *
        FROM meta.dq_results
        ORDER BY check_time DESC;
    """,
    "10_run_history_recent.csv": """
        SELECT TOP 300 *
        FROM meta.sp_run_history
        ORDER BY start_time DESC;
    """,
    "11_pipeline_run_log_recent.csv": """
        SELECT TOP 100 *
        FROM meta.pipeline_run_log
        ORDER BY start_time DESC;
    """,
    "12_table_dictionary.csv": "SELECT * FROM meta.vw_table_dictionary ORDER BY SchemaName, TableName;",
    "13_view_definitions.csv": """
        SELECT
            s.name AS schema_name,
            v.name AS view_name,
            m.definition
        FROM sys.views v
        INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
        INNER JOIN sys.sql_modules m ON v.object_id = m.object_id
        ORDER BY s.name, v.name;
    """,
    "14_routine_definitions.csv": """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc,
            m.definition
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
        WHERE o.type IN ('P', 'FN', 'IF', 'TF')
        ORDER BY s.name, o.type_desc, o.name;
    """,
    "15_phase3_object_existence.csv": """
        SELECT 'meta.schema_contracts' AS object_name,
               CASE WHEN OBJECT_ID('meta.schema_contracts', 'U') IS NULL THEN 0 ELSE 1 END AS exists_flag
        UNION ALL
        SELECT 'meta.performance_baseline',
               CASE WHEN OBJECT_ID('meta.performance_baseline', 'U') IS NULL THEN 0 ELSE 1 END
        UNION ALL
        SELECT 'meta.pipeline_cost_log',
               CASE WHEN OBJECT_ID('meta.pipeline_cost_log', 'U') IS NULL THEN 0 ELSE 1 END
        UNION ALL
        SELECT 'meta.usp_validate_schema_contracts',
               CASE WHEN OBJECT_ID('meta.usp_validate_schema_contracts', 'P') IS NULL THEN 0 ELSE 1 END
        UNION ALL
        SELECT 'meta.usp_check_dq_single',
               CASE WHEN OBJECT_ID('meta.usp_check_dq_single', 'P') IS NULL THEN 0 ELSE 1 END
        UNION ALL
        SELECT 'meta.usp_compute_slv_waves',
               CASE WHEN OBJECT_ID('meta.usp_compute_slv_waves', 'P') IS NULL THEN 0 ELSE 1 END
        UNION ALL
        SELECT 'meta.usp_finalize_pipeline',
               CASE WHEN OBJECT_ID('meta.usp_finalize_pipeline', 'P') IS NULL THEN 0 ELSE 1 END;
    """,
    "16_schema_contracts.csv": "SELECT * FROM meta.schema_contracts ORDER BY source_object, column_name;",
    "17_performance_baseline.csv": "SELECT * FROM meta.performance_baseline ORDER BY sp_name;",
    "18_pipeline_cost_log.csv": "SELECT * FROM meta.pipeline_cost_log ORDER BY start_time DESC;",
}


def run_az_token(resource: str) -> str:
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource", resource, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)["accessToken"]


def connect_sql() -> pyodbc.Connection:
    token = run_az_token("https://database.windows.net/").encode("UTF-16-LE")
    token_struct = struct.pack(f"<I{len(token)}s", len(token), token)
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={DATABASE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        timeout=30,
    )


def normalize_value(value: Any) -> Any:
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    return value


def write_query_csv(conn: pyodbc.Connection, sql: str, path: pathlib.Path) -> int:
    cur = conn.cursor()
    cur.execute("SET NOCOUNT ON; " + sql)
    columns = [col[0] for col in cur.description]
    row_count = 0
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(columns)
        for row in cur:
            writer.writerow([normalize_value(v) for v in row])
            row_count += 1
    return row_count


def request_json(method: str, url: str, token: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method.upper(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def decode_definition_parts(definition: dict[str, Any], output_dir: pathlib.Path) -> list[dict[str, Any]]:
    parts = definition.get("definition", {}).get("parts", [])
    decoded: list[dict[str, Any]] = []
    for part in parts:
        path = part["path"]
        payload = part.get("payload", "")
        payload_type = part.get("payloadType")
        if payload_type == "InlineBase64":
            content = base64.b64decode(payload).decode("utf-8")
        else:
            content = payload

        safe_path = output_dir / path
        safe_path.parent.mkdir(parents=True, exist_ok=True)
        safe_path.write_text(content, encoding="utf-8")
        decoded.append({"path": path, "payload_type": payload_type, "content": content})
    return decoded


def walk_json(value: Any) -> list[Any]:
    out = [value]
    if isinstance(value, dict):
        for child in value.values():
            out.extend(walk_json(child))
    elif isinstance(value, list):
        for child in value:
            out.extend(walk_json(child))
    return out


def summarize_pipeline(name: str, parts: list[dict[str, Any]]) -> dict[str, Any]:
    content = next((p["content"] for p in parts if p["path"] == "pipeline-content.json"), None)
    if not content:
        return {"pipeline": name, "has_pipeline_content": False}

    doc = json.loads(content)
    activities = doc.get("properties", {}).get("activities", [])
    nodes = walk_json(doc)
    sql_queries = []
    activity_rows = []

    for node in nodes:
        if isinstance(node, dict):
            if "sqlReaderQuery" in node:
                raw_query = node["sqlReaderQuery"]
                if isinstance(raw_query, dict):
                    raw_query = raw_query.get("value", json.dumps(raw_query, sort_keys=True))
                sql_queries.append(str(raw_query))
            if "name" in node and "type" in node:
                type_props = node.get("typeProperties", {})
                activity_rows.append(
                    {
                        "pipeline": name,
                        "activity_name": node.get("name"),
                        "activity_type": node.get("type"),
                        "state": node.get("state", "Active"),
                        "batch_count": type_props.get("batchCount"),
                        "retry": node.get("policy", {}).get("retry"),
                        "retry_interval_seconds": node.get("policy", {}).get("retryIntervalInSeconds"),
                    }
                )

    joined_queries = "\n".join(sql_queries).lower()
    return {
        "pipeline": name,
        "has_pipeline_content": True,
        "activity_count": len(activity_rows),
        "sql_query_count": len(sql_queries),
        "has_next_run_time_filter": "next_run_time" in joined_queries and "getutcdate" in joined_queries,
        "has_project_filter": "project" in joined_queries,
        "has_dq_activity_name": any("dq" in str(a["activity_name"]).lower() for a in activity_rows),
        "inactive_activity_count": sum(1 for a in activity_rows if str(a.get("state", "")).lower() == "inactive"),
        "activities": activity_rows,
        "sql_queries": sql_queries,
    }


def export_rest(output_dir: pathlib.Path) -> dict[str, Any]:
    token = run_az_token("https://api.fabric.microsoft.com")
    rest_dir = output_dir / "rest"
    pipeline_dir = output_dir / "pipeline_definitions"
    rest_dir.mkdir(parents=True, exist_ok=True)
    pipeline_dir.mkdir(parents=True, exist_ok=True)

    summary: dict[str, Any] = {"pipeline_summaries": []}
    base = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}"

    for endpoint_name, url in {
        "items": f"{base}/items",
        "warehouses": f"{base}/warehouses",
        "lakehouses": f"{base}/lakehouses",
        "semanticModels": f"{base}/semanticModels",
    }.items():
        try:
            payload = request_json("GET", url, token)
            (rest_dir / f"{endpoint_name}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
            summary[f"{endpoint_name}_status"] = "exported"
        except Exception as exc:  # noqa: BLE001
            summary[f"{endpoint_name}_status"] = f"error: {exc}"

    activity_rows: list[dict[str, Any]] = []
    query_rows: list[dict[str, Any]] = []

    for pipeline_name, pipeline_id in PIPELINES.items():
        try:
            definition = request_json("POST", f"{base}/items/{pipeline_id}/getDefinition", token)
            raw_path = rest_dir / f"definition_{pipeline_name}.json"
            raw_path.write_text(json.dumps(definition, indent=2), encoding="utf-8")
            parts = decode_definition_parts(definition, pipeline_dir / pipeline_name)
            pipeline_summary = summarize_pipeline(pipeline_name, parts)
            summary["pipeline_summaries"].append(
                {k: v for k, v in pipeline_summary.items() if k not in ("activities", "sql_queries")}
            )
            activity_rows.extend(pipeline_summary.get("activities", []))
            for idx, query in enumerate(pipeline_summary.get("sql_queries", []), start=1):
                query_rows.append({"pipeline": pipeline_name, "query_index": idx, "sql_query": query})
        except Exception as exc:  # noqa: BLE001
            summary["pipeline_summaries"].append({"pipeline": pipeline_name, "error": str(exc)})

    write_dict_csv(output_dir / "pipeline_activity_summary.csv", activity_rows)
    write_dict_csv(output_dir / "pipeline_sql_queries.csv", query_rows)
    return summary


def write_dict_csv(path: pathlib.Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    columns = sorted({key for row in rows for key in row.keys()})
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def export_sql(output_dir: pathlib.Path) -> dict[str, Any]:
    conn = connect_sql()
    summary: dict[str, Any] = {}
    sql_dir = output_dir / "sql"
    sql_dir.mkdir(parents=True, exist_ok=True)

    for filename, sql in SQL_EXPORTS.items():
        path = sql_dir / filename
        try:
            rows = write_query_csv(conn, sql, path)
            summary[filename] = {"status": "exported", "rows": rows}
        except Exception as exc:  # noqa: BLE001
            summary[filename] = {"status": "error", "error": str(exc)}
            path.with_suffix(path.suffix + ".error.txt").write_text(str(exc), encoding="utf-8")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default=None)
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = pathlib.Path(args.output_dir) if args.output_dir else root / "readiness_exports" / timestamp
    output_dir.mkdir(parents=True, exist_ok=True)

    run_summary: dict[str, Any] = {
        "timestamp": timestamp,
        "workspace_id": WORKSPACE_ID,
        "sql_server": SQL_SERVER,
        "database": DATABASE,
        "output_dir": str(output_dir),
    }

    try:
        run_summary["sql_exports"] = export_sql(output_dir)
    except Exception as exc:  # noqa: BLE001
        run_summary["sql_export_error"] = str(exc)

    try:
        run_summary["rest_exports"] = export_rest(output_dir)
    except Exception as exc:  # noqa: BLE001
        run_summary["rest_export_error"] = str(exc)

    (output_dir / "run_summary.json").write_text(json.dumps(run_summary, indent=2), encoding="utf-8")
    print(output_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
