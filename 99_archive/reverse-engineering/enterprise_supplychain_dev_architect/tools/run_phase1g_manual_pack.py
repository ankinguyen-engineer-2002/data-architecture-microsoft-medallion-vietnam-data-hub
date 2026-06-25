#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from Enterprise_SupplyChain_Dev_architect.tools.repro_usp_incremental_table_load import (
    ETL_DB,
    connect,
)


GO_RE = re.compile(r"^\s*GO\s*$", re.IGNORECASE)
OBJECT_RE = re.compile(r"^\s*--\s*(\d+)\.\s+(.+?)\s*$")
REGISTER_ONLY_RE = re.compile(r"^\s*--\s*REGISTER_ONLY\s+(\d+)\.\s+(.+?)\s*$")
APPROVAL_RE = re.compile(r"^\s*--\s*APPROVAL REQUIRED\s+(\d+)\.\s+(.+?)\s*$")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_pack(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    commands: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    current_object: str | None = None
    current_index: int | None = None
    buffer: list[str] = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        register_match = REGISTER_ONLY_RE.match(raw_line)
        if register_match:
            skipped.append(
                {
                    "index": int(register_match.group(1)),
                    "object": register_match.group(2),
                    "reason": "REGISTER_ONLY",
                }
            )
            continue

        approval_match = APPROVAL_RE.match(raw_line)
        if approval_match:
            skipped.append(
                {
                    "index": int(approval_match.group(1)),
                    "object": approval_match.group(2),
                    "reason": "APPROVAL_REQUIRED_EXTERNAL_TO_PACK",
                }
            )
            continue

        object_match = OBJECT_RE.match(raw_line)
        if object_match:
            current_index = int(object_match.group(1))
            current_object = object_match.group(2)
            continue

        if GO_RE.match(raw_line):
            statement = "\n".join(line for line in buffer if line.strip()).strip()
            if statement:
                commands.append(
                    {
                        "index": current_index,
                        "object": current_object,
                        "statement": statement,
                    }
                )
            buffer = []
            continue

        if raw_line.strip() and not raw_line.lstrip().startswith("--"):
            buffer.append(raw_line)

    statement = "\n".join(line for line in buffer if line.strip()).strip()
    if statement:
        commands.append(
            {"index": current_index, "object": current_object, "statement": statement}
        )

    return commands, skipped


def drain(cursor: Any) -> None:
    while True:
        try:
            cursor.fetchall()
        except Exception:
            pass
        if not cursor.nextset():
            break


def run_pack(path: Path, start_index: int | None = None) -> dict[str, Any]:
    commands, skipped = parse_pack(path)
    if start_index is not None:
        commands = [
            command
            for command in commands
            if command["index"] is not None and command["index"] >= start_index
        ]
    result: dict[str, Any] = {
        "pack_path": str(path),
        "start_index": start_index,
        "started_at_utc": utc_now(),
        "ended_at_utc": None,
        "command_count": len(commands),
        "skipped": skipped,
        "results": [],
        "ok": False,
        "failed_at": None,
    }

    conn = connect(ETL_DB)
    cursor = conn.cursor()
    try:
        for idx, command in enumerate(commands, start=1):
            started = time.monotonic()
            entry = {
                "sequence": idx,
                "index": command["index"],
                "object": command["object"],
                "statement": command["statement"],
                "started_at_utc": utc_now(),
                "ended_at_utc": None,
                "duration_seconds": None,
                "ok": False,
                "error": None,
            }
            print(
                f"[{idx}/{len(commands)}] {command['object']} :: {command['statement']}",
                flush=True,
            )
            try:
                cursor.execute(command["statement"])
                drain(cursor)
                entry["ok"] = True
                print(f"[{idx}/{len(commands)}] OK {command['object']}", flush=True)
            except Exception as exc:  # noqa: BLE001
                entry["error"] = str(exc)
                result["failed_at"] = {
                    "sequence": idx,
                    "index": command["index"],
                    "object": command["object"],
                }
                print(f"[{idx}/{len(commands)}] FAIL {command['object']}: {exc}", flush=True)
                result["results"].append(entry)
                break
            finally:
                entry["ended_at_utc"] = utc_now()
                entry["duration_seconds"] = round(time.monotonic() - started, 3)

            result["results"].append(entry)
        else:
            result["ok"] = True
    finally:
        cursor.close()
        conn.close()
        result["ended_at_utc"] = utc_now()

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pack", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--start-index",
        type=int,
        help="Resume at the manifest index after a prior stop-on-failure run.",
    )
    args = parser.parse_args()

    result = run_pack(args.pack, start_index=args.start_index)
    payload = json.dumps(result, indent=2, default=str)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    print(payload)
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
