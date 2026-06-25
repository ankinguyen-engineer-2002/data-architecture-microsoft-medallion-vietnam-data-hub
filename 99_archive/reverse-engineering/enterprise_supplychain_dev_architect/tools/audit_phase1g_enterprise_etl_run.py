#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from Enterprise_SupplyChain_Dev_architect.tools.repro_usp_incremental_table_load import (  # noqa: E402
    connect,
    rows_as_dicts,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_run(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def object_ref(name: str) -> tuple[str, str, str]:
    database, schema, table = name.split(".", 2)
    return database, schema, table


def audit_description(statement: str, database: str, schema: str, table: str) -> str:
    if "usp_RefreshCuratedTableFromView" in statement:
        return f"usp_RefreshCuratedTableFromView: {database}.{schema}.{table}"
    return f"{database}.{schema}.{table}"


def fetch_rows(database: str, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    conn = connect(database)
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
        if cur.description:
            return rows_as_dicts(cur)
        return []
    finally:
        cur.close()
        conn.close()


def row_counts_by_database(refs: list[tuple[str, str, str]]) -> dict[str, Any]:
    grouped: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for database, schema, table in refs:
        grouped[database].append((schema, table))

    result: dict[str, Any] = {}
    for database, tables in grouped.items():
        filters = " OR ".join("(s.name = ? AND t.name = ?)" for _ in tables)
        params: list[Any] = []
        for schema, table in tables:
            params.extend([schema, table])
        sql = f"""
        SELECT
            s.name AS schema_name,
            t.name AS table_name,
            SUM(p.rows) AS row_count
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0,1)
        WHERE {filters}
        GROUP BY s.name, t.name
        ORDER BY s.name, t.name;
        """
        result[database] = fetch_rows(database, sql, tuple(params))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--initial-run", type=Path, required=True)
    parser.add_argument("--resume-run", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-md", type=Path, required=True)
    args = parser.parse_args()

    runs = [load_run(args.initial_run), load_run(args.resume_run)]
    results = [entry for run in runs for entry in run.get("results", [])]
    success_results = [entry for entry in results if entry.get("ok")]
    failed_results = [entry for entry in results if not entry.get("ok")]

    executable_refs = [object_ref(entry["object"]) for entry in success_results]
    audit_checks = []
    for entry in success_results:
        database, schema, table = object_ref(entry["object"])
        desc = audit_description(entry["statement"], database, schema, table)
        rows = fetch_rows(
            "ETL_Framework",
            """
            SELECT TOP (4) Description, DateTime, [User], Command
            FROM DW_Developer.AuditLog
            WHERE Description = ?
            ORDER BY DateTime DESC;
            """,
            (desc,),
        )
        commands = [str(row["Command"]) for row in rows]
        audit_checks.append(
            {
                "object": entry["object"],
                "audit_description": desc,
                "has_process_start": "Process Start" in commands,
                "has_process_complete": "Process Complete" in commands,
                "latest_rows": rows,
            }
        )

    td_filters = " OR ".join(
        "(DatabaseName = ? AND SchemaName = ? AND TableName = ?)"
        for _ in executable_refs
    )
    td_params: list[Any] = []
    for database, schema, table in executable_refs:
        td_params.extend([database, schema, table])
    table_dictionary = fetch_rows(
        "ETL_Framework",
        f"""
        SELECT DatabaseName, SchemaName, TableName, UpdateMethod, UpdateQuery, Modified, [RowCount], DateKey, DateRangeDays
        FROM DW_Developer.TableDictionary
        WHERE {td_filters}
        ORDER BY DatabaseName, SchemaName, TableName;
        """,
        tuple(td_params),
    )

    row_counts = row_counts_by_database(executable_refs)

    output = {
        "generated_at_utc": utc_now(),
        "initial_run": str(args.initial_run),
        "resume_run": str(args.resume_run),
        "total_result_entries": len(results),
        "successful_entries": len(success_results),
        "failed_entries": len(failed_results),
        "failed_results": failed_results,
        "audit_missing_complete": [
            row for row in audit_checks if not row["has_process_complete"]
        ],
        "audit_missing_start": [row for row in audit_checks if not row["has_process_start"]],
        "audit_checks": audit_checks,
        "table_dictionary": table_dictionary,
        "row_counts": row_counts,
    }

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(output, indent=2, default=str) + "\n", encoding="utf-8")

    md_lines = [
        "# Phase 1G Enterprise ETL Run Audit",
        "",
        f"Generated UTC: `{output['generated_at_utc']}`",
        "",
        f"- Successful executable entries: `{len(success_results)}`",
        f"- Failed entries retained from stop-on-failure run: `{len(failed_results)}`",
        f"- Audit entries missing `Process Complete`: `{len(output['audit_missing_complete'])}`",
        f"- Audit entries missing `Process Start`: `{len(output['audit_missing_start'])}`",
        "",
        "## Failed Entries",
        "",
    ]
    if failed_results:
        for entry in failed_results:
            md_lines.append(
                f"- `{entry['object']}` failed before fix with: `{entry.get('error')}`"
            )
    else:
        md_lines.append("- None")
    md_lines.extend(["", "## Row Counts", ""])
    for database, rows in row_counts.items():
        md_lines.append(f"### {database}")
        md_lines.append("")
        md_lines.append("| Schema | Table | Row count |")
        md_lines.append("|---|---:|---:|")
        for row in rows:
            md_lines.append(
                f"| `{row['schema_name']}` | `{row['table_name']}` | `{row['row_count']}` |"
            )
        md_lines.append("")

    args.output_md.write_text("\n".join(md_lines).rstrip() + "\n", encoding="utf-8")
    print(json.dumps({k: output[k] for k in ["successful_entries", "failed_entries", "audit_missing_complete", "audit_missing_start"]}, default=str))
    return 0 if not output["audit_missing_complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
