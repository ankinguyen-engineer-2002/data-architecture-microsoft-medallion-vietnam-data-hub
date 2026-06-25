#!/usr/bin/env python3
"""Dry-run or trigger Fabric refresh manifests.

Default behavior is dry-run. Live execution requires --execute and should only
be used after explicit same-conversation approval from Aric.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


FABRIC_RESOURCE = "https://api.fabric.microsoft.com"


def load_manifest(path: Path) -> dict[str, Any]:
    if path.suffix.lower() != ".json":
        raise SystemExit("Use the JSON manifest for tooling. YAML manifests are human-readable mirrors.")
    return json.loads(path.read_text(encoding="utf-8"))


def az_rest(method: str, url: str, body: dict[str, Any] | None = None) -> subprocess.CompletedProcess[str]:
    cmd = [
        "az",
        "rest",
        "--method",
        method,
        "--url",
        url,
        "--resource",
        FABRIC_RESOURCE,
        "--only-show-errors",
    ]
    if body is not None:
        cmd.extend(["--body", json.dumps(body)])
    cmd.extend(["-o", "json"])
    return subprocess.run(cmd, check=False, text=True, capture_output=True)


def build_execute_request(manifest: dict[str, Any]) -> tuple[str, dict[str, Any] | None]:
    workspace_id = manifest["workspace_id"]
    pipeline = manifest["pipeline"]
    pipeline_id = pipeline["id"]

    url = f"{FABRIC_RESOURCE}/v1/workspaces/{workspace_id}/dataPipelines/{pipeline_id}/jobs/execute/instances"
    params = pipeline.get("parameters")
    body = {"executionData": {"parameters": params}} if params else None
    return url, body


def build_list_jobs_request(manifest: dict[str, Any]) -> str:
    workspace_id = manifest["workspace_id"]
    pipeline_id = manifest["pipeline"]["id"]
    return f"{FABRIC_RESOURCE}/v1/workspaces/{workspace_id}/dataPipelines/{pipeline_id}/jobs/execute/instances"


def print_manifest(manifest: dict[str, Any]) -> None:
    pipeline = manifest["pipeline"]
    print(f"manifest={manifest['name']}")
    print(f"workspace_id={manifest['workspace_id']}")
    print(f"pipeline={pipeline['name']} ({pipeline['id']})")
    if pipeline.get("parameters"):
        print(f"parameters={json.dumps(pipeline['parameters'], sort_keys=True)}")
        if pipeline.get("parameters_need_verify"):
            print("warning=parameterized DataPipeline REST execution is marked Need-verify for this mart")
    wrapper_procedures = manifest.get("wrapper_procedures")
    if wrapper_procedures:
        print("wrapper_procedures:")
        for wrapper in sorted(wrapper_procedures, key=lambda item: item.get("step", 0)):
            step = wrapper.get("step", "")
            database = wrapper.get("database", "")
            schema = wrapper.get("schema", "")
            procedure = wrapper.get("procedure", "")
            purpose = wrapper.get("purpose", "")
            print(
                f"  {step:>4} database={database} exec=EXEC [{schema}].[{procedure}];"
                + (f"  {purpose}" if purpose else "")
            )
    print("sequence:")
    for step in manifest.get("sequence", []):
        label = step.get("project") or step.get("object") or step.get("purpose")
        wave = step.get("wave", "")
        load_type = step.get("load_type", "")
        print(f"  {step['step']:>4} wave={wave!s:<10} load_type={load_type!s:<24} {label}")
    if manifest.get("post_run_checks"):
        print("post_run_checks:")
        for check in manifest["post_run_checks"]:
            print(f"  - {check}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--execute", action="store_true", help="Trigger the Fabric pipeline.")
    parser.add_argument("--list-jobs", action="store_true", help="List recent jobs for the manifest pipeline.")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    print_manifest(manifest)

    if args.list_jobs:
        url = build_list_jobs_request(manifest)
        print(f"GET {url}")
        result = az_rest("get", url)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode

    url, body = build_execute_request(manifest)
    if not args.execute:
        print("dry_run=true")
        print(f"POST {url}")
        if body:
            print(f"body={json.dumps(body, sort_keys=True)}")
        return 0

    print("dry_run=false")
    print(f"POST {url}")
    if body:
        print(f"body={json.dumps(body, sort_keys=True)}")
    result = az_rest("post", url, body)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
