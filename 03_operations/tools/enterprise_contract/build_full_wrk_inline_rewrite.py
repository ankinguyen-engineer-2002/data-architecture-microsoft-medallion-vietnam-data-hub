#!/usr/bin/env python3
"""Build full _Wrk inline rewrite package from live base view definitions.

Goal:
  <BaseSchema>.<TableName>        physical final table
  <BaseSchema>_Wrk.v_<TableName>  direct source/work view

The generated _Wrk view preserves the final table column contract and inlines
the existing base-schema view SQL into a private CTE named __source_rows.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
from typing import Any


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def token_at(text: str, idx: int, token: str) -> bool:
    end = idx + len(token)
    if text[idx:end].upper() != token.upper():
        return False
    before_ok = idx == 0 or not (text[idx - 1].isalnum() or text[idx - 1] == "_")
    after_ok = end >= len(text) or not (text[end].isalnum() or text[end] == "_")
    return before_ok and after_ok


def iter_code_positions(text: str):
    i = 0
    depth = 0
    state = "code"
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if ch == "-" and nxt == "-":
                state = "line_comment"
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch == "'":
                state = "string"
                i += 1
                continue
            if ch == "[":
                state = "bracket"
                i += 1
                continue
            if ch == "(":
                depth += 1
            elif ch == ")" and depth > 0:
                depth -= 1
            yield i, ch, depth
            i += 1
            continue
        if state == "line_comment":
            if ch in "\r\n":
                state = "code"
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if ch == "'" and nxt == "'":
                i += 2
            elif ch == "'":
                state = "code"
                i += 1
            else:
                i += 1
            continue
        if state == "bracket":
            if ch == "]":
                state = "code"
            i += 1


def first_code_token_pos(text: str) -> int:
    positions = {idx for idx, _, _ in iter_code_positions(text)}
    for idx, ch in enumerate(text):
        if idx in positions and not ch.isspace():
            return idx
    return 0


def find_top_level_select_after_with(body: str) -> int | None:
    start = first_code_token_pos(body)
    if not token_at(body, start, "WITH"):
        return None
    for idx, _, depth in iter_code_positions(body[start + 4 :]):
        actual = start + 4 + idx
        if depth == 0 and token_at(body, actual, "SELECT"):
            return actual
    return None


def extract_view_body(definition: str, source_schema: str, view_name: str) -> str:
    pattern = re.compile(
        r"CREATE\s+(?:OR\s+ALTER\s+)?VIEW\s+"
        + r"(?:"
        + re.escape(source_schema)
        + r"|\["
        + re.escape(source_schema)
        + r"\])"
        + r"\s*\.\s*"
        + r"(?:"
        + re.escape(view_name)
        + r"|\["
        + re.escape(view_name)
        + r"\])"
        + r"\s+AS\b",
        flags=re.IGNORECASE,
    )
    match = pattern.search(definition)
    if not match:
        raise ValueError(f"Could not locate CREATE VIEW header for {source_schema}.{view_name}")
    return definition[match.end() :].strip().rstrip(";")


def find_module(modules: list[dict[str, Any]], schema_name: str, object_name: str) -> dict[str, Any] | None:
    for module in modules:
        if module["schema_name"] == schema_name and module["object_name"] == object_name:
            return module
    return None


def columns_for(scan_db: dict[str, Any], schema: str, table: str) -> list[str]:
    cols = [
        obj
        for obj in scan_db["columns"]
        if obj["schema_name"] == schema and obj["object_name"] == table
    ]
    return [c["column_name"] for c in sorted(cols, key=lambda c: c["column_id"])]


def build_select_from_columns(columns: list[str]) -> str:
    lines = ["SELECT"]
    for i, col in enumerate(columns):
        comma = "," if i < len(columns) - 1 else ""
        if col.lower() == "loaddt":
            expr = f"    {quote_name(col)} = CAST(SYSUTCDATETIME() AS datetime2(6)){comma}"
        else:
            expr = f"    {quote_name(col)} = src.{quote_name(col)}{comma}"
        lines.append(expr)
    lines.append("FROM __source_rows AS src;")
    return "\n".join(lines)


def build_inline_body(base_body: str, output_columns: list[str]) -> str:
    final_select = find_top_level_select_after_with(base_body)
    select_from_source = build_select_from_columns(output_columns)
    if final_select is not None:
        prefix = base_body[:final_select].rstrip()
        source_select = base_body[final_select:].strip().rstrip(";")
        return (
            f"{prefix},\n"
            f"__source_rows AS (\n{source_select}\n)\n"
            f"{select_from_source}"
        )
    source_select = base_body.strip().rstrip(";")
    return (
        "WITH __source_rows AS (\n"
        f"{source_select}\n"
        ")\n"
        f"{select_from_source}"
    )


def canonicalize_base_view_refs(sql: str, view_to_table: dict[tuple[str, str], str]) -> str:
    rewritten = sql
    for (schema, view_name), table_name in sorted(view_to_table.items(), key=lambda x: len(x[0][1]), reverse=True):
        patterns = [
            (
                re.compile(rf"\[{re.escape(schema)}\]\s*\.\s*\[{re.escape(view_name)}\]", re.IGNORECASE),
                f"{quote_name(schema)}.{quote_name(table_name)}",
            ),
            (
                re.compile(rf"\[{re.escape(schema)}\]\s*\.\s*{re.escape(view_name)}\b", re.IGNORECASE),
                f"{quote_name(schema)}.{quote_name(table_name)}",
            ),
            (
                re.compile(rf"\b{re.escape(schema)}\s*\.\s*\[{re.escape(view_name)}\]", re.IGNORECASE),
                f"{quote_name(schema)}.{quote_name(table_name)}",
            ),
            (
                re.compile(rf"\b{re.escape(schema)}\s*\.\s*{re.escape(view_name)}\b", re.IGNORECASE),
                f"{quote_name(schema)}.{quote_name(table_name)}",
            ),
        ]
        for pattern, replacement in patterns:
            rewritten = pattern.sub(replacement, rewritten)
    return rewritten


def build(scan: dict[str, Any], out_dir: pathlib.Path) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    summary: dict[str, Any] = {"databases": {}}
    for db_key in ["processing", "gold"]:
        db = scan["databases"][db_key]
        view_to_table: dict[tuple[str, str], str] = {}
        for pair in db["schema_pairs"]:
            for view_name in pair["duplicate_base_views"]:
                if view_name.startswith("v_"):
                    view_to_table[(pair["base_schema"], view_name)] = view_name[2:]
        alter_lines = [
            f"-- Full _Wrk inline rewrite for {db['database']}",
            "-- Generated from live base-schema view definitions plus final table column contracts.",
            "-- Execute before dropping legacy base-schema v_* views.",
            "",
        ]
        rollback_lines = [
            f"-- Rollback _Wrk definitions for {db['database']}",
            "-- Execute against the database named above.",
            "",
        ]
        built: list[dict[str, Any]] = []
        errors: list[dict[str, str]] = []
        modules = db["modules"]
        for pair in db["schema_pairs"]:
            base_schema = pair["base_schema"]
            wrk_schema = pair["wrk_schema"]
            for view_name in pair["duplicate_base_views"]:
                table_name = view_name[2:] if view_name.startswith("v_") else view_name
                final_cols = columns_for(db, base_schema, table_name)
                if not final_cols:
                    errors.append({"object": f"{base_schema}.{view_name}", "error": f"missing final table columns for {table_name}"})
                    continue
                base_module = find_module(modules, base_schema, view_name)
                wrk_module = find_module(modules, wrk_schema, view_name)
                if not base_module or not base_module.get("definition"):
                    errors.append({"object": f"{base_schema}.{view_name}", "error": "missing base definition"})
                    continue
                if not wrk_module or not wrk_module.get("definition"):
                    errors.append({"object": f"{wrk_schema}.{view_name}", "error": "missing wrk definition"})
                    continue
                try:
                    base_body = extract_view_body(base_module["definition"], base_schema, view_name)
                    base_body = canonicalize_base_view_refs(base_body, view_to_table)
                    inline_body = build_inline_body(base_body, final_cols)
                except Exception as exc:  # noqa: BLE001
                    errors.append({"object": f"{wrk_schema}.{view_name}", "error": str(exc)})
                    continue
                alter_lines.append(f"-- {db['database']}.{wrk_schema}.{view_name}")
                alter_lines.append(f"CREATE OR ALTER VIEW {quote_name(wrk_schema)}.{quote_name(view_name)} AS")
                alter_lines.append(inline_body.rstrip())
                alter_lines.append("GO")
                alter_lines.append("")
                rollback_lines.append(f"-- {db['database']}.{wrk_schema}.{view_name}")
                rollback_lines.append(wrk_module["definition"].rstrip())
                rollback_lines.append("GO")
                rollback_lines.append("")
                built.append(
                    {
                        "database": db["database"],
                        "base_schema": base_schema,
                        "wrk_schema": wrk_schema,
                        "view": view_name,
                        "target_table": table_name,
                        "final_column_count": len(final_cols),
                    }
                )
        (out_dir / f"candidate_alter_wrk_views_{db_key}_full_inline.sql").write_text(
            "\n".join(alter_lines).rstrip() + "\n", encoding="utf-8"
        )
        (out_dir / f"rollback_wrk_views_{db_key}_full_inline.sql").write_text(
            "\n".join(rollback_lines).rstrip() + "\n", encoding="utf-8"
        )
        summary["databases"][db_key] = {
            "database": db["database"],
            "candidate_rewrite_count": len(built),
            "build_errors": errors,
            "objects": built,
        }
    (out_dir / "full_wrk_inline_rewrite_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()
    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    print(json.dumps(build(scan, pathlib.Path(args.out_dir)), indent=2))


if __name__ == "__main__":
    main()
