#!/usr/bin/env python3
"""
Normalize v10 inventory project taxonomy and tighten pipeline routing.

Scope:
- Meta.AssetRegistry.project: inventoryHistory_Enh -> inventory_health
- Meta.AssetRegistry.frequency: Daily -> daily for the affected inventory rows
- Meta.usp_ComputeSilverWaves @project='inventory_health'
- Fabric pipeline definitions:
  - pl_sc_master: deterministic project order (shared -> forecast_accuracy -> inventory_health)
  - pl_sc_staging: ReferenceMaster lookup filtered by current project
  - pl_sc_gold: Gold lookup filtered by current project

This script is intentionally narrow and idempotent. It writes backups/artifacts
under Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import pathlib
import struct
import subprocess
import sys
from typing import Any

import pyodbc


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
SQL_DATABASE = "SupplyChain_Processing_Warehouse"
FABRIC_BASE = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}"

PIPELINES = {
    "pl_sc_master": "f36f56b8-5668-4a0c-b991-2c28302f1710",
    "pl_sc_staging": "10221fb2-6e30-4911-9d95-d8dd67440d84",
    "pl_sc_gold": "50ff6263-659d-4b09-9e45-b42a3434e093",
}

MASTER_OLD = (
    "SELECT DISTINCT project FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry "
    "WHERE is_active = 1 AND project IS NOT NULL"
)
MASTER_NEW = (
    "SELECT DISTINCT project FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry "
    "WHERE is_active = 1 AND project IS NOT NULL "
    "ORDER BY CASE "
    "WHEN project = 'shared' THEN 0 "
    "WHEN project = 'forecast_accuracy' THEN 1 "
    "WHEN project = 'inventory_health' THEN 2 "
    "ELSE 99 END, project"
)

STAGING_OLD = (
    "SELECT r.target_schema, r.target_table FROM SupplyChain_Processing_Warehouse.Meta.v_sp_registry r "
    "WHERE r.layer IN ('ReferenceMaster') AND r.is_active = 1 "
    "AND (r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())"
)
STAGING_NEW = (
    "SELECT r.target_schema, r.target_table FROM SupplyChain_Processing_Warehouse.Meta.v_sp_registry r "
    "WHERE r.layer IN ('ReferenceMaster') AND r.is_active = 1 "
    "AND r.project = '@{pipeline().parameters.project_name}' "
    "AND (r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())"
)

GOLD_OLD = (
    "SELECT r.physical_schema, r.physical_object, REPLACE(r.legacy_view_name, "
    "r.physical_schema + '.', '') AS view_name FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry r "
    "WHERE r.canonical_layer = 'Gold' AND r.is_active = 1 "
    "ORDER BY CASE WHEN r.physical_object LIKE 'Dim%' THEN 0 ELSE 1 END, r.physical_object"
)
GOLD_NEW = (
    "SELECT r.physical_schema, r.physical_object, REPLACE(r.legacy_view_name, "
    "r.physical_schema + '.', '') AS view_name FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry r "
    "WHERE r.canonical_layer = 'Gold' AND r.is_active = 1 "
    "AND r.project = '@{pipeline().parameters.project_name}' "
    "ORDER BY CASE WHEN r.physical_object LIKE 'Dim%' THEN 0 ELSE 1 END, r.physical_object"
)


def run(cmd: list[str], *, input_text: str | None = None) -> str:
    return subprocess.check_output(cmd, text=True, input=input_text)


def az_token(resource: str) -> str:
    return run(
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
    ).strip()


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


def get_pipeline_definition(pipeline_id: str) -> dict[str, Any]:
    return fabric_request("POST", f"{FABRIC_BASE}/items/{pipeline_id}/getDefinition")


def update_pipeline_definition(pipeline_id: str, definition: dict[str, Any]) -> dict[str, Any]:
    return fabric_request(
        "POST",
        f"{FABRIC_BASE}/items/{pipeline_id}/updateDefinition",
        {"definition": definition["definition"]},
    )


def decode_pipeline_content(definition: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    part = next(p for p in definition["definition"]["parts"] if p["path"] == "pipeline-content.json")
    payload = base64.b64decode(part["payload"]).decode("utf-8")
    return part, json.loads(payload)


def encode_pipeline_content(part: dict[str, Any], content: dict[str, Any]) -> dict[str, Any]:
    updated = dict(part)
    updated["payload"] = base64.b64encode(json.dumps(content, indent=2).encode("utf-8")).decode("ascii")
    updated["payloadType"] = "InlineBase64"
    return updated


def write_json(path: pathlib.Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")


def write_text(path: pathlib.Path, payload: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="utf-8")


def replace_sql_query(content: dict[str, Any], old: str, new: str) -> bool:
    raw = json.dumps(content)
    if new in raw:
        return True
    if old not in raw:
        return False
    raw = raw.replace(old, new)
    content.clear()
    content.update(json.loads(raw))
    return True


def fetch_sql_rows(conn: pyodbc.Connection, sql: str) -> list[dict[str, Any]]:
    cur = conn.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def execute_sql(conn: pyodbc.Connection, sql: str) -> None:
    cur = conn.cursor()
    cur.execute(sql)
    conn.commit()


def build_output_dir(root: pathlib.Path) -> pathlib.Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = root / "Enterprise_SupplyChain_Dev_architect" / "artifacts" / "build_runs" / f"{ts}_inventory_project_taxonomy_fix"
    out.mkdir(parents=True, exist_ok=True)
    return out


def backup_state(root: pathlib.Path, output_dir: pathlib.Path, conn: pyodbc.Connection) -> None:
    sql_snapshots = {
        "asset_registry_inventory_before.json": """
            SELECT asset_id, project, canonical_layer, physical_schema, physical_object,
                   frequency, load_type, is_active, depends_on, source_objects, updated_at_utc
            FROM Meta.AssetRegistry
            WHERE project IN ('inventoryHistory_Enh', 'inventory_health', 'shared')
            ORDER BY project, canonical_layer, asset_id;
        """,
        "silver_wave_inventory_before.json": """
            SELECT project, asset_id, physical_schema, physical_object, wave_number,
                   dependency_count, is_active, computed_at_utc
            FROM Meta.SilverDagWaveRuntime
            WHERE project IN ('inventoryHistory_Enh', 'inventory_health', 'shared')
            ORDER BY project, wave_number, asset_id;
        """,
        "pipeline_runlog_before.json": """
            SELECT pipeline_name, project, status, trigger_type, start_time_utc, end_time_utc
            FROM Meta.PipelineRunLog
            ORDER BY start_time_utc DESC;
        """,
    }
    for filename, sql in sql_snapshots.items():
        write_json(output_dir / "sql_backups" / filename, fetch_sql_rows(conn, sql))

    for name, pipeline_id in PIPELINES.items():
        definition = get_pipeline_definition(pipeline_id)
        write_json(output_dir / "pipeline_backups" / f"{name}_before_getDefinition.json", definition)
        _, content = decode_pipeline_content(definition)
        write_text(
            output_dir / "pipeline_backups" / f"{name}_before_pipeline-content.json",
            json.dumps(content, indent=2),
        )


def apply_sql_changes(conn: pyodbc.Connection) -> None:
    sql = """
    BEGIN TRAN;

    UPDATE Meta.AssetRegistry
       SET project = 'inventory_health',
           updated_at_utc = SYSUTCDATETIME()
     WHERE project = 'inventoryHistory_Enh';

    UPDATE Meta.AssetRegistry
       SET frequency = 'daily',
           updated_at_utc = SYSUTCDATETIME()
     WHERE project = 'inventory_health'
       AND frequency = 'Daily';

    DELETE FROM Meta.SilverDagWaveRuntime
     WHERE project = 'inventoryHistory_Enh';

    EXEC Meta.usp_ComputeSilverWaves @project = 'inventory_health';

    COMMIT TRAN;
    """
    execute_sql(conn, sql)


def apply_pipeline_change(output_dir: pathlib.Path, name: str, old: str, new: str) -> None:
    pipeline_id = PIPELINES[name]
    definition = get_pipeline_definition(pipeline_id)
    part, content = decode_pipeline_content(definition)
    changed = replace_sql_query(content, old, new)
    if not changed:
        raise RuntimeError(f"{name}: expected SQL pattern not found")
    definition["definition"]["parts"] = [encode_pipeline_content(part, content)]
    write_text(
        output_dir / "pipeline_backups" / f"{name}_after_local_patch_pipeline-content.json",
        json.dumps(content, indent=2),
    )
    write_json(output_dir / "pipeline_backups" / f"{name}_update_definition_body.json", {"definition": definition["definition"]})
    update_pipeline_definition(pipeline_id, definition)


def verify(conn: pyodbc.Connection) -> dict[str, Any]:
    results: dict[str, Any] = {}
    results["asset_projects"] = fetch_sql_rows(
        conn,
        """
        SELECT project, canonical_layer, COUNT(*) AS cnt
        FROM Meta.AssetRegistry
        WHERE is_active = 1
        GROUP BY project, canonical_layer
        ORDER BY project, canonical_layer;
        """,
    )
    results["wave_projects"] = fetch_sql_rows(
        conn,
        """
        SELECT project, wave_number, COUNT(*) AS cnt
        FROM Meta.SilverDagWaveRuntime
        WHERE is_active = 1
        GROUP BY project, wave_number
        ORDER BY project, wave_number;
        """,
    )
    results["inventory_frequency_values"] = fetch_sql_rows(
        conn,
        """
        SELECT COALESCE(frequency, '<NULL>') AS frequency, COUNT(*) AS cnt
        FROM Meta.AssetRegistry
        WHERE project = 'inventory_health'
        GROUP BY frequency
        ORDER BY cnt DESC, frequency;
        """,
    )

    def _iter_strings(obj: Any) -> list[str]:
        out: list[str] = []
        if isinstance(obj, str):
            out.append(obj)
        elif isinstance(obj, list):
            for v in obj:
                out.extend(_iter_strings(v))
        elif isinstance(obj, dict):
            for v in obj.values():
                out.extend(_iter_strings(v))
        return out

    def _has_sql_fragment(strings: list[str], *fragments: str) -> bool:
        return any(all(frag in s for frag in fragments) for s in strings)

    for name, pipeline_id in PIPELINES.items():
        definition = get_pipeline_definition(pipeline_id)
        _, content = decode_pipeline_content(definition)
        strings = _iter_strings(content)
        results[name] = {
            "contains_master_ordering": any(MASTER_NEW in s for s in strings),
            "contains_staging_project_filter": _has_sql_fragment(
                strings,
                "FROM SupplyChain_Processing_Warehouse.Meta.v_sp_registry r",
                "r.layer IN ('ReferenceMaster')",
                "r.project = '@{pipeline().parameters.project_name}'",
            ),
            "contains_gold_project_filter": _has_sql_fragment(
                strings,
                "FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry r",
                "r.canonical_layer = 'Gold'",
                "r.project = '@{pipeline().parameters.project_name}'",
            ),
        }
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    output_dir = build_output_dir(root)

    conn = sql_conn()
    try:
        backup_state(root, output_dir, conn)

        if not args.verify_only:
            apply_sql_changes(conn)
            apply_pipeline_change(output_dir, "pl_sc_master", MASTER_OLD, MASTER_NEW)
            apply_pipeline_change(output_dir, "pl_sc_staging", STAGING_OLD, STAGING_NEW)
            apply_pipeline_change(output_dir, "pl_sc_gold", GOLD_OLD, GOLD_NEW)

        results = verify(conn)

        for name, pipeline_id in PIPELINES.items():
            definition = get_pipeline_definition(pipeline_id)
            write_json(output_dir / "pipeline_backups" / f"{name}_after_getDefinition.json", definition)
            _, content = decode_pipeline_content(definition)
            write_text(
                output_dir / "pipeline_backups" / f"{name}_after_pipeline-content.json",
                json.dumps(content, indent=2),
            )

        write_json(output_dir / "verification_summary.json", results)
        print(json.dumps({"output_dir": str(output_dir), "results": results}, indent=2))
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
