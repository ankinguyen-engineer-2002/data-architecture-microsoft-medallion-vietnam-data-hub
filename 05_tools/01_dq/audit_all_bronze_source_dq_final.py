#!/usr/bin/env python3
"""Final read-only DQ scan for all active Bronze Enterprise_Lakehouse sources.

This scanner is intentionally latest-partition oriented so every active source
can be audited without letting very large historical tables block the batch.
It records exact grains and marks unsupported/heavy checks explicitly.
"""

from __future__ import annotations

import csv
import datetime as dt
import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "05_tools" / "01_dq"))

import audit_bronze_source_dq as base  # noqa: E402


OUT_DIR = ROOT / "01_docs/runbook/artifacts/20260623_bronze_source_dq_all_final"


def serialize(value: Any) -> Any:
    return base.stringify_nested(value)


def query(conn, sql: str, *, timeout_seconds: int = 180) -> dict[str, Any]:
    result = base.run_timed(conn, sql, timeout_seconds=timeout_seconds)
    return {
        "status": result.status,
        "seconds": result.seconds,
        "error": result.error,
        "rows": serialize(result.value),
    }


def sql_ident(name: str) -> str:
    return f"[{name}]"


def first_row(result: dict[str, Any]) -> dict[str, Any]:
    rows = result.get("rows") or result.get("value") or []
    return rows[0] if rows else {}


def latest_null_blank_query(ref: base.Ref, key_cols: list[str], columns: list[dict[str, Any]], freshness_col: str) -> str:
    col_types = {str(c["column_name"]): str(c["data_type"]).lower() for c in columns}
    clauses = []
    for col in key_cols:
        if base.is_text_type(col_types.get(col, "")):
            clauses.append(f"([{col}] IS NULL OR LTRIM(RTRIM([{col}])) = '')")
        else:
            clauses.append(f"[{col}] IS NULL")
    if not clauses:
        return ""
    return f"""
        WITH latest AS (
            SELECT MAX([{freshness_col}]) AS max_value
            FROM {ref.sql}
        )
        SELECT COUNT_BIG(*) AS latest_partition_null_blank_key_rows
        FROM {ref.sql} AS src
        CROSS JOIN latest
        WHERE src.[{freshness_col}] = latest.max_value
          AND ({' OR '.join(clauses)});
    """


def full_row_duplicate_query(ref: base.Ref, columns: list[dict[str, Any]], freshness_col: str | None) -> str:
    col_names = [str(c["column_name"]) for c in columns]
    if not col_names:
        return ""
    cols_sql = ", ".join(f"[{c}]" for c in col_names)
    if freshness_col:
        return f"""
            WITH latest AS (
                SELECT MAX([{freshness_col}]) AS max_value
                FROM {ref.sql}
            ),
            d AS (
                SELECT {cols_sql}, COUNT_BIG(*) AS row_count
                FROM {ref.sql} AS src
                CROSS JOIN latest
                WHERE src.[{freshness_col}] = latest.max_value
                GROUP BY {cols_sql}
                HAVING COUNT_BIG(*) > 1
            )
            SELECT
                COUNT_BIG(*) AS latest_full_row_duplicate_groups,
                SUM(row_count - 1) AS latest_full_row_duplicate_extra_rows,
                MAX(row_count) AS latest_full_row_max_rows_per_full_row
            FROM d;
        """
    return f"""
        WITH d AS (
            SELECT {cols_sql}, COUNT_BIG(*) AS row_count
            FROM {ref.sql}
            GROUP BY {cols_sql}
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            COUNT_BIG(*) AS full_row_duplicate_groups,
            SUM(row_count - 1) AS full_row_duplicate_extra_rows,
            MAX(row_count) AS max_rows_per_full_row
        FROM d;
    """


def table_status(item: dict[str, Any]) -> str:
    if not item.get("exists"):
        return "MISSING"
    if item.get("table_error"):
        return "PARTIAL"

    latest_dup_extra = first_row(item.get("latest_partition_duplicate") or {}).get("latest_partition_duplicate_extra_rows")
    full_row_extra = (
        first_row(item.get("full_row_duplicate") or {}).get("latest_full_row_duplicate_extra_rows")
        or first_row(item.get("full_row_duplicate") or {}).get("full_row_duplicate_extra_rows")
    )
    latest_nulls = first_row(item.get("latest_partition_null_blank") or {}).get("latest_partition_null_blank_key_rows")
    history_extra = first_row(item.get("all_history_grain_duplicate") or {}).get("duplicate_extra_rows")

    latest_dup_extra = latest_dup_extra or 0
    full_row_extra = full_row_extra or 0
    latest_nulls = latest_nulls or 0
    history_extra = history_extra or 0

    if item["ref"].endswith("Inventory_Enh_History.ItemBalance") and latest_dup_extra == 0 and latest_nulls == 0 and history_extra:
        return "REVIEW_HISTORY_DUP_LATEST_CLEAN"
    if latest_dup_extra or full_row_extra or latest_nulls:
        return "REVIEW"
    if (item.get("latest_partition_duplicate") or {}).get("status") == "ERROR":
        return "PARTIAL"
    if (item.get("latest_partition_null_blank") or {}).get("status") == "ERROR":
        return "PARTIAL"
    if (item.get("full_row_duplicate") or {}).get("status") == "ERROR":
        return "PARTIAL"
    return "PASS"


def audit_one(ref: base.Ref, projects: list[str]) -> dict[str, Any]:
    item: dict[str, Any] = {
        "ref": ref.full,
        "projects": projects,
        "exists": False,
    }
    try:
        with base.connect() as conn:
            item["exists"] = base.table_exists(conn, ref)
            if not item["exists"]:
                item["status"] = "MISSING"
                return item

            columns = base.fetch_columns(conn, ref)
            item["columns"] = columns
            item["column_count"] = len(columns)
            item["row_count_metadata"] = base.metadata_row_count(conn, ref)

            date_cols = base.pick_date_candidates(ref, columns)
            item["freshness_columns"] = date_cols
            item["freshness"] = base.max_dates(conn, ref, date_cols)

            key_cols = base.known_key_columns(ref, columns)
            item["key_columns"] = key_cols

            freshness_col = date_cols[0] if date_cols else None
            if freshness_col and key_cols:
                item["latest_partition_null_blank"] = query(
                    conn,
                    latest_null_blank_query(ref, key_cols, columns, freshness_col),
                    timeout_seconds=180,
                )
                item["latest_partition_duplicate"] = base.check_to_dict(
                    base.latest_partition_duplicate_check(conn, ref, key_cols, freshness_col, timeout_seconds=240)
                )
            else:
                item["latest_partition_null_blank"] = {
                    "status": "NOT_APPLICABLE",
                    "error": "No freshness column or no key columns",
                    "rows": [],
                }
                item["latest_partition_duplicate"] = {
                    "status": "NOT_APPLICABLE",
                    "error": "No freshness column or no key columns",
                    "rows": [],
                }

            full_row_sql = full_row_duplicate_query(ref, columns, freshness_col)
            if full_row_sql:
                item["full_row_duplicate"] = query(conn, full_row_sql, timeout_seconds=300)
            else:
                item["full_row_duplicate"] = {
                    "status": "NOT_APPLICABLE",
                    "error": "No columns",
                    "rows": [],
                }

            if ref.short == "Inventory_Enh_History.ItemBalance":
                item["all_history_grain_duplicate"] = base.check_to_dict(
                    base.duplicate_check(conn, ref, key_cols, timeout_seconds=240)
                )
            else:
                item["all_history_grain_duplicate"] = {
                    "status": "SKIPPED",
                    "error": "Final all-source pass uses latest-partition duplicate scan; full-history duplicate scan is not run for every large source table.",
                    "rows": [],
                }
    except Exception as exc:  # noqa: BLE001
        item["table_error"] = str(exc)

    item["status"] = table_status(item)
    return item


def write_report(payload: dict[str, Any], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "all_source_dq_results.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    fields = [
        "status",
        "ref",
        "projects",
        "freshness",
        "key_columns",
        "latest_null_blank_key_rows",
        "latest_duplicate_groups",
        "latest_duplicate_extra_rows",
        "full_row_duplicate_groups",
        "full_row_duplicate_extra_rows",
        "history_duplicate_extra_rows",
        "notes",
    ]
    with (out_dir / "all_source_dq_results.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for item in payload["tables"]:
            dup = first_row(item.get("latest_partition_duplicate") or {})
            full_dup = first_row(item.get("full_row_duplicate") or {})
            nulls = first_row(item.get("latest_partition_null_blank") or {})
            hist = first_row(item.get("all_history_grain_duplicate") or {})
            writer.writerow(
                {
                    "status": item.get("status"),
                    "ref": item.get("ref"),
                    "projects": ";".join(item.get("projects") or []),
                    "freshness": json.dumps(item.get("freshness"), ensure_ascii=False),
                    "key_columns": ";".join(item.get("key_columns") or []),
                    "latest_null_blank_key_rows": nulls.get("latest_partition_null_blank_key_rows"),
                    "latest_duplicate_groups": dup.get("latest_partition_duplicate_groups"),
                    "latest_duplicate_extra_rows": dup.get("latest_partition_duplicate_extra_rows"),
                    "full_row_duplicate_groups": full_dup.get("latest_full_row_duplicate_groups") or full_dup.get("full_row_duplicate_groups"),
                    "full_row_duplicate_extra_rows": full_dup.get("latest_full_row_duplicate_extra_rows") or full_dup.get("full_row_duplicate_extra_rows"),
                    "history_duplicate_extra_rows": hist.get("duplicate_extra_rows"),
                    "notes": item.get("table_error") or "",
                }
            )

    counts: dict[str, int] = {}
    for item in payload["tables"]:
        counts[item.get("status", "UNKNOWN")] = counts.get(item.get("status", "UNKNOWN"), 0) + 1

    lines = [
        "# Bronze Source DQ All-Source Final Report",
        "",
        f"- Generated at ICT: `{payload['metadata']['generated_at_ict']}`",
        f"- Tables audited: `{len(payload['tables'])}`",
        f"- Source list: `{payload['metadata']['summary_path']}` + requested extra `SupplyPlanDetailSnapshotWeekly`",
        "",
        "## Processing Summary",
        "",
        "| Status | Count | Meaning |",
        "|---|---:|---|",
    ]
    meanings = {
        "PASS": "Latest-partition DQ check has no duplicate/null key signal at checked grain.",
        "REVIEW": "Latest-partition duplicate/null key signal exists; DE/business contract needed.",
        "REVIEW_HISTORY_DUP_LATEST_CLEAN": "Latest partition clean but historical duplicate exists.",
        "PARTIAL": "Table exists but one or more checks errored.",
        "MISSING": "Table not found on Enterprise_Lakehouse.",
    }
    for status in ["PASS", "REVIEW", "REVIEW_HISTORY_DUP_LATEST_CLEAN", "PARTIAL", "MISSING"]:
        lines.append(f"| `{status}` | {counts.get(status, 0)} | {meanings[status]} |")

    lines.extend(
        [
            "",
            "## Detail Table",
            "",
            "| # | Status | Table | Projects | Freshness / max dates | Grain checked | Null/blank key rows | Grain dup groups | Grain dup extra rows | Full-row dup groups | Full-row dup extra rows | Historical note |",
            "|---:|---|---|---|---|---|---:|---:|---:|---:|---:|---|",
        ]
    )
    for idx, item in enumerate(payload["tables"], start=1):
        dup = first_row(item.get("latest_partition_duplicate") or {})
        full_dup = first_row(item.get("full_row_duplicate") or {})
        nulls = first_row(item.get("latest_partition_null_blank") or {})
        hist = first_row(item.get("all_history_grain_duplicate") or {})
        hist_note = ""
        if hist.get("duplicate_extra_rows"):
            hist_note = (
                f"all-history duplicate groups={hist.get('duplicate_groups')}, "
                f"extra={hist.get('duplicate_extra_rows')}"
            )
        elif (item.get("all_history_grain_duplicate") or {}).get("status") == "SKIPPED":
            hist_note = "full-history duplicate scan skipped in all-source pass"
        lines.append(
            "| "
            + " | ".join(
                [
                    str(idx),
                    f"`{item.get('status')}`",
                    f"`{item.get('ref')}`",
                    ", ".join(item.get("projects") or []),
                    f"`{item.get('freshness')}`".replace("|", "\\|"),
                    f"`{', '.join(item.get('key_columns') or [])}`",
                    str(nulls.get("latest_partition_null_blank_key_rows") or 0),
                    str(dup.get("latest_partition_duplicate_groups") or 0),
                    str(dup.get("latest_partition_duplicate_extra_rows") or 0),
                    str(full_dup.get("latest_full_row_duplicate_groups") or full_dup.get("full_row_duplicate_groups") or 0),
                    str(full_dup.get("latest_full_row_duplicate_extra_rows") or full_dup.get("full_row_duplicate_extra_rows") or 0),
                    hist_note,
                ]
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- This report audits every active Bronze `Enterprise_Lakehouse` source referenced by the two marts plus `SupplyPlanDetailSnapshotWeekly`.",
            "- The duplicate checks are applied to every table as latest-partition grain duplicate and latest-partition full-row duplicate when a freshness/date column exists; tables without a freshness/date column use full-table full-row duplicate and mark grain/key checks as `NOT_APPLICABLE` when no key is selected.",
            "- Full-history grain duplicate scan is not run for every large table in this all-source pass; `ItemBalance` is included because it is a known historical issue and is bounded enough for this check.",
            "- A `REVIEW` status does not automatically mean downstream ETL is broken; it means source-level grain/null/freshness contract needs DE/business confirmation before declaring DQ clean.",
        ]
    )
    (out_dir / "bronze_source_dq_all_final_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the final read-only DQ scan for active Bronze Enterprise_Lakehouse sources."
    )
    parser.add_argument(
        "--out-dir",
        default=str(OUT_DIR),
        help="Output directory for JSON/CSV/Markdown DQ reports.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    refs = base.load_source_refs(base.SUMMARY_PATH)
    ordered = sorted(refs)
    metadata = {
        "generated_at_ict": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "summary_path": str(base.SUMMARY_PATH),
        "server": base.SERVER,
        "database": base.DATABASE,
    }
    payload = {"metadata": metadata, "tables": []}
    for idx, ref in enumerate(ordered, start=1):
        print(f"[{idx}/{len(ordered)}] {ref.full}", flush=True)
        item = audit_one(ref, sorted(refs[ref]))
        payload["tables"].append(item)
        write_report(payload, out_dir)
    write_report(payload, out_dir)
    print(out_dir / "bronze_source_dq_all_final_report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
