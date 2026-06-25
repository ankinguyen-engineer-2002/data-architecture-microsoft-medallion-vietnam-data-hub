#!/usr/bin/env python3
"""Build approval-gated _Wrk view rewrite packages.

This generator is intentionally conservative:
- It emits executable ALTER VIEW candidates only when the base and _Wrk view
  column contracts are identical.
- LoadDT wrapper cases are listed as manual work because safely inlining CTE
  based SQL while adding LoadDT requires SQL-aware review.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
from typing import Any


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def find_module(modules: list[dict[str, Any]], schema_name: str, object_name: str) -> dict[str, Any] | None:
    for module in modules:
        if module["schema_name"] == schema_name and module["object_name"] == object_name:
            return module
    return None


def rewrite_view_header(definition: str, source_schema: str, target_schema: str, view_name: str) -> str:
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
        + r"\s+AS",
        flags=re.IGNORECASE,
    )
    replacement = f"CREATE OR ALTER VIEW {quote_name(target_schema)}.{quote_name(view_name)} AS"
    rewritten, count = pattern.subn(replacement, definition, count=1)
    if count != 1:
        raise ValueError(f"Could not rewrite header for {source_schema}.{view_name}")
    return rewritten.rstrip() + "\n"


def classify(diff_rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    identical: list[dict[str, Any]] = []
    simple_load_dt: list[dict[str, Any]] = []
    manual: list[dict[str, Any]] = []
    for row in diff_rows:
        missing_in_wrk = row.get("missing_in_wrk") or []
        missing_in_base = row.get("missing_in_base") or []
        datatype_mismatch = row.get("datatype_mismatch") or []
        if not missing_in_wrk and not missing_in_base and not datatype_mismatch:
            identical.append(row)
        elif not missing_in_wrk and missing_in_base == ["LoadDT"] and not datatype_mismatch:
            simple_load_dt.append(row)
        else:
            manual.append(row)
    return identical, simple_load_dt, manual


def build_package(scan: dict[str, Any], diff_rows: list[dict[str, Any]], out_dir: pathlib.Path) -> dict[str, Any]:
    identical, simple_load_dt, manual = classify(diff_rows)
    out_dir.mkdir(parents=True, exist_ok=True)

    packages: dict[str, dict[str, Any]] = {}
    for db_key in ["processing", "gold"]:
        db = scan["databases"][db_key]
        executable_rows = [row for row in identical if row["database"] == db["database"]]
        alter_lines = [
            f"-- Candidate _Wrk rewrite package for {db['database']}",
            "-- Purpose: remove _Wrk dependency on duplicate base-schema views where contracts are identical.",
            "-- Approval-gated: review this exact file before live execution.",
            "",
        ]
        rollback_lines = [
            f"-- Rollback current _Wrk definitions for {db['database']}",
            "-- Execute against the database named above.",
            "",
        ]
        drop_lines = [
            f"-- Candidate base-schema duplicate view cleanup for {db['database']} after _Wrk rewrite succeeds.",
            "-- Approval-gated and only valid after dependency audit shows zero refs for these views.",
            "",
        ]
        build_errors: list[dict[str, str]] = []
        built: list[dict[str, str]] = []

        modules = db["modules"]
        for row in executable_rows:
            base_module = find_module(modules, row["base_schema"], row["view"])
            wrk_module = find_module(modules, row["wrk_schema"], row["view"])
            if not base_module or not base_module.get("definition"):
                build_errors.append({"object": f"{row['base_schema']}.{row['view']}", "error": "missing base definition"})
                continue
            if not wrk_module or not wrk_module.get("definition"):
                build_errors.append({"object": f"{row['wrk_schema']}.{row['view']}", "error": "missing wrk definition"})
                continue
            try:
                rewritten = rewrite_view_header(
                    base_module["definition"],
                    row["base_schema"],
                    row["wrk_schema"],
                    row["view"],
                )
            except Exception as exc:  # noqa: BLE001
                build_errors.append({"object": f"{row['wrk_schema']}.{row['view']}", "error": str(exc)})
                continue

            alter_lines.append(f"-- {db['database']}.{row['wrk_schema']}.{row['view']}")
            alter_lines.append(rewritten)
            alter_lines.append("GO")
            alter_lines.append("")

            rollback_lines.append(f"-- {db['database']}.{row['wrk_schema']}.{row['view']}")
            rollback_lines.append(wrk_module["definition"].rstrip())
            rollback_lines.append("GO")
            rollback_lines.append("")

            drop_lines.append(f"DROP VIEW {quote_name(row['base_schema'])}.{quote_name(row['view'])};")
            drop_lines.append("GO")

            built.append(
                {
                    "database": row["database"],
                    "base_schema": row["base_schema"],
                    "wrk_schema": row["wrk_schema"],
                    "view": row["view"],
                }
            )

        (out_dir / f"candidate_alter_wrk_views_{db_key}_identical_contract.sql").write_text(
            "\n".join(alter_lines).rstrip() + "\n", encoding="utf-8"
        )
        (out_dir / f"rollback_wrk_views_{db_key}_identical_contract.sql").write_text(
            "\n".join(rollback_lines).rstrip() + "\n", encoding="utf-8"
        )
        (out_dir / f"candidate_drop_base_views_{db_key}_after_identical_wrk_rewrite.sql").write_text(
            "\n".join(drop_lines).rstrip() + "\n", encoding="utf-8"
        )
        packages[db_key] = {
            "database": db["database"],
            "candidate_rewrite_count": len(built),
            "build_errors": build_errors,
            "objects": built,
        }

    manual_payload = {
        "simple_load_dt_wrappers_manual_count": len(simple_load_dt),
        "non_simple_manual_count": len(manual),
        "simple_load_dt_wrappers": simple_load_dt,
        "non_simple": manual,
        "rule": (
            "Do not auto-rewrite these with text regex. Preserve the _Wrk output contract, "
            "inline the base source logic with SQL-aware review, and keep LoadDT where present."
        ),
    }
    (out_dir / "manual_rewrite_required_processing_wrk_views.json").write_text(
        json.dumps(manual_payload, indent=2), encoding="utf-8"
    )

    summary = {
        "total_pairs": len(diff_rows),
        "identical_contract_candidates": len(identical),
        "simple_load_dt_manual": len(simple_load_dt),
        "non_simple_manual": len(manual),
        "packages": packages,
    }
    (out_dir / "wrk_view_rewrite_package_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--diff-json", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    diff_rows = json.loads(pathlib.Path(args.diff_json).read_text(encoding="utf-8"))
    summary = build_package(scan, diff_rows, pathlib.Path(args.out_dir))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
