#!/usr/bin/env python3
"""
Update a Fabric Semantic Model definition using a prebuilt TMDL updateDefinition payload.

This mirrors the proven LRO pattern used by getDefinition, because `az rest` may not
reliably surface headers needed to poll 202 operations.

Endpoints attempted (in order):
  1) /v1/workspaces/{ws}/semanticModels/{id}/updateDefinition
  2) /v1/workspaces/{ws}/items/{id}/updateDefinition   (fallback)

Auth:
  - Uses `az account get-access-token --resource https://api.fabric.microsoft.com`.
  - Pin AZURE_CONFIG_DIR if HOME is not writable.

Usage:
  AZURE_CONFIG_DIR=/private/tmp/azcfg python3 docs/runbook/scripts/update_fabric_semantic_model_definition_tmdl.py \\
    --workspace-id <wsGuid> \\
    --semantic-model-id <modelGuid> \\
    --payload-json <path/to/updateDefinition_body.json> \\
    --out-json <path/to/result.json>
"""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError
from urllib.request import Request, urlopen


FABRIC_BASE = "https://api.fabric.microsoft.com/v1"


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


def http_json(method: str, url: str, token: str, body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
    req = Request(
        url,
        data=body,
        method=method.upper(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urlopen(req) as resp:
        return resp.status, dict(resp.headers), resp.read()


def try_post(token: str, urls: Iterable[str], body: bytes) -> tuple[str, int, dict[str, str], bytes]:
    last_error: Exception | None = None
    for url in urls:
        try:
            status, headers, payload = http_json("POST", url, token, body=body)
            return url, status, headers, payload
        except HTTPError as exc:
            # Read server payload for debugging, then decide whether to fall back.
            err_body = exc.read() if hasattr(exc, "read") else b""
            last_error = RuntimeError(f"POST {url} failed HTTP {exc.code}: {err_body[:1000]!r}")
            # Only fall back on obvious endpoint mismatch.
            if exc.code in (404, 405):
                continue
            raise last_error
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            raise
    raise RuntimeError(str(last_error) if last_error else "No updateDefinition endpoint succeeded")


def poll_operation(token: str, operation_url: str, retry_after: int) -> dict[str, Any]:
    op_url = operation_url
    for _ in range(240):
        time.sleep(min(max(retry_after, 1), 30))
        status, headers, payload = http_json("GET", op_url, token)
        retry_after = int(headers.get("Retry-After") or "5")
        location = headers.get("Location")
        if location:
            op_url = location if location.startswith("http") else "https://api.fabric.microsoft.com" + location
        if status != 200:
            continue
        text = payload.decode("utf-8", errors="replace").strip()
        if not text:
            continue
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict) and "status" in parsed:
            s = str(parsed.get("status") or "").lower()
            if s == "failed":
                raise RuntimeError(f"updateDefinition failed: {parsed}")
            if s == "succeeded":
                return parsed
        # Some endpoints might return the final object directly.
        if isinstance(parsed, dict) and any(k in parsed for k in ("definition", "errorCode", "error")):
            return parsed
    raise TimeoutError(f"Timed out waiting for updateDefinition LRO: {operation_url}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--semantic-model-id", required=True)
    parser.add_argument("--payload-json", required=True)
    parser.add_argument("--out-json", required=True)
    args = parser.parse_args()

    payload_path = Path(args.payload_json).resolve()
    out_json = Path(args.out_json).resolve()
    if not payload_path.is_file():
        raise SystemExit(f"Not a file: {payload_path}")

    body = payload_path.read_bytes()
    # Basic sanity: ensure it has `definition.format` and at least one part.
    try:
        parsed = json.loads(body.decode("utf-8"))
        fmt = (parsed.get("definition") or {}).get("format")
        parts = (parsed.get("definition") or {}).get("parts") or []
        if fmt != "TMDL" or not isinstance(parts, list) or not parts:
            raise ValueError("payload-json is not a TMDL updateDefinition body")
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"Invalid payload-json: {exc}")

    token = az_token("https://api.fabric.microsoft.com")
    ws = args.workspace_id
    mid = args.semantic_model_id

    candidate_urls = [
        f"{FABRIC_BASE}/workspaces/{ws}/semanticModels/{mid}/updateDefinition",
        f"{FABRIC_BASE}/workspaces/{ws}/items/{mid}/updateDefinition",
    ]
    used_url, status, headers, resp_payload = try_post(token, candidate_urls, body)

    if status == 200:
        result = json.loads(resp_payload.decode("utf-8")) if resp_payload else {"status": "Succeeded"}
    elif status == 202:
        location = headers.get("Location")
        operation_id = headers.get("x-ms-operation-id")
        retry_after = int(headers.get("Retry-After") or "5")
        if location and location.startswith("/"):
            location = "https://api.fabric.microsoft.com" + location
        if not location and operation_id:
            location = f"https://api.fabric.microsoft.com/v1/operations/{operation_id}"
        if not location:
            raise RuntimeError("updateDefinition returned 202 but missing Location/x-ms-operation-id")
        result = poll_operation(token, location, retry_after)
    else:
        raise RuntimeError(f"Unexpected updateDefinition status {status}: {resp_payload[:500]!r}")

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps({"endpoint": used_url, "result": result}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"endpoint": used_url, "status": (result.get("status") if isinstance(result, dict) else None)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

