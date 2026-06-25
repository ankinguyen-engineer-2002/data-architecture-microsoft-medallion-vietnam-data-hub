#!/usr/bin/env python3
"""
Export Fabric item definition (getDefinition) with LRO polling that may hop domains.

Why:
  Some item getDefinition calls return 202 with Location on a wabi/analysis.windows.net
  operations endpoint, which requires a Power BI token (resource
  https://analysis.windows.net/powerbi/api) rather than a Fabric token.

This script:
  - POST /v1/workspaces/{ws}/items/{itemId}/getDefinition   (Fabric token)
  - If 202, poll Location using:
      * Fabric token for api.fabric.microsoft.com
      * Power BI token for *.analysis.windows.net / api.powerbi.com
  - Writes:
      <out-dir>/getDefinition.json
      <out-dir>/parts/<part.path> (decoded)
      <out-dir>/parts_index.json
      <out-dir>/export_meta.json

Usage:
  AZURE_CONFIG_DIR=/private/tmp/azcfg python3 01_docs/runbook/scripts/export_fabric_item_definition_dual_token.py \\
    --workspace-id <wsGuid> \\
    --item-id <itemGuid> \\
    --out-dir 01_docs/runbook/artifacts/<folder>
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
from urllib.parse import urlparse
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


def http_request(method: str, url: str, token: str, body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
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


def token_for_url(url: str, fabric_token: str, powerbi_token: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    if host.endswith("analysis.windows.net") or host == "api.powerbi.com":
        return powerbi_token
    return fabric_token


def poll_lro(location: str, fabric_token: str, powerbi_token: str, retry_after: int) -> dict[str, Any]:
    op_url = location
    for _ in range(180):
        time.sleep(min(max(retry_after, 1), 30))
        token = token_for_url(op_url, fabric_token, powerbi_token)
        status, headers, payload = http_request("GET", op_url, token)
        retry_after = int(headers.get("Retry-After") or "5")

        if status != 200:
            continue
        text = payload.decode("utf-8", errors="replace").strip()
        if not text:
            continue
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            continue

        # Some endpoints return the final object directly.
        if isinstance(parsed, dict) and ("definition" in parsed or "parts" in parsed):
            return parsed

        op_status = str(parsed.get("status") or "").lower() if isinstance(parsed, dict) else ""
        if op_status in ("failed", "cancelled", "canceled"):
            raise RuntimeError(f"LRO failed: {parsed}")
        if op_status in ("succeeded", "success", "completed"):
            result = parsed.get("result") if isinstance(parsed, dict) else None
            if isinstance(result, dict):
                return result
            # Some ops expose a /result endpoint.
            try:
                token = token_for_url(f"{op_url}/result", fabric_token, powerbi_token)
                rs, _, rp = http_request("GET", f"{op_url}/result", token)
                if rs == 200:
                    return json.loads(rp.decode("utf-8"))
            except Exception:  # noqa: BLE001
                pass

        # Follow redirects if server provides Location updates.
        new_loc = headers.get("Location")
        if new_loc:
            op_url = new_loc

    raise TimeoutError(f"LRO did not complete: {location}")


def decode_parts(definition: dict[str, Any], out_dir: Path) -> list[dict[str, Any]]:
    parts = definition.get("definition", {}).get("parts", []) if isinstance(definition, dict) else []
    index: list[dict[str, Any]] = []
    parts_dir = out_dir / "parts"
    parts_dir.mkdir(parents=True, exist_ok=True)
    for part in parts or []:
        rel_path = (part.get("path") or "").lstrip("/").strip()
        payload = part.get("payload") or ""
        if not rel_path or not payload:
            continue
        try:
            content = base64.b64decode(payload)
        except Exception:
            continue
        file_path = parts_dir / rel_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_bytes(content)
        index.append(
            {
                "path": rel_path,
                "bytes": len(content),
            }
        )
    return index


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--item-id", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    fabric_token = az_token("https://api.fabric.microsoft.com")
    powerbi_token = az_token("https://analysis.windows.net/powerbi/api")

    url = f"https://api.fabric.microsoft.com/v1/workspaces/{args.workspace_id}/items/{args.item_id}/getDefinition"
    status, headers, payload = http_request("POST", url, fabric_token, body=b"{}")
    if status == 200:
        definition = json.loads(payload.decode("utf-8")) if payload else {}
    elif status == 202:
        location = headers.get("Location")
        if not location:
            raise RuntimeError("202 Accepted but missing Location header")
        retry_after = int(headers.get("Retry-After") or "5")
        definition = poll_lro(location, fabric_token, powerbi_token, retry_after)
    else:
        raise RuntimeError(f"Unexpected status {status}: {payload[:500]!r}")

    (out_dir / "getDefinition.json").write_text(json.dumps(definition, indent=2, ensure_ascii=False), encoding="utf-8")
    parts_index = decode_parts(definition, out_dir)
    (out_dir / "parts_index.json").write_text(json.dumps(parts_index, indent=2), encoding="utf-8")

    meta = {
        "workspace_id": args.workspace_id,
        "item_id": args.item_id,
        "az_config_dir": os.getenv("AZURE_CONFIG_DIR", ""),
        "exported_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (out_dir / "export_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

