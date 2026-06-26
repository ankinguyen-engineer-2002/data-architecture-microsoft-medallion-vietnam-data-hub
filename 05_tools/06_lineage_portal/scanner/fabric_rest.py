from __future__ import annotations

import base64
import json
import time
import urllib.request
from typing import Any


BASE_URL = "https://api.fabric.microsoft.com/v1"


def fabric_request(method: str, url: str, token: str, body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.status, dict(resp.headers), resp.read()


def list_workspace_items(workspace_id: str, token: str) -> list[dict[str, Any]]:
    _, _, payload = fabric_request("GET", f"{BASE_URL}/workspaces/{workspace_id}/items", token)
    return json.loads(payload.decode("utf-8")).get("value", [])


def get_semantic_definition(workspace_id: str, semantic_model_id: str, token: str) -> dict[str, Any]:
    url = f"{BASE_URL}/workspaces/{workspace_id}/semanticModels/{semantic_model_id}/getDefinition?format=TMDL"
    status, headers, payload = fabric_request("POST", url, token, body=b"{}")
    if status == 200:
        return json.loads(payload.decode("utf-8"))
    if status != 202:
        raise RuntimeError(f"Unexpected semantic getDefinition status {status}")

    operation_url = headers.get("Location")
    if operation_url and operation_url.startswith("/"):
        operation_url = "https://api.fabric.microsoft.com" + operation_url
    operation_id = headers.get("x-ms-operation-id")
    retry_after = int(headers.get("Retry-After") or "5")
    if not operation_url and operation_id:
        operation_url = f"{BASE_URL}/operations/{operation_id}"
    if not operation_url:
        raise RuntimeError("Semantic getDefinition LRO did not return Location or operation id")

    for _ in range(120):
        time.sleep(retry_after)
        status, headers, payload = fabric_request("GET", operation_url, token)
        retry_after = int(headers.get("Retry-After") or "5")
        if status != 200:
            continue
        parsed = json.loads(payload.decode("utf-8") or "{}")
        if "definition" in parsed:
            return parsed
        if str(parsed.get("status", "")).lower() == "failed":
            raise RuntimeError(f"Semantic getDefinition failed: {parsed}")
        if str(parsed.get("status", "")).lower() == "succeeded" and operation_id:
            _, _, result_payload = fabric_request("GET", f"{BASE_URL}/operations/{operation_id}/result", token)
            return json.loads(result_payload.decode("utf-8"))
    raise TimeoutError(f"Timed out waiting for semantic model definition {semantic_model_id}")


def decode_definition_parts(definition: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for part in definition.get("definition", {}).get("parts", []):
        path = part.get("path")
        payload = part.get("payload")
        if path and payload:
            result[path] = base64.b64decode(payload).decode("utf-8", errors="replace")
    return result
