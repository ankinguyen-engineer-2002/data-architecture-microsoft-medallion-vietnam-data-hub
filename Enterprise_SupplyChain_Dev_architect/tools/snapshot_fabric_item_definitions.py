#!/usr/bin/env python3
"""
Snapshot Fabric item definitions via REST API (supports LRO).

Read-only tool:
- POST /v1/workspaces/{workspaceId}/items/{itemId}/getDefinition
- If 202 Accepted, poll Location until succeeded and return result

Writes:
- artifacts/build_runs/<ts>_fabric_item_definitions/<item_name_or_id>/
  - getDefinition.json
  - parts/<part.path> (decoded payload)
  - parts_index.json
  - meta.json
"""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import subprocess
import time
import urllib.error
import urllib.request
from typing import Any


def run(cmd: list[str], *, input_text: str | None = None) -> str:
    return subprocess.check_output(cmd, text=True, input=input_text)


def az_token(resource: str) -> str:
    return (
        run(
            [
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
        )
        .strip()
    )


def request_json(
    method: str,
    url: str,
    token: str,
    body: dict[str, Any] | None = None,
    *,
    allow_lro: bool = True,
) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method.upper(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            raw = resp.read().decode("utf-8")
            if resp.status == 202 and allow_lro:
                location = resp.headers.get("Location")
                retry_after = int(resp.headers.get("Retry-After", "5"))
                if not location:
                    return {"status": "accepted", "location": None}
                return poll_lro(location, token, retry_after)
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} failed with {exc.code}: {error_body}") from exc


def poll_lro(location: str, token: str, retry_after: int) -> dict[str, Any]:
    for _ in range(60):
        time.sleep(min(max(retry_after, 1), 30))
        payload = request_json("GET", location, token, allow_lro=False)
        status = str(payload.get("status", "")).lower()
        if status in ("succeeded", "success", "completed"):
            result = payload.get("result")
            if result:
                return result
            # Some Fabric operations (notably getDefinition for SemanticModel) return the
            # actual payload at a secondary /result endpoint.
            try:
                secondary = request_json("GET", f"{location}/result", token, allow_lro=False)
                if secondary:
                    return secondary
            except Exception:  # noqa: BLE001
                pass
            return payload
        if status in ("failed", "cancelled", "canceled"):
            raise RuntimeError(f"LRO failed: {json.dumps(payload, ensure_ascii=False)}")
        retry_after = 5
    raise TimeoutError(f"LRO did not complete: {location}")


def write_json(path: pathlib.Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_text(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def decode_definition_parts(definition: dict[str, Any], output_dir: pathlib.Path) -> list[dict[str, Any]]:
    parts = definition.get("definition", {}).get("parts", [])
    decoded: list[dict[str, Any]] = []
    for part in parts:
        rel_path = part["path"]
        payload = part.get("payload", "")
        payload_type = part.get("payloadType")
        if payload_type == "InlineBase64":
            content = base64.b64decode(payload).decode("utf-8")
        else:
            content = payload
        write_text(output_dir / "parts" / rel_path, content)
        decoded.append({"path": rel_path, "payloadType": payload_type})
    return decoded


def safe_dir_name(name: str) -> str:
    keep = []
    for ch in name.strip():
        if ch.isalnum() or ch in ("-", "_", ".", " "):
            keep.append(ch)
        else:
            keep.append("_")
    return "".join(keep).strip().replace(" ", "_") or "item"


def build_output_dir(root: pathlib.Path, suffix: str) -> pathlib.Path:
    ts = time.strftime("%Y%m%d_%H%M%S")
    return root / "Enterprise_SupplyChain_Dev_architect" / "artifacts" / "build_runs" / f"{ts}_{suffix}"


def load_items_from_json(path: pathlib.Path) -> list[dict[str, str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and "items" in payload:
        items = payload["items"]
        if not isinstance(items, list):
            raise ValueError("items_json must contain {items:[...]}")
        return items
    if isinstance(payload, list):
        return payload
    raise ValueError("items_json must be a list or contain {items:[...]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--item-id", action="append", default=[])
    parser.add_argument("--item-name", action="append", default=[])
    parser.add_argument("--items-json", type=pathlib.Path)
    parser.add_argument("--output-dir", type=pathlib.Path)
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    output_dir = args.output_dir or build_output_dir(root, "fabric_item_definitions")
    output_dir.mkdir(parents=True, exist_ok=True)

    items: list[dict[str, str]] = []
    if args.items_json:
        items.extend(load_items_from_json(args.items_json))
    for item_id in args.item_id:
        items.append({"id": item_id})
    for name in args.item_name:
        items.append({"name": name})

    if not items:
        raise SystemExit("Provide --item-id/--item-name or --items-json")

    token = az_token("https://api.fabric.microsoft.com")
    ws = args.workspace_id

    # Optional resolution by name using list items
    name_to_id: dict[str, str] = {}
    if any("name" in it and "id" not in it for it in items):
        list_url = f"https://api.fabric.microsoft.com/v1/workspaces/{ws}/items"
        listing = request_json("GET", list_url, token)
        for it in listing.get("value", []):
            if it.get("displayName") and it.get("id"):
                name_to_id[it["displayName"]] = it["id"]
        write_json(output_dir / "workspace_items.json", listing)

    results: list[dict[str, Any]] = []
    for it in items:
        item_id = it.get("id")
        display_name = it.get("name")
        if not item_id and display_name:
            item_id = name_to_id.get(display_name)
        if not item_id:
            results.append(
                {
                    "name": display_name,
                    "id": it.get("id"),
                    "ok": False,
                    "error": "Item id not resolved",
                }
            )
            continue

        item_label = safe_dir_name(display_name or item_id)
        item_dir = output_dir / item_label

        url = f"https://api.fabric.microsoft.com/v1/workspaces/{ws}/items/{item_id}/getDefinition"
        try:
            definition = request_json("POST", url, token, body=None)
            write_json(item_dir / "getDefinition.json", definition)
            parts_index = decode_definition_parts(definition, item_dir)
            write_json(item_dir / "parts_index.json", parts_index)
            write_json(
                item_dir / "meta.json",
                {"workspaceId": ws, "itemId": item_id, "displayName": display_name},
            )
            results.append({"name": display_name, "id": item_id, "ok": True, "dir": str(item_dir)})
        except Exception as exc:
            results.append(
                {
                    "name": display_name,
                    "id": item_id,
                    "ok": False,
                    "error": str(exc),
                    "url": url,
                }
            )

    write_json(output_dir / "summary.json", {"results": results})
    print(json.dumps({"output_dir": str(output_dir), "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
