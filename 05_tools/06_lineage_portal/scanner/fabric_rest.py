from __future__ import annotations

import base64
import json
import time
import urllib.error
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
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as exc:
        # Read body for diagnostics; do NOT log the token.
        body_snippet = ""
        try:
            body_snippet = exc.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        raise RuntimeError(
            f"Fabric REST {method} {url} -> HTTP {exc.code} {exc.reason}. Body: {body_snippet}"
        ) from exc


def list_workspace_items(workspace_id: str, token: str) -> list[dict[str, Any]]:
    _, _, payload = fabric_request("GET", f"{BASE_URL}/workspaces/{workspace_id}/items", token)
    return json.loads(payload.decode("utf-8")).get("value", [])


def resolve_semantic_model_id(workspace_id: str, model_name: str, token: str) -> str | None:
    """Fallback: find semantic model id by display name inside the workspace."""
    try:
        _, _, payload = fabric_request(
            "GET", f"{BASE_URL}/workspaces/{workspace_id}/semanticModels", token
        )
    except Exception:
        return None
    for item in json.loads(payload.decode("utf-8")).get("value", []):
        if str(item.get("displayName", "")).lower() == model_name.lower():
            return item.get("id")
    return None


def get_semantic_definition(workspace_id: str, semantic_model_id: str, token: str) -> dict[str, Any]:
    url = f"{BASE_URL}/workspaces/{workspace_id}/semanticModels/{semantic_model_id}/getDefinition?format=TMDL"
    status, headers, payload = fabric_request("POST", url, token, body=b"{}")
    if status == 200:
        return json.loads(payload.decode("utf-8"))
    if status != 202:
        raise RuntimeError(f"Unexpected semantic getDefinition status {status}")

    operation_id = headers.get("x-ms-operation-id")
    if not operation_id:
        raise RuntimeError("Semantic getDefinition LRO did not return x-ms-operation-id")

    # Always use Fabric API operation endpoint — PBI redirect URL may be unreachable from CI/CD.
    operation_url = f"{BASE_URL}/operations/{operation_id}"
    retry_after = int(headers.get("Retry-After") or "5")

    for attempt in range(120):
        time.sleep(retry_after)
        status, _, payload = fabric_request("GET", operation_url, token)
        retry_after = int(headers.get("Retry-After") or "5")
        if status != 200:
            continue
        parsed = json.loads(payload.decode("utf-8") or "{}")
        if "definition" in parsed:
            return parsed
        op_status = str(parsed.get("status", "")).lower()
        if op_status == "failed":
            raise RuntimeError(f"Semantic getDefinition failed: {parsed}")
        if op_status == "succeeded":
            _, _, result_payload = fabric_request("GET", f"{operation_url}/result", token)
            result = json.loads(result_payload.decode("utf-8"))
            if "definition" in result:
                return result
            raise RuntimeError(f"Semantic getDefinition result missing definition: {list(result.keys())}")
    raise TimeoutError(f"Timed out waiting for semantic model definition {semantic_model_id}")


def decode_definition_parts(definition: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for part in definition.get("definition", {}).get("parts", []):
        path = part.get("path")
        payload = part.get("payload")
        if path and payload:
            result[path] = base64.b64decode(payload).decode("utf-8", errors="replace")
    return result
