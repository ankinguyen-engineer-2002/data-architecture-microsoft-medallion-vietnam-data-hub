#!/usr/bin/env python3
"""Build non-destructive cleanup candidates for duplicate base-schema views."""

from __future__ import annotations

import argparse
import json
import pathlib
from typing import Any


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def module_refs(modules: list[dict[str, Any]], schema_name: str, view_name: str) -> list[dict[str, str]]:
    needles = [
        f"{schema_name}.{view_name}",
        f"[{schema_name}].[{view_name}]",
        f"{quote_name(schema_name)}.{quote_name(view_name)}",
    ]
    refs: list[dict[str, str]] = []
    for module in modules:
        if module["schema_name"] == schema_name and module["object_name"] == view_name:
            continue
        definition = module.get("definition") or ""
        if any(needle.lower() in definition.lower() for needle in needles):
            refs.append(
                {
                    "schema_name": module["schema_name"],
                    "object_name": module["object_name"],
                    "type_desc": module["type_desc"],
                }
            )
    return refs


def view_definition(modules: list[dict[str, Any]], schema_name: str, view_name: str) -> str | None:
    for module in modules:
        if module["schema_name"] == schema_name and module["object_name"] == view_name:
            return module.get("definition")
    return None


def build_for_database(db_key: str, db: dict[str, Any]) -> dict[str, Any]:
    modules = db["modules"]
    audit: list[dict[str, Any]] = []
    rollback_lines: list[str] = [
        f"-- Rollback definitions for {db['database']}",
        "-- Execute against the database named above.",
        "",
    ]
    drop_lines: list[str] = [
        f"-- Candidate duplicate base-view cleanup for {db['database']}",
        "-- Do not execute until dependency_audit.json has zero required refs and Aric approves this exact list.",
        "",
    ]
    for pair in db["schema_pairs"]:
        base_schema = pair["base_schema"]
        for view_name in pair["duplicate_base_views"]:
            refs = module_refs(modules, base_schema, view_name)
            definition = view_definition(modules, base_schema, view_name)
            audit.append(
                {
                    "database_key": db_key,
                    "database": db["database"],
                    "schema": base_schema,
                    "view": view_name,
                    "required_module_refs": refs,
                    "safe_to_drop_candidate": len(refs) == 0,
                }
            )
            rollback_lines.append(f"-- {db['database']}.{base_schema}.{view_name}")
            rollback_lines.append(definition or f"-- Definition not found for {base_schema}.{view_name}")
            rollback_lines.append("GO")
            rollback_lines.append("")
            drop_lines.append(f"DROP VIEW {quote_name(base_schema)}.{quote_name(view_name)};")
            drop_lines.append("GO")
    return {
        "audit": audit,
        "rollback_sql": "\n".join(rollback_lines).rstrip() + "\n",
        "drop_sql": "\n".join(drop_lines).rstrip() + "\n",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    all_audit: list[dict[str, Any]] = []
    for db_key in ["processing", "gold"]:
        built = build_for_database(db_key, scan["databases"][db_key])
        all_audit.extend(built["audit"])
        (out_dir / f"rollback_recreate_duplicate_base_views_{db_key}.sql").write_text(
            built["rollback_sql"], encoding="utf-8"
        )
        (out_dir / f"candidate_drop_duplicate_base_views_{db_key}.sql").write_text(
            built["drop_sql"], encoding="utf-8"
        )
    (out_dir / "dependency_audit.json").write_text(json.dumps(all_audit, indent=2), encoding="utf-8")
    blocked = [row for row in all_audit if not row["safe_to_drop_candidate"]]
    print(json.dumps({"candidate_views": len(all_audit), "blocked_by_module_refs": len(blocked)}, indent=2))
    print("RESULT", out_dir / "dependency_audit.json")


if __name__ == "__main__":
    main()
