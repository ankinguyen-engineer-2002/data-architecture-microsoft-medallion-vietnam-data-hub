#!/usr/bin/env python3
"""Create the Forecast Accuracy Agent semantic model through Fabric REST."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path


FABRIC_RESOURCE = "https://api.fabric.microsoft.com"
API = f"{FABRIC_RESOURCE}/v1"
MODEL_NAME = "sc_forecast_accuracy_agent"


def az_token() -> str:
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource", FABRIC_RESOURCE,
         "--query", "accessToken", "-o", "tsv"],
        check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def request(token: str, method: str, url: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=120) as response:
        payload = response.read()
        return response.status, dict(response.headers), json.loads(payload) if payload else None


def encoded_part(path: str, content: bytes) -> dict[str, str]:
    return {
        "path": path,
        "payload": base64.b64encode(content).decode("ascii"),
        "payloadType": "InlineBase64",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--folder-id")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    definition = root / "definition"
    token = az_token()

    _, _, workspace = request(token, "GET", f"{API}/workspaces/{args.workspace_id}")
    if not workspace.get("capacityId"):
        raise SystemExit("Target workspace is not assigned to Fabric capacity")

    _, _, existing = request(token, "GET", f"{API}/workspaces/{args.workspace_id}/semanticModels")
    duplicates = [item for item in existing.get("value", []) if item.get("displayName") == MODEL_NAME]
    if duplicates:
        raise SystemExit(f"Refusing duplicate create: {MODEL_NAME} already exists")

    expression = (definition / "expressions.template.tmdl").read_text(encoding="utf-8")
    expression = expression.replace("__WORKSPACE_ID__", args.workspace_id)
    expression = expression.replace("__WAREHOUSE_ID__", args.warehouse_id)

    parts = [encoded_part("definition.pbism", (root / "definition.pbism").read_bytes())]
    for path in sorted(definition.rglob("*.tmdl")):
        if path.name == "expressions.template.tmdl":
            continue
        relative = path.relative_to(root).as_posix()
        parts.append(encoded_part(relative, path.read_bytes()))
    parts.append(encoded_part("definition/expressions.tmdl", expression.encode("utf-8")))

    body = {
        "displayName": MODEL_NAME,
        "description": "Forecast-only Direct Lake semantic model for Fabric Data Agent and Copilot Studio, with deterministic horizon and snapshot guardrails.",
        "definition": {"format": "TMDL", "parts": parts},
    }
    if args.folder_id:
        body["folderId"] = args.folder_id

    print(json.dumps({"model": MODEL_NAME, "parts": len(parts), "execute": args.execute}, indent=2))
    if not args.execute:
        return

    status, headers, result = request(
        token, "POST", f"{API}/workspaces/{args.workspace_id}/semanticModels", body
    )
    if status == 201:
        print(json.dumps(result, indent=2))
        return
    if status != 202:
        raise SystemExit(f"Unexpected create status: {status}")

    operation_url = headers.get("Location") or headers.get("location")
    if not operation_url:
        raise SystemExit("Create returned 202 without Location header")

    for _ in range(60):
        time.sleep(2)
        _, _, operation = request(token, "GET", operation_url)
        if operation.get("status") == "Succeeded":
            _, _, created = request(token, "GET", f"{operation_url}/result")
            print(json.dumps(created, indent=2))
            return
        if operation.get("status") == "Failed":
            raise SystemExit(json.dumps(operation, indent=2))
    raise SystemExit("Timed out waiting for semantic model creation")


if __name__ == "__main__":
    main()
