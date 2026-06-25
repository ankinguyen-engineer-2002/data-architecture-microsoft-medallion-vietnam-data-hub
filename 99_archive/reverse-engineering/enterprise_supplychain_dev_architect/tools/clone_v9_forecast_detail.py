#!/usr/bin/env python3
"""Read-only detail clone of the live SupplyChain v9 Forecast implementation.

The output is intended as local evidence for v9 -> v10 refactoring. It exports
Fabric item inventory, selected Data Pipeline definitions, SQL metadata, SQL
object definitions, and meta-control-plane tables without mutating Fabric.

Business table data rows are intentionally not exported. The clone captures
schemas, row counts, definitions, registry/control-plane data, and operational
history needed to preserve v9 behavior.
"""

from __future__ import annotations

import argparse
import base64
import csv
import datetime as dt
import json
import pathlib
import re
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from typing import Any

import pyodbc


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
WAREHOUSE_ID = "e146ffe2-d907-46a7-9b7e-3e739a31b24e"
SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Warehouse"

V9_PIPELINES = {
    "pl_sc_master": "319a8160-3f3a-4b87-8ad6-75ac4f3ec184",
    "pl_sc_mart": "9a1e7a12-30ab-465c-a45d-b051619193ac",
    "pl_sc_bronze": "1bdbaebb-7222-4e9c-a45d-3e632bba846d",
    "pl_sc_silver": "46437ae6-3a15-4697-957d-f1f44ba10633",
    "pl_sc_silver_wave": "57a09720-21a2-49b5-a472-1e19abd14f76",
    "pl_sc_gold": "94fc130e-f327-46a9-b7ba-cd2aa328c0da",
    "pl_dq_check": "c32dc18d-d027-4672-9872-f73404cd7c6f",
}

FOCUS_ITEM_NAMES = {
    "Enterprise_Lakehouse",
    "SupplyChain_Lakehouse",
    "SupplyChain_Warehouse",
    "SupplyChain_Gold",
    "SC_Control_Tower",
    "Supply Chain Control Tower",
    "Forecast Accuracy Gold",
}

V9_SCHEMAS = ("bronze", "silver", "gold", "meta")


SQL_EXPORTS: dict[str, str] = {
    "00_schemas.csv": """
        SELECT
            s.name AS schema_name,
            COUNT(o.object_id) AS object_count
        FROM sys.schemas s
        LEFT JOIN sys.objects o
            ON o.schema_id = s.schema_id
           AND o.type NOT IN ('IT', 'S')
        GROUP BY s.name
        ORDER BY s.name;
    """,
    "01_object_inventory.csv": """
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
    "02_object_counts_by_schema.csv": """
        SELECT
            s.name AS schema_name,
            o.type_desc,
            COUNT(*) AS object_count
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        WHERE s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
        GROUP BY s.name, o.type_desc
        ORDER BY s.name, o.type_desc;
    """,
    "03_table_row_counts.csv": """
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
    "04_columns.csv": """
        SELECT
            table_schema,
            table_name,
            column_name,
            ordinal_position,
            data_type,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            datetime_precision,
            is_nullable
        FROM INFORMATION_SCHEMA.COLUMNS
        ORDER BY table_schema, table_name, ordinal_position;
    """,
    "05_v9_layer_inventory.csv": """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc,
            o.create_date,
            o.modify_date
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        WHERE s.name IN ('bronze', 'silver', 'gold', 'meta')
        ORDER BY s.name, o.type_desc, o.name;
    """,
    "06_sp_registry.csv": "SELECT * FROM meta.sp_registry ORDER BY layer, project, target_schema, target_table;",
    "07_sp_registry_summary.csv": """
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
    "08_registry_dependency_map.csv": """
        SELECT
            sp_name,
            target_schema,
            target_table,
            layer,
            project,
            load_type,
            depends_on,
            source_objects,
            is_active,
            next_run_time,
            last_load_date,
            rows_loaded
        FROM meta.sp_registry
        ORDER BY layer, target_schema, target_table;
    """,
    "09_smart_skip_registry.csv": """
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
    "10_lineage.csv": "SELECT * FROM meta.sp_lineage ORDER BY source_schema, source_table, target_schema, target_table;",
    "11_dq_rules.csv": "SELECT * FROM meta.dq_rules ORDER BY layer, target_schema, target_table, rule_id;",
    "12_dq_rules_summary.csv": """
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
    "13_dq_results.csv": "SELECT * FROM meta.dq_results ORDER BY check_time DESC;",
    "14_sp_run_history.csv": "SELECT * FROM meta.sp_run_history ORDER BY start_time DESC;",
    "15_pipeline_run_log.csv": "SELECT * FROM meta.pipeline_run_log ORDER BY start_time DESC;",
    "16_slv_dag_waves_runtime.csv": "SELECT * FROM meta.slv_dag_waves_runtime ORDER BY wave, sp_name;",
    "17_table_dictionary.csv": "SELECT * FROM meta.vw_table_dictionary ORDER BY SchemaName, TableName;",
    "18_view_definitions.csv": """
        SELECT
            s.name AS schema_name,
            v.name AS object_name,
            'VIEW' AS object_kind,
            m.definition
        FROM sys.views v
        INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
        INNER JOIN sys.sql_modules m ON v.object_id = m.object_id
        ORDER BY s.name, v.name;
    """,
    "19_routine_definitions.csv": """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc AS object_kind,
            m.definition
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
        WHERE o.type IN ('P', 'FN', 'IF', 'TF')
        ORDER BY s.name, o.type_desc, o.name;
    """,
    "20_phase3_object_existence.csv": """
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
    "21_schema_contracts.csv": "SELECT * FROM meta.schema_contracts ORDER BY source_object, column_name;",
    "22_performance_baseline.csv": "SELECT * FROM meta.performance_baseline ORDER BY sp_name;",
    "23_pipeline_cost_log.csv": "SELECT * FROM meta.pipeline_cost_log ORDER BY start_time DESC;",
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


def safe_filename(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "unnamed"


def quote_name(value: str) -> str:
    return "[" + value.replace("]", "]]") + "]"


def write_text(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json(path: pathlib.Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def write_dict_csv(path: pathlib.Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    columns = sorted({key for row in rows for key in row.keys()})
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: normalize_value(row.get(key)) for key in columns})


def query_rows(conn: pyodbc.Connection, sql: str) -> tuple[list[str], list[dict[str, Any]]]:
    cur = conn.cursor()
    cur.execute("SET NOCOUNT ON; " + sql)
    columns = [col[0] for col in cur.description]
    rows: list[dict[str, Any]] = []
    for row in cur:
        rows.append({columns[idx]: normalize_value(value) for idx, value in enumerate(row)})
    return columns, rows


def write_query_csv(conn: pyodbc.Connection, sql: str, path: pathlib.Path) -> int:
    columns, rows = query_rows(conn, sql)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    return len(rows)


def request_json(
    method: str,
    url: str,
    token: str,
    body: dict[str, Any] | None = None,
    *,
    allow_lro: bool = True,
) -> dict[str, Any]:
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
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            raw = resp.read().decode("utf-8")
            if resp.status == 202 and allow_lro:
                location = resp.headers.get("Location")
                retry_after = int(resp.headers.get("Retry-After", "5"))
                if not location:
                    return {"status": "accepted", "location": None}
                return poll_lro(location, token, retry_after)
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} failed with {exc.code}: {error_body}") from exc


def poll_lro(location: str, token: str, retry_after: int) -> dict[str, Any]:
    for _ in range(30):
        time.sleep(min(max(retry_after, 1), 30))
        payload = request_json("GET", location, token, allow_lro=False)
        status = str(payload.get("status", "")).lower()
        if status in ("succeeded", "success", "completed"):
            return payload.get("result") or payload
        if status in ("failed", "cancelled", "canceled"):
            raise RuntimeError(f"LRO failed: {json.dumps(payload, ensure_ascii=False)}")
        retry_after = 5
    raise TimeoutError(f"LRO did not complete: {location}")


def list_all(token: str, url: str) -> dict[str, Any]:
    values: list[dict[str, Any]] = []
    next_url: str | None = url
    continuation_token: str | None = None
    while next_url:
        fetch_url = next_url
        if continuation_token and "continuationToken=" not in fetch_url:
            separator = "&" if "?" in fetch_url else "?"
            fetch_url = f"{fetch_url}{separator}continuationToken={urllib.parse.quote(continuation_token)}"
        payload = request_json("GET", fetch_url, token)
        values.extend(payload.get("value", []))
        next_url = payload.get("continuationUri")
        continuation_token = payload.get("continuationToken")
        if not next_url and continuation_token:
            next_url = url
    return {"value": values, "count": len(values)}


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
        write_text(safe_path, content)
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


def get_nested(value: dict[str, Any], path: list[str]) -> Any:
    current: Any = value
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def summarize_pipeline(name: str, parts: list[dict[str, Any]]) -> dict[str, Any]:
    content = next((p["content"] for p in parts if p["path"] == "pipeline-content.json"), None)
    if not content:
        return {"pipeline": name, "has_pipeline_content": False}

    doc = json.loads(content)
    nodes = walk_json(doc)
    parameters = get_nested(doc, ["properties", "parameters"]) or {}
    variables = get_nested(doc, ["properties", "variables"]) or {}

    sql_queries: list[dict[str, Any]] = []
    activity_rows: list[dict[str, Any]] = []
    sp_rows: list[dict[str, Any]] = []
    invocation_rows: list[dict[str, Any]] = []

    for node in nodes:
        if not isinstance(node, dict):
            continue

        if "sqlReaderQuery" in node:
            raw_query = node["sqlReaderQuery"]
            expression_type = None
            if isinstance(raw_query, dict):
                expression_type = raw_query.get("type")
                raw_query = raw_query.get("value", json.dumps(raw_query, sort_keys=True))
            sql_queries.append(
                {
                    "pipeline": name,
                    "query_index": len(sql_queries) + 1,
                    "expression_type": expression_type,
                    "sql_query": str(raw_query),
                }
            )

        if "name" in node and "type" in node:
            type_props = node.get("typeProperties", {})
            depends_on = node.get("dependsOn") or []
            dependency_names = []
            for dep in depends_on:
                if isinstance(dep, dict):
                    dependency_names.append(str(dep.get("activity", "")))
            stored_procedure_name = type_props.get("storedProcedureName")
            if stored_procedure_name:
                params = type_props.get("storedProcedureParameters")
                sp_rows.append(
                    {
                        "pipeline": name,
                        "activity_name": node.get("name"),
                        "stored_procedure_name": stored_procedure_name,
                        "stored_procedure_parameters": json.dumps(params, sort_keys=True) if params else None,
                    }
                )
            if node.get("type") == "InvokePipeline":
                invocation_rows.append(
                    {
                        "pipeline": name,
                        "activity_name": node.get("name"),
                        "invoked_pipeline_id": type_props.get("pipelineId"),
                        "invoked_workspace_id": type_props.get("workspaceId"),
                        "wait_on_completion": type_props.get("waitOnCompletion"),
                        "operation_type": type_props.get("operationType"),
                        "parameters": json.dumps(type_props.get("parameters", {}), sort_keys=True),
                    }
                )
            activity_rows.append(
                {
                    "pipeline": name,
                    "activity_name": node.get("name"),
                    "activity_type": node.get("type"),
                    "state": node.get("state", "Active"),
                    "depends_on": ",".join(filter(None, dependency_names)),
                    "batch_count": type_props.get("batchCount"),
                    "is_sequential": type_props.get("isSequential"),
                    "retry": get_nested(node, ["policy", "retry"]),
                    "retry_interval_seconds": get_nested(node, ["policy", "retryIntervalInSeconds"]),
                    "timeout": get_nested(node, ["policy", "timeout"]),
                }
            )

    joined_queries = "\n".join(row["sql_query"] for row in sql_queries).lower()
    return {
        "pipeline": name,
        "has_pipeline_content": True,
        "parameter_count": len(parameters),
        "variable_count": len(variables),
        "activity_count": len(activity_rows),
        "sql_query_count": len(sql_queries),
        "stored_procedure_activity_count": len(sp_rows),
        "pipeline_invocation_count": len(invocation_rows),
        "has_next_run_time_filter": "next_run_time" in joined_queries and "getutcdate" in joined_queries,
        "has_project_filter": "project" in joined_queries,
        "has_dq_activity_name": any("dq" in str(a["activity_name"]).lower() for a in activity_rows),
        "inactive_activity_count": sum(1 for a in activity_rows if str(a.get("state", "")).lower() == "inactive"),
        "parameters": parameters,
        "variables": variables,
        "activities": activity_rows,
        "sql_queries": sql_queries,
        "stored_procedures": sp_rows,
        "invocations": invocation_rows,
    }


def get_pipeline_definition(token: str, base: str, pipeline_id: str) -> dict[str, Any]:
    data_pipeline_url = f"{base}/dataPipelines/{pipeline_id}/getDefinition"
    item_url = f"{base}/items/{pipeline_id}/getDefinition"
    try:
        return request_json("POST", data_pipeline_url, token)
    except RuntimeError:
        return request_json("POST", item_url, token)


def export_rest(output_dir: pathlib.Path) -> dict[str, Any]:
    token = run_az_token("https://api.fabric.microsoft.com")
    rest_dir = output_dir / "rest"
    pipeline_dir = output_dir / "pipeline_definitions"
    rest_dir.mkdir(parents=True, exist_ok=True)
    pipeline_dir.mkdir(parents=True, exist_ok=True)

    summary: dict[str, Any] = {"pipeline_summaries": []}
    base = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}"

    endpoint_urls = {
        "items_all": f"{base}/items?include=DefaultIdentity",
        "items_dataPipelines": f"{base}/items?type=DataPipeline",
        "items_dataflows": f"{base}/items?type=Dataflow",
        "items_notebooks": f"{base}/items?type=Notebook",
        "items_reports": f"{base}/items?type=Report",
        "items_semanticModels": f"{base}/items?type=SemanticModel",
        "items_lakehouses": f"{base}/items?type=Lakehouse",
        "items_warehouses": f"{base}/items?type=Warehouse",
        "warehouses": f"{base}/warehouses",
        "lakehouses": f"{base}/lakehouses",
        "semanticModels": f"{base}/semanticModels",
    }

    item_rows: list[dict[str, Any]] = []
    for endpoint_name, url in endpoint_urls.items():
        try:
            try:
                payload = list_all(token, url)
            except RuntimeError:
                if endpoint_name == "items_all":
                    payload = list_all(token, f"{base}/items")
                else:
                    raise
            write_json(rest_dir / f"{endpoint_name}.json", payload)
            summary[f"{endpoint_name}_status"] = "exported"
            summary[f"{endpoint_name}_count"] = payload.get("count", len(payload.get("value", [])))
            if endpoint_name == "items_all":
                for item in payload.get("value", []):
                    item_rows.append(
                        {
                            "id": item.get("id"),
                            "displayName": item.get("displayName"),
                            "type": item.get("type"),
                            "workspaceId": item.get("workspaceId"),
                            "folderId": item.get("folderId"),
                            "description": item.get("description"),
                        }
                    )
        except Exception as exc:  # noqa: BLE001
            summary[f"{endpoint_name}_status"] = f"error: {exc}"

    by_type: dict[str, list[str]] = defaultdict(list)
    focus_rows: list[dict[str, Any]] = []
    for row in item_rows:
        by_type[str(row.get("type"))].append(str(row.get("displayName")))
        name = str(row.get("displayName"))
        if name in FOCUS_ITEM_NAMES or name in V9_PIPELINES:
            focus_rows.append(row)
    write_dict_csv(output_dir / "workspace_items_all.csv", item_rows)
    write_json(rest_dir / "items_by_type_summary.json", {key: sorted(values) for key, values in sorted(by_type.items())})
    write_dict_csv(output_dir / "workspace_focus_items.csv", focus_rows)

    activity_rows: list[dict[str, Any]] = []
    query_rows: list[dict[str, Any]] = []
    sp_rows: list[dict[str, Any]] = []
    invocation_rows: list[dict[str, Any]] = []
    parameter_rows: list[dict[str, Any]] = []

    for pipeline_name, pipeline_id in V9_PIPELINES.items():
        try:
            definition = get_pipeline_definition(token, base, pipeline_id)
            write_json(rest_dir / f"definition_{pipeline_name}.json", definition)
            parts = decode_definition_parts(definition, pipeline_dir / pipeline_name)
            pipeline_summary = summarize_pipeline(pipeline_name, parts)
            summary["pipeline_summaries"].append(
                {k: v for k, v in pipeline_summary.items() if k not in ("activities", "sql_queries", "stored_procedures", "invocations", "parameters", "variables")}
            )
            activity_rows.extend(pipeline_summary.get("activities", []))
            query_rows.extend(pipeline_summary.get("sql_queries", []))
            sp_rows.extend(pipeline_summary.get("stored_procedures", []))
            invocation_rows.extend(pipeline_summary.get("invocations", []))
            for param_name, param_def in (pipeline_summary.get("parameters") or {}).items():
                parameter_rows.append(
                    {
                        "pipeline": pipeline_name,
                        "parameter_name": param_name,
                        "definition": json.dumps(param_def, sort_keys=True),
                    }
                )
        except Exception as exc:  # noqa: BLE001
            summary["pipeline_summaries"].append({"pipeline": pipeline_name, "error": str(exc)})

    write_dict_csv(output_dir / "pipeline_activity_summary.csv", activity_rows)
    write_dict_csv(output_dir / "pipeline_sql_queries.csv", query_rows)
    write_dict_csv(output_dir / "pipeline_stored_procedures.csv", sp_rows)
    write_dict_csv(output_dir / "pipeline_invocations.csv", invocation_rows)
    write_dict_csv(output_dir / "pipeline_parameters.csv", parameter_rows)
    return summary


def export_static_sql(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
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
            write_text(path.with_suffix(path.suffix + ".error.txt"), str(exc))
    return summary


def export_meta_tables(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    _, table_rows = query_rows(
        conn,
        """
        SELECT t.name AS table_name
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = 'meta'
        ORDER BY t.name;
        """,
    )
    summary: dict[str, Any] = {}
    meta_dir = output_dir / "sql" / "meta_tables"
    for row in table_rows:
        table_name = row["table_name"]
        path = meta_dir / f"{safe_filename(table_name)}.csv"
        try:
            count = write_query_csv(conn, f"SELECT * FROM meta.{quote_name(table_name)};", path)
            summary[table_name] = {"status": "exported", "rows": count}
        except Exception as exc:  # noqa: BLE001
            summary[table_name] = {"status": "error", "error": str(exc)}
            write_text(path.with_suffix(path.suffix + ".error.txt"), str(exc))
    return summary


def export_definitions(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    definitions_dir = output_dir / "sql_definitions"
    _, rows = query_rows(
        conn,
        """
        SELECT
            s.name AS schema_name,
            o.name AS object_name,
            o.type_desc,
            m.definition
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
        WHERE o.type IN ('V', 'P', 'FN', 'IF', 'TF')
          AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
        ORDER BY s.name, o.type_desc, o.name;
        """,
    )
    summary: dict[str, Any] = {}
    for row in rows:
        object_kind = "views" if row["type_desc"] == "VIEW" else "routines"
        schema_name = row["schema_name"]
        object_name = row["object_name"]
        path = definitions_dir / object_kind / safe_filename(schema_name) / f"{safe_filename(object_name)}.sql"
        header = (
            f"-- Source: {DATABASE}.{schema_name}.{object_name}\n"
            f"-- Object type: {row['type_desc']}\n"
            f"-- Exported read-only from sys.sql_modules.\n\n"
        )
        write_text(path, header + str(row["definition"]))
        summary[f"{schema_name}.{object_name}"] = {"type_desc": row["type_desc"], "path": str(path.relative_to(output_dir))}
    return {"object_count": len(rows), "objects": summary}


def format_sql_type(row: dict[str, Any]) -> str:
    data_type = str(row["data_type"]).lower()
    char_len = row.get("character_maximum_length")
    precision = row.get("numeric_precision")
    scale = row.get("numeric_scale")
    dt_precision = row.get("datetime_precision")

    if data_type in {"char", "varchar", "nchar", "nvarchar", "binary", "varbinary"}:
        if char_len is None:
            return data_type
        if int(char_len) == -1:
            return f"{data_type}(max)"
        return f"{data_type}({int(char_len)})"
    if data_type in {"decimal", "numeric"} and precision is not None and scale is not None:
        return f"{data_type}({int(precision)},{int(scale)})"
    if data_type in {"datetime2", "datetimeoffset", "time"} and dt_precision is not None:
        return f"{data_type}({int(dt_precision)})"
    return data_type


def export_table_ddl_snapshots(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    _, rows = query_rows(
        conn,
        """
        SELECT
            c.table_schema,
            c.table_name,
            c.column_name,
            c.ordinal_position,
            c.data_type,
            c.character_maximum_length,
            c.numeric_precision,
            c.numeric_scale,
            c.datetime_precision,
            c.is_nullable
        FROM INFORMATION_SCHEMA.COLUMNS c
        INNER JOIN INFORMATION_SCHEMA.TABLES t
            ON t.table_schema = c.table_schema
           AND t.table_name = c.table_name
           AND t.table_type = 'BASE TABLE'
        ORDER BY c.table_schema, c.table_name, c.ordinal_position;
        """,
    )
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[(row["table_schema"], row["table_name"])].append(row)

    ddl_dir = output_dir / "sql_definitions" / "tables"
    for (schema_name, table_name), columns in grouped.items():
        lines = [
            f"-- Source: {DATABASE}.{schema_name}.{table_name}",
            "-- Generated from INFORMATION_SCHEMA.COLUMNS.",
            "-- This is a logical schema snapshot; review Fabric physical options before execution.",
            f"CREATE TABLE {quote_name(schema_name)}.{quote_name(table_name)} (",
        ]
        column_lines = []
        for col in sorted(columns, key=lambda r: int(r["ordinal_position"])):
            nullable = "NULL" if str(col["is_nullable"]).upper() == "YES" else "NOT NULL"
            column_lines.append(f"    {quote_name(col['column_name'])} {format_sql_type(col)} {nullable}")
        lines.append(",\n".join(column_lines))
        lines.append(");")
        path = ddl_dir / safe_filename(schema_name) / f"{safe_filename(table_name)}.sql"
        write_text(path, "\n".join(lines) + "\n")
    return {"table_count": len(grouped)}


def parse_json_array_maybe(value: Any) -> list[str]:
    if value is None:
        return []
    text = str(value).strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return [text]
    if isinstance(parsed, list):
        return [str(item) for item in parsed]
    return [str(parsed)]


def export_registry_edges(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    _, rows = query_rows(conn, "SELECT sp_name, target_schema, target_table, layer, project, depends_on, source_objects FROM meta.sp_registry;")
    source_edges: list[dict[str, Any]] = []
    dependency_edges: list[dict[str, Any]] = []
    for row in rows:
        target = f"{row['target_schema']}.{row['target_table']}"
        for source in parse_json_array_maybe(row.get("source_objects")):
            source_edges.append(
                {
                    "edge_type": "source_object",
                    "source": source,
                    "target": target,
                    "target_layer": row.get("layer"),
                    "project": row.get("project"),
                    "sp_name": row.get("sp_name"),
                }
            )
        for dep in parse_json_array_maybe(row.get("depends_on")):
            dependency_edges.append(
                {
                    "edge_type": "depends_on",
                    "source": dep,
                    "target": row.get("sp_name"),
                    "target_layer": row.get("layer"),
                    "project": row.get("project"),
                    "target_table": target,
                }
            )
    write_dict_csv(output_dir / "sql" / "registry_source_edges.csv", source_edges)
    write_dict_csv(output_dir / "sql" / "registry_dependency_edges.csv", dependency_edges)
    return {"source_edge_count": len(source_edges), "dependency_edge_count": len(dependency_edges)}


def export_registry_with_row_counts(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    _, registry_rows = query_rows(
        conn,
        """
        SELECT
            layer,
            project,
            target_schema,
            target_table,
            load_type,
            is_active,
            rows_loaded,
            last_load_date,
            next_run_time,
            source_objects,
            depends_on
        FROM meta.sp_registry
        ORDER BY layer, target_schema, target_table;
        """,
    )
    _, count_rows = query_rows(
        conn,
        """
        SELECT
            s.name AS schema_name,
            t.name AS table_name,
            SUM(p.rows) AS row_count
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.partitions p
            ON p.object_id = t.object_id
           AND p.index_id IN (0, 1)
        GROUP BY s.name, t.name;
        """,
    )
    row_count_by_table = {
        (row["schema_name"], row["table_name"]): row["row_count"]
        for row in count_rows
    }
    output_rows: list[dict[str, Any]] = []
    for row in registry_rows:
        output_rows.append(
            {
                "layer": row.get("layer"),
                "project": row.get("project"),
                "target_schema": row.get("target_schema"),
                "target_table": row.get("target_table"),
                "load_type": row.get("load_type"),
                "is_active": row.get("is_active"),
                "registry_rows_loaded": row.get("rows_loaded"),
                "current_table_row_count": row_count_by_table.get((row.get("target_schema"), row.get("target_table"))),
                "last_load_date": row.get("last_load_date"),
                "next_run_time": row.get("next_run_time"),
                "source_objects": row.get("source_objects"),
                "depends_on": row.get("depends_on"),
            }
        )
    write_dict_csv(output_dir / "sql" / "24_registry_tables_with_row_counts.csv", output_rows)
    return {"rows": len(output_rows), "join_mode": "local_postprocess"}


def export_sql(output_dir: pathlib.Path) -> dict[str, Any]:
    conn = connect_sql()
    summary: dict[str, Any] = {}
    try:
        summary["static_exports"] = export_static_sql(conn, output_dir)
        summary["meta_table_exports"] = export_meta_tables(conn, output_dir)
        summary["definition_exports"] = export_definitions(conn, output_dir)
        summary["table_ddl_exports"] = export_table_ddl_snapshots(conn, output_dir)
        summary["registry_edges"] = export_registry_edges(conn, output_dir)
        summary["registry_with_row_counts"] = export_registry_with_row_counts(conn, output_dir)
    finally:
        conn.close()
    return summary


def csv_rows(path: pathlib.Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        out.append("| " + " | ".join(str(cell) for cell in row) + " |")
    return "\n".join(out)


def render_analysis(output_dir: pathlib.Path, run_summary: dict[str, Any]) -> None:
    analysis_dir = output_dir / "analysis"
    items = csv_rows(output_dir / "workspace_items_all.csv")
    focus_items = csv_rows(output_dir / "workspace_focus_items.csv")
    object_counts = csv_rows(output_dir / "sql" / "02_object_counts_by_schema.csv")
    registry_summary = csv_rows(output_dir / "sql" / "07_sp_registry_summary.csv")
    pipeline_summaries = run_summary.get("rest_exports", {}).get("pipeline_summaries", [])
    v9_inventory = csv_rows(output_dir / "sql" / "05_v9_layer_inventory.csv")

    item_type_counts = Counter(row.get("type", "") for row in items)
    analysis_summary = [
        "# V9 Forecast Detail Clone Summary",
        "",
        f"- Timestamp: `{run_summary['timestamp']}`",
        f"- Workspace ID: `{WORKSPACE_ID}`",
        f"- Warehouse: `{DATABASE}` / `{WAREHOUSE_ID}`",
        "- Scope: live SupplyChain v9 Forecast Accuracy evidence clone.",
        "- Safety: read-only REST and read-only SQL metadata export; no business data rows exported.",
        "- Deletion status: no delete/drop/truncate/update operation executed.",
        "",
        "## Workspace Counts",
        "",
        markdown_table(["Item type", "Count"], [[k, v] for k, v in sorted(item_type_counts.items())]),
        "",
        "## Focus Items",
        "",
        markdown_table(
            ["Type", "Display name", "ID"],
            [[row.get("type"), row.get("displayName"), row.get("id")] for row in focus_items],
        ),
        "",
        "## V9 Registry Summary",
        "",
        markdown_table(
            ["Layer", "Schema", "Project", "Load type", "Frequency", "Active", "Count"],
            [
                [
                    row.get("layer"),
                    row.get("target_schema"),
                    row.get("project"),
                    row.get("load_type"),
                    row.get("frequency"),
                    row.get("is_active"),
                    row.get("object_count"),
                ]
                for row in registry_summary
            ],
        ),
        "",
        "## Object Counts",
        "",
        markdown_table(
            ["Schema", "Object type", "Count"],
            [[row.get("schema_name"), row.get("type_desc"), row.get("object_count")] for row in object_counts],
        ),
    ]
    write_text(analysis_dir / "00_clone_summary.md", "\n".join(analysis_summary) + "\n")

    pipeline_rows = [
        [
            row.get("pipeline"),
            row.get("activity_count"),
            row.get("sql_query_count"),
            row.get("stored_procedure_activity_count"),
            row.get("pipeline_invocation_count"),
            row.get("has_next_run_time_filter"),
            row.get("has_project_filter"),
        ]
        for row in pipeline_summaries
    ]
    write_text(
        analysis_dir / "01_v9_pipeline_inventory.md",
        "\n".join(
            [
                "# V9 Pipeline Inventory",
                "",
                markdown_table(
                    [
                        "Pipeline",
                        "Activities",
                        "SQL queries",
                        "SP activities",
                        "Invokes",
                        "Smart skip",
                        "Project filter",
                    ],
                    pipeline_rows,
                ),
                "",
                "Detailed CSV files:",
                "",
                "- `pipeline_activity_summary.csv`",
                "- `pipeline_sql_queries.csv`",
                "- `pipeline_stored_procedures.csv`",
                "- `pipeline_invocations.csv`",
                "- `pipeline_parameters.csv`",
            ]
        )
        + "\n",
    )

    write_text(
        analysis_dir / "02_sql_control_plane_inventory.md",
        "\n".join(
            [
                "# SQL Control Plane Inventory",
                "",
                "Primary evidence files:",
                "",
                "- `sql/06_sp_registry.csv`",
                "- `sql/08_registry_dependency_map.csv`",
                "- `sql/10_lineage.csv`",
                "- `sql/11_dq_rules.csv`",
                "- `sql/13_dq_results.csv`",
                "- `sql/14_sp_run_history.csv`",
                "- `sql/15_pipeline_run_log.csv`",
                "- `sql/16_slv_dag_waves_runtime.csv`",
                "- `sql/17_table_dictionary.csv`",
                "- `sql/meta_tables/*.csv`",
                "- `sql_definitions/views/*/*.sql`",
                "- `sql_definitions/routines/*/*.sql`",
                "",
                "Important: `sql_definitions/tables/*/*.sql` are logical schema snapshots generated from `INFORMATION_SCHEMA.COLUMNS`, not exact physical deployment scripts.",
            ]
        )
        + "\n",
    )

    candidate_rows = []
    for row in v9_inventory:
        candidate_rows.append(
            [
                row.get("schema_name"),
                row.get("object_name"),
                row.get("type_desc"),
                "inventory-only; do not delete without Aric approval",
            ]
        )
    write_text(
        analysis_dir / "03_v9_delete_candidates_review.md",
        "\n".join(
            [
                "# V9 Delete Candidates Review",
                "",
                "No deletion has been executed.",
                "",
                "This is only an inventory of live v9-related objects that may need migration, archive, rename, or delete decisions later. Do not delete anything in this list until Aric approves the exact action in the same conversation.",
                "",
                "## Confirmed V9 Pipeline Items",
                "",
                markdown_table(
                    ["Pipeline", "ID", "Action status"],
                    [[name, pid, "candidate inventory only; no delete approval"] for name, pid in V9_PIPELINES.items()],
                ),
                "",
                "## SQL Objects In V9 Layer Schemas",
                "",
                markdown_table(["Schema", "Object", "Type", "Action status"], candidate_rows),
                "",
                "## Explicit Do-Not-Touch Boundary",
                "",
                "- Do not touch v8/production assets.",
                "- Do not touch non-`pl_sc_*` legacy/notebook pipelines unless separately classified and approved.",
                "- Do not drop `Enterprise_Lakehouse`, shortcuts, semantic models, reports, or any Warehouse until v10 cutover is approved.",
            ]
        )
        + "\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default=None)
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = pathlib.Path(args.output_dir) if args.output_dir else root / "detail_clone_v9_forecast" / timestamp
    output_dir.mkdir(parents=True, exist_ok=True)

    run_summary: dict[str, Any] = {
        "timestamp": timestamp,
        "workspace_id": WORKSPACE_ID,
        "warehouse_id": WAREHOUSE_ID,
        "sql_server": SQL_SERVER,
        "database": DATABASE,
        "output_dir": str(output_dir),
        "safety": {
            "mode": "read_only_clone",
            "business_data_rows_exported": False,
            "destructive_operations_executed": False,
        },
    }

    try:
        run_summary["sql_exports"] = export_sql(output_dir)
    except Exception as exc:  # noqa: BLE001
        run_summary["sql_export_error"] = str(exc)

    try:
        run_summary["rest_exports"] = export_rest(output_dir)
    except Exception as exc:  # noqa: BLE001
        run_summary["rest_export_error"] = str(exc)

    try:
        render_analysis(output_dir, run_summary)
    except Exception as exc:  # noqa: BLE001
        run_summary["analysis_error"] = str(exc)

    write_json(output_dir / "run_summary.json", run_summary)
    print(output_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
