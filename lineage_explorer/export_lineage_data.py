#!/usr/bin/env python3
"""
Export live SupplyChain lineage data for the Streamlit Lineage Explorer.

Source of truth:
  - Active ETL assets: Meta.AssetRegistry where is_active = 1
  - Direct/derived edges: AssetRegistry.source_objects + AssetRegistry.depends_on
  - Semantic edges: Fabric semantic model getDefinition (TMDL partitions)

Do not use Meta.LineageEdge for direct ETL lineage here. In the current v10
workspace it can lag behind registry/code changes and still contain stale edges.
"""

from __future__ import annotations

import base64
import csv
import json
import os
import re
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import pyodbc


DEFAULT_SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)
DEFAULT_WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
DEFAULT_SILVER_WH = "SupplyChain_Processing_Warehouse"
DEFAULT_GOLD_WH = "SupplyChain_Gold_Warehouse"

DEFAULT_SEMANTIC_MODELS = [
    {
        "project": "forecast_accuracy",
        "name": "sc_forecast_control_tower",
        "id": "f06a2361-15fd-4f91-9d37-941fefe62aaf",
    },
    {
        "project": "inventory_health",
        "name": "sc_inventory_health_control_tower",
        "id": "88c3fccd-698d-4175-b7b9-ea377e0f5afc",
    },
]

DATA_DIR = Path(__file__).resolve().parent / "data"
STALE_TOKENS = (
    "ForecastSnapshotWeeklySat",
    "InventorySnapshotWeeklySat",
    "LogilityItemStatusSnapshotWeekly",
    "ATPSUM",
    "ATPQty",
    "ATPInStockFlag",
    "SalesShipment",
    "DimAFIWarehouses",
)


def _az_token(resource: str) -> str:
    cmd = [
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
    return subprocess.check_output(cmd, text=True).strip()


def _client_credentials_token(scope: str) -> str:
    tenant = os.environ["AZURE_TENANT_ID"]
    client_id = os.environ["AZURE_CLIENT_ID"]
    client_secret = os.environ["AZURE_CLIENT_SECRET"]
    token_url = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
    body = urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": scope,
        }
    ).encode()
    req = Request(
        token_url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    return json.loads(urlopen(req).read().decode("utf-8"))["access_token"]


def get_token(kind: str) -> str:
    if os.getenv("AZURE_CLIENT_ID") and os.getenv("AZURE_CLIENT_SECRET") and os.getenv("AZURE_TENANT_ID"):
        scope = {
            "database": "https://database.windows.net/.default",
            "fabric": "https://api.fabric.microsoft.com/.default",
        }[kind]
        return _client_credentials_token(scope)
    resource = {
        "database": "https://database.windows.net/",
        "fabric": "https://api.fabric.microsoft.com",
    }[kind]
    return _az_token(resource)


def connect(database: str, server: str, db_token: str) -> pyodbc.Connection:
    token_bytes = db_token.encode("UTF-16-LE")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server};"
        f"DATABASE={database};Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
    )


def rows_as_dicts(cursor: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def parse_asset_list(raw_value: Any) -> list[str]:
    if raw_value is None:
        return []
    raw = str(raw_value).strip()
    if not raw or raw.lower() in {"nan", "none", "null"}:
        return []
    if raw.startswith("["):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return [str(x).strip() for x in parsed if str(x).strip()]
        except Exception:
            pass
    return [x.strip().strip('"').strip("'") for x in raw.split(",") if x.strip()]


def split_asset(asset: str) -> tuple[str, str]:
    clean = (asset or "").strip().strip('"').strip("'")
    if not clean:
        return "", ""
    parts = [p for p in clean.split(".") if p]
    if len(parts) >= 2:
        if parts[0] in {"Enterprise_Lakehouse", "SupplyChain_Lakehouse", "SemanticModel"}:
            return parts[0], ".".join(parts[1:])
        return parts[0], ".".join(parts[1:])
    return clean, clean


def fetch_registry(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    sql = """
        SELECT
            ar.physical_schema + '.' + ar.physical_object AS sp_name,
            ar.legacy_view_name AS view_name,
            ar.physical_schema AS target_schema,
            ar.physical_object AS target_table,
            ar.canonical_layer AS layer,
            ar.load_type,
            ar.frequency,
            CASE WHEN ar.source_objects IS NOT NULL THEN 1 ELSE 0 END AS execution_order,
            ar.depends_on,
            ar.source_objects,
            ar.is_active,
            sdw.wave_number AS wave,
            ar.project,
            ar.asset_id,
            ar.access_mode,
            ar.physical_workspace,
            ar.physical_item
        FROM Meta.AssetRegistry ar
        LEFT JOIN Meta.SilverDagWaveRuntime sdw
               ON sdw.asset_id = ar.asset_id
        WHERE ar.is_active = 1
        ORDER BY ar.project, ar.canonical_layer, ar.physical_schema, ar.physical_object;
    """
    cur = conn.cursor()
    cur.execute(sql)
    return rows_as_dicts(cur)


def build_registry_edges(registry: list[dict[str, Any]]) -> list[dict[str, Any]]:
    edges: list[dict[str, Any]] = []
    edge_no = 1
    seen: set[tuple[str, str, str]] = set()
    for row in registry:
        target_schema = str(row.get("target_schema") or "").strip()
        target_table = str(row.get("target_table") or "").strip()
        target_asset = f"{target_schema}.{target_table}"
        for relationship, field in (("direct", "source_objects"), ("derived", "depends_on")):
            for source_asset in parse_asset_list(row.get(field)):
                source_schema, source_table = split_asset(source_asset)
                if not source_schema or not source_table:
                    continue
                key = (source_asset, target_asset, relationship)
                if key in seen:
                    continue
                seen.add(key)
                edges.append(
                    {
                        "lineage_id": edge_no,
                        "source_schema": source_schema,
                        "source_table": source_table,
                        "target_schema": target_schema,
                        "target_table": target_table,
                        "relationship_type": relationship,
                        "sp_name": target_asset,
                    }
                )
                edge_no += 1
    return edges


def fabric_request(method: str, url: str, token: str, body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
    req = Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urlopen(req) as resp:
        return resp.status, dict(resp.headers), resp.read()


def get_semantic_definition(workspace_id: str, model_id: str, token: str) -> dict[str, Any]:
    url = (
        f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
        f"/semanticModels/{model_id}/getDefinition?format=TMDL"
    )
    status, headers, payload = fabric_request("POST", url, token, body=b"{}")
    if status == 200:
        return json.loads(payload.decode("utf-8"))
    if status != 202:
        raise RuntimeError(f"Unexpected getDefinition status {status} for semantic model {model_id}")

    operation_url = headers.get("Location")
    if operation_url and operation_url.startswith("/"):
        operation_url = "https://api.fabric.microsoft.com" + operation_url
    operation_id = headers.get("x-ms-operation-id")
    retry_after = int(headers.get("Retry-After") or "5")
    if not operation_url and operation_id:
        operation_url = f"https://api.fabric.microsoft.com/v1/operations/{operation_id}"
    if not operation_url:
        raise RuntimeError(f"getDefinition LRO missing Location and operation id for {model_id}")

    for _ in range(120):
        time.sleep(retry_after)
        status, headers, payload = fabric_request("GET", operation_url, token)
        retry_after = int(headers.get("Retry-After") or "5")
        location = headers.get("Location")
        if location:
            operation_url = location if location.startswith("http") else "https://api.fabric.microsoft.com" + location
        if status == 200:
            text = payload.decode("utf-8")
            if text:
                try:
                    parsed = json.loads(text)
                    if "definition" in parsed:
                        return parsed
                    op_status = str(parsed.get("status") or "").lower()
                    if op_status == "failed":
                        raise RuntimeError(f"getDefinition LRO failed for {model_id}: {parsed}")
                    if op_status == "succeeded":
                        result_url = f"https://api.fabric.microsoft.com/v1/operations/{operation_id}/result"
                        result_status, _, result_payload = fabric_request("GET", result_url, token)
                        if result_status == 200:
                            return json.loads(result_payload.decode("utf-8"))
                except json.JSONDecodeError:
                    pass
        if operation_url.endswith("/result"):
            status, _, payload = fabric_request("GET", operation_url, token)
            if status == 200:
                return json.loads(payload.decode("utf-8"))
    raise TimeoutError(f"Timed out waiting for semantic model definition: {model_id}")


def decode_definition_parts(definition: dict[str, Any]) -> dict[str, str]:
    parts: dict[str, str] = {}
    for part in definition.get("definition", {}).get("parts", []):
        path = part.get("path") or ""
        payload = part.get("payload") or ""
        if not path or not payload:
            continue
        try:
            parts[path] = base64.b64decode(payload).decode("utf-8", errors="replace")
        except Exception:
            continue
    return parts


def extract_partition_source(tmdl: str) -> tuple[str, str] | None:
    direct_lake_entity = re.search(
        r"entityName:\s*([^\s]+)\s+schemaName:\s*([^\s]+)",
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if direct_lake_entity:
        return direct_lake_entity.group(2).strip("'\""), direct_lake_entity.group(1).strip("'\"")

    schema_item = re.search(
        r'Schema\s*=\s*"([^"]+)"\s*,\s*Item\s*=\s*"([^"]+)"',
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if schema_item:
        return schema_item.group(1), schema_item.group(2)

    bracket_ref = re.search(
        r"\[(Shared_DW|ForecastAccuracy_DW|InventoryHealth_DW)\]\.\[([^\]]+)\]",
        tmdl,
        flags=re.IGNORECASE,
    )
    if bracket_ref:
        return bracket_ref.group(1), bracket_ref.group(2)
    return None


def build_semantic_edges(workspace_id: str, models: list[dict[str, str]], fabric_token: str, start_id: int) -> list[dict[str, Any]]:
    edges: list[dict[str, Any]] = []
    edge_no = start_id
    for model in models:
        model_name = model["name"]
        definition = get_semantic_definition(workspace_id, model["id"], fabric_token)
        parts = decode_definition_parts(definition)
        for path, content in parts.items():
            if not path.startswith("definition/tables/") or not path.endswith(".tmdl"):
                continue
            semantic_table = Path(path).stem
            source = extract_partition_source(content)
            if not source:
                continue
            source_schema, source_table = source
            edges.append(
                {
                    "lineage_id": edge_no,
                    "source_schema": source_schema,
                    "source_table": source_table,
                    "target_schema": "SemanticModel",
                    "target_table": model_name,
                    "relationship_type": "semantic",
                    "sp_name": f"semantic::{model_name}::{semantic_table}",
                }
            )
            edge_no += 1
    return edges


def fetch_views(server: str, db_token: str, silver_wh: str, gold_wh: str) -> list[dict[str, Any]]:
    views_sql = """
        SELECT s.name AS [schema], v.name AS view_name, m.definition
        FROM sys.views v
        JOIN sys.schemas s ON v.schema_id = s.schema_id
        JOIN sys.sql_modules m ON v.object_id = m.object_id
        WHERE s.name NOT IN ('sys','queryinsights','INFORMATION_SCHEMA')
        ORDER BY s.name, v.name;
    """
    rows: list[dict[str, Any]] = []
    for wh_name in (silver_wh, gold_wh):
        with connect(wh_name, server, db_token) as conn:
            cur = conn.cursor()
            cur.execute(views_sql)
            for r in rows_as_dicts(cur):
                rows.append(
                    {
                        "warehouse": wh_name,
                        "schema": r["schema"],
                        "view_name": r["view_name"],
                        "definition": r["definition"] or "",
                    }
                )
    return rows


def fetch_run_history(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT TOP 50
            asset_id AS sp_name,
            status,
            rows_loaded AS rows_affected,
            DATEDIFF(SECOND, start_time_utc, COALESCE(end_time_utc, start_time_utc)) AS duration_seconds,
            start_time_utc AS start_time,
            load_type
        FROM Meta.RunLog
        WHERE status = 'success'
        ORDER BY start_time_utc DESC;
        """
    )
    return rows_as_dicts(cur)


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def normalize_for_csv(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for row in rows:
        out = {}
        for key, value in row.items():
            if isinstance(value, (list, dict)):
                out[key] = json.dumps(value, ensure_ascii=False)
            elif value is None:
                out[key] = ""
            else:
                out[key] = value
        normalized.append(out)
    return normalized


def load_semantic_models() -> list[dict[str, str]]:
    raw = os.getenv("SEMANTIC_MODELS_JSON")
    if not raw:
        return DEFAULT_SEMANTIC_MODELS
    parsed = json.loads(raw)
    if not isinstance(parsed, list):
        raise ValueError("SEMANTIC_MODELS_JSON must be a JSON list")
    return parsed


def stale_guard(registry: list[dict[str, Any]], lineage: list[dict[str, Any]]) -> None:
    text = "\n".join(json.dumps(r, default=str) for r in registry + lineage)
    hits = [token for token in STALE_TOKENS if token in text]
    if hits:
        raise RuntimeError(f"Stale lineage tokens found in active export: {', '.join(hits)}")


def main() -> int:
    server = os.getenv("FABRIC_SERVER", DEFAULT_SERVER)
    workspace_id = os.getenv("FABRIC_WORKSPACE_ID", DEFAULT_WORKSPACE_ID)
    silver_wh = os.getenv("SILVER_WH", DEFAULT_SILVER_WH)
    gold_wh = os.getenv("GOLD_WH", DEFAULT_GOLD_WH)

    db_token = get_token("database")
    fabric_token = get_token("fabric")

    with connect(silver_wh, server, db_token) as conn:
        registry = fetch_registry(conn)
        lineage = build_registry_edges(registry)
        semantic_edges = build_semantic_edges(
            workspace_id,
            load_semantic_models(),
            fabric_token,
            start_id=len(lineage) + 1,
        )
        lineage.extend(semantic_edges)
        run_history = fetch_run_history(conn)

    views = fetch_views(server, db_token, silver_wh, gold_wh)
    stale_guard(registry, lineage)

    registry_fields = [
        "sp_name",
        "view_name",
        "target_schema",
        "target_table",
        "layer",
        "load_type",
        "frequency",
        "execution_order",
        "depends_on",
        "source_objects",
        "is_active",
        "wave",
        "project",
        "asset_id",
        "access_mode",
        "physical_workspace",
        "physical_item",
    ]
    lineage_fields = [
        "lineage_id",
        "source_schema",
        "source_table",
        "target_schema",
        "target_table",
        "relationship_type",
        "sp_name",
    ]
    view_fields = ["warehouse", "schema", "view_name", "definition"]
    run_fields = ["sp_name", "status", "rows_affected", "duration_seconds", "start_time", "load_type"]

    write_csv(DATA_DIR / "registry.csv", normalize_for_csv(registry), registry_fields)
    write_csv(DATA_DIR / "lineage.csv", normalize_for_csv(lineage), lineage_fields)
    write_csv(DATA_DIR / "views.csv", normalize_for_csv(views), view_fields)
    write_csv(DATA_DIR / "run_history.csv", normalize_for_csv(run_history), run_fields)

    rel_counts: dict[str, int] = {}
    for row in lineage:
        key = str(row.get("relationship_type") or "")
        rel_counts[key] = rel_counts.get(key, 0) + 1
    print(
        json.dumps(
            {
                "registry_rows": len(registry),
                "lineage_rows": len(lineage),
                "lineage_by_type": rel_counts,
                "semantic_edges": len(semantic_edges),
                "views": len(views),
                "run_history": len(run_history),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[export_lineage_data] ERROR: {exc}", file=sys.stderr)
        raise
