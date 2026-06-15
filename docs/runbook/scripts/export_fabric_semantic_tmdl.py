#!/usr/bin/env python3
"""
Export a Fabric Semantic Model definition in TMDL format and decode parts to files.

Why this exists:
  - `az rest` does not reliably surface async (202) operation headers needed to poll.
  - This script implements the LRO polling pattern used by Fabric getDefinition.

Usage:
  python3 docs/runbook/scripts/export_fabric_semantic_tmdl.py \
    --workspace-id <workspaceGuid> \
    --semantic-model-id <modelGuid> \
    --out-dir docs/runbook/artifacts/<folder>

Auth:
  - Uses `az account get-access-token --resource https://api.fabric.microsoft.com`.
  - If you need an isolated Azure CLI config dir, set AZURE_CONFIG_DIR.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen


def az_token(resource: str) -> str:
    cmd = [
        "az",
        "account",
        "get-access-token",
        "--resource",
        resource,
        "--query",
        "accessToken",
        "-o",
        "tsv",
    ]
    return subprocess.check_output(cmd, text=True).strip()


def fabric_request(method: str, url: str, token: str, body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
    req = Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urlopen(req) as resp:
        return resp.status, dict(resp.headers), resp.read()


def get_definition(workspace_id: str, model_id: str, token: str) -> dict[str, Any]:
    url = (
        f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
        f"/semanticModels/{model_id}/getDefinition?format=TMDL"
    )
    status, headers, payload = fabric_request("POST", url, token, body=b"{}")
    if status == 200:
        return json.loads(payload.decode("utf-8"))
    if status != 202:
        raise RuntimeError(f"Unexpected getDefinition status {status}: {payload[:500]!r}")

    operation_url = headers.get("Location")
    if operation_url and operation_url.startswith("/"):
        operation_url = "https://api.fabric.microsoft.com" + operation_url
    operation_id = headers.get("x-ms-operation-id")
    retry_after = int(headers.get("Retry-After") or "5")
    if not operation_url and operation_id:
        operation_url = f"https://api.fabric.microsoft.com/v1/operations/{operation_id}"
    if not operation_url:
        raise RuntimeError("getDefinition LRO missing Location/x-ms-operation-id")

    for _ in range(240):
        time.sleep(retry_after)
        status, headers, payload = fabric_request("GET", operation_url, token)
        retry_after = int(headers.get("Retry-After") or "5")
        location = headers.get("Location")
        if location:
            operation_url = location if location.startswith("http") else "https://api.fabric.microsoft.com" + location
        if status != 200:
            continue
        text = payload.decode("utf-8", errors="replace").strip()
        if not text:
            continue
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            continue
        if "definition" in parsed:
            return parsed
        op_status = str(parsed.get("status") or "").lower()
        if op_status == "failed":
            raise RuntimeError(f"getDefinition failed: {parsed}")
        if op_status == "succeeded":
            if operation_id:
                result_url = f"https://api.fabric.microsoft.com/v1/operations/{operation_id}/result"
                result_status, _, result_payload = fabric_request("GET", result_url, token)
                if result_status == 200:
                    return json.loads(result_payload.decode("utf-8"))

    raise TimeoutError("Timed out waiting for getDefinition")


def write_decoded_parts(definition: dict[str, Any], out_dir: Path) -> int:
    parts = definition.get("definition", {}).get("parts", []) or []
    count = 0
    for part in parts:
        rel_path = (part.get("path") or "").lstrip("/").strip()
        payload = part.get("payload") or ""
        if not rel_path or not payload:
            continue
        try:
            content = base64.b64decode(payload).decode("utf-8", errors="replace")
        except Exception:
            continue
        file_path = out_dir / rel_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content, encoding="utf-8")
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--semantic-model-id", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    token = az_token("https://api.fabric.microsoft.com")
    definition = get_definition(args.workspace_id, args.semantic_model_id, token)

    raw_path = out_dir / "getDefinition.tmdl.json"
    raw_path.write_text(json.dumps(definition, indent=2, ensure_ascii=False), encoding="utf-8")

    decoded_dir = out_dir / "decoded"
    decoded_dir.mkdir(parents=True, exist_ok=True)
    parts_written = write_decoded_parts(definition, decoded_dir)

    meta_path = out_dir / "export_meta.json"
    meta = {
        "workspace_id": args.workspace_id,
        "semantic_model_id": args.semantic_model_id,
        "parts_written": parts_written,
        "az_config_dir": os.getenv("AZURE_CONFIG_DIR", ""),
        "exported_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

