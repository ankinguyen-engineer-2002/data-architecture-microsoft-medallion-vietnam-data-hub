#!/usr/bin/env python3
"""Verify Enterprise `_Wrk` curated contract after scan or cleanup."""

from __future__ import annotations

import argparse
import json
import pathlib
from typing import Any


def failures_for_scan(scan: dict[str, Any], allow_base_views: bool) -> list[dict[str, Any]]:
    failures: list[dict[str, Any]] = []
    for db_key in ["processing", "gold"]:
        db = scan["databases"][db_key]
        for pair in db["schema_pairs"]:
            if not allow_base_views and pair["base_views"]:
                failures.append(
                    {
                        "database": db["database"],
                        "schema": pair["base_schema"],
                        "type": "base_schema_views_remaining",
                        "objects": pair["base_views"],
                    }
                )
            if pair["expected_wrk_views_missing"]:
                failures.append(
                    {
                        "database": db["database"],
                        "schema": pair["wrk_schema"],
                        "type": "expected_wrk_views_missing",
                        "objects": pair["expected_wrk_views_missing"],
                    }
                )
    for row in scan.get("tabledictionary", {}).get("bad_rows", []):
        failures.append(
            {
                "database": "ETL_Framework",
                "schema": "DW_Developer",
                "type": "bad_tabledictionary_row",
                "row": row,
            }
        )
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-json", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument(
        "--allow-base-views",
        action="store_true",
        help="Use before live cleanup; duplicate base views are reported by scanner but not failed.",
    )
    args = parser.parse_args()

    scan = json.loads(pathlib.Path(args.scan_json).read_text(encoding="utf-8"))
    failures = failures_for_scan(scan, allow_base_views=args.allow_base_views)
    result = {
        "pass": len(failures) == 0,
        "allow_base_views": args.allow_base_views,
        "failures": failures,
    }
    pathlib.Path(args.out_json).write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")
    print(json.dumps(result, indent=2, default=str))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
