from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .dependency_parser import extract_object_refs
from .snapshot_writer import now_utc


def load_live_baseline(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def build_live_baseline(
    sql_scan: dict[str, Any],
    *,
    workspace_id: str,
    workspace_name: str,
) -> dict[str, Any]:
    dependency_map: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for database, rows in sql_scan.get("dependencies", {}).items():
        for row in rows:
            key = (
                database,
                str(row.get("referencing_schema_name") or ""),
                str(row.get("referencing_object_name") or ""),
            )
            dependency_map.setdefault(key, []).append(
                {
                    "database": str(row.get("referenced_database_name") or database),
                    "schema": str(row.get("referenced_schema_name") or ""),
                    "object_name": str(row.get("referenced_object_name") or ""),
                }
            )

    views: list[dict[str, Any]] = []
    for database, rows in sql_scan.get("modules", {}).items():
        for row in rows:
            if str(row.get("type_desc") or "").upper() != "VIEW":
                continue
            schema = str(row.get("schema_name") or "")
            object_name = str(row.get("object_name") or "")
            deps = dependency_map.get((database, schema, object_name), [])
            if not deps:
                definition = str(row.get("definition") or "")
                deps = [
                    {
                        "database": ref.database or database,
                        "schema": ref.schema,
                        "object_name": ref.object_name,
                    }
                    for ref in extract_object_refs(definition, default_database=database)
                ]
            unique = {
                (dep["database"], dep["schema"], dep["object_name"]): dep
                for dep in deps
                if dep["schema"] and dep["object_name"]
            }
            views.append(
                {
                    "database": database,
                    "schema": schema,
                    "object_name": object_name,
                    "dependencies": sorted(
                        unique.values(),
                        key=lambda item: (item["database"], item["schema"], item["object_name"]),
                    ),
                }
            )

    return {
        "schema_version": 1,
        "generated_at_utc": now_utc(),
        "workspace": {"id": workspace_id, "name": workspace_name},
        "summary": {
            "view_count": len(views),
            "dependency_edge_count": sum(len(view["dependencies"]) for view in views),
            "system_dependency_row_count": sum(
                len(rows) for rows in sql_scan.get("dependencies", {}).values()
            ),
        },
        "views": sorted(
            views,
            key=lambda item: (item["database"], item["schema"], item["object_name"]),
        ),
    }


def write_live_baseline(path: Path, baseline: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
