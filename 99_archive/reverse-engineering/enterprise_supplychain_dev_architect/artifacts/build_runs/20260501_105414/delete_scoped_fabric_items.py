#!/usr/bin/env python3
"""Delete only the explicitly approved v9 Fabric items from a manifest."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
ALLOWED_TARGETS = {
    ("SC_Control_Tower", "SemanticModel"),
    ("pl_sc_master", "DataPipeline"),
    ("pl_sc_mart", "DataPipeline"),
    ("pl_sc_bronze", "DataPipeline"),
    ("pl_sc_silver", "DataPipeline"),
    ("pl_sc_silver_wave", "DataPipeline"),
    ("pl_sc_gold", "DataPipeline"),
    ("pl_dq_check", "DataPipeline"),
}


def run_az_delete(item: dict) -> dict:
    url = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}/items/{item['id']}"
    cmd = [
        "az",
        "rest",
        "--method",
        "DELETE",
        "--resource",
        "https://api.fabric.microsoft.com",
        "--url",
        url,
        "--output",
        "json",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return {
        "displayName": item["displayName"],
        "type": item["type"],
        "id": item["id"],
        "workspaceId": item["workspaceId"],
        "returncode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    out_path = Path(args.out)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    targets = manifest["targets"]

    actual = {(target["displayName"], target["type"]) for target in targets}
    if actual != ALLOWED_TARGETS:
        raise SystemExit(
            "Manifest target set does not match the approved allow-list. "
            f"actual={sorted(actual)}"
        )

    bad_workspace = [target for target in targets if target["workspaceId"] != WORKSPACE_ID]
    if bad_workspace:
        raise SystemExit(f"Unexpected workspace in manifest: {bad_workspace}")

    results = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "workspace_id": WORKSPACE_ID,
        "approved_target_count": len(targets),
        "results": [],
    }

    for target in targets:
        results["results"].append(run_az_delete(target))

    results["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    out_path.write_text(json.dumps(results, indent=2, sort_keys=True), encoding="utf-8")

    failed = [item for item in results["results"] if item["returncode"] != 0]
    print(
        json.dumps(
            {
                "deleted_attempts": len(results["results"]),
                "failed_count": len(failed),
                "failed": [
                    {"displayName": item["displayName"], "type": item["type"], "id": item["id"]}
                    for item in failed
                ],
            },
            sort_keys=True,
        )
    )
    return 0 if not failed else 2


if __name__ == "__main__":
    raise SystemExit(main())
