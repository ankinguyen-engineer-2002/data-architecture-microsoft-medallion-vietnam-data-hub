from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .dependency_parser import extract_object_refs
from .snapshot_writer import now_utc


def load_live_baseline(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def validate_live_baseline(
    baseline: dict[str, Any] | None,
    *,
    max_age_hours: int | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Return machine-readable freshness and coverage evidence for a fallback."""
    if baseline is None:
        return {"status": "not_configured", "valid": False, "reason": "No live baseline supplied."}

    generated_at = str(baseline.get("generated_at_utc") or "")
    try:
        generated = datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
        if generated.tzinfo is None:
            generated = generated.replace(tzinfo=UTC)
    except ValueError:
        return {"status": "invalid", "valid": False, "reason": "Invalid generated_at_utc.", "generated_at_utc": generated_at}

    views = baseline.get("views")
    summary = baseline.get("summary") or {}
    if not isinstance(views, list):
        return {"status": "invalid", "valid": False, "reason": "Baseline views must be a list.", "generated_at_utc": generated_at}
    actual_edges = sum(len(view.get("dependencies") or []) for view in views if isinstance(view, dict))
    incomplete_views = [
        view for view in views
        if not isinstance(view, dict)
        or not view.get("database")
        or not view.get("schema")
        or not view.get("object_name")
        or not isinstance(view.get("dependencies"), list)
        or not view.get("dependencies")
    ]
    metadata: dict[str, Any] = {
        "generated_at_utc": generated_at,
        "view_count": len(views),
        "dependency_edge_count": actual_edges,
        "max_age_hours": max_age_hours,
    }
    if summary.get("view_count") != len(views) or summary.get("dependency_edge_count") != actual_edges or incomplete_views:
        metadata.update({"status": "incomplete", "valid": False, "reason": "Baseline summary or view dependency coverage is incomplete.", "incomplete_view_count": len(incomplete_views)})
        return metadata

    age_hours = ((now or datetime.now(UTC)) - generated).total_seconds() / 3600
    metadata["age_hours"] = round(age_hours, 3)
    if age_hours < 0 or (max_age_hours is not None and age_hours > max_age_hours):
        metadata.update({"status": "stale", "valid": False, "reason": "Baseline is outside the allowed age window."})
        return metadata
    metadata.update({"status": "valid", "valid": True, "reason": "Baseline freshness and coverage checks passed."})
    return metadata


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
