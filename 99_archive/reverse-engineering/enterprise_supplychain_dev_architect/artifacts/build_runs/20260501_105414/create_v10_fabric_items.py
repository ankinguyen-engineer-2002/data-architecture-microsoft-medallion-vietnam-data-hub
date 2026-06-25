#!/usr/bin/env python3
"""Create or designate v10 Fabric Warehouse items."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
FABRIC_RESOURCE = "https://api.fabric.microsoft.com"
FABRIC_BASE = "https://api.fabric.microsoft.com/v1"

WAREHOUSES = [
    {
        "displayName": "SupplyChain_Processing_Warehouse",
        "description": "Supply Chain processing warehouse: Meta, Staging, ReferenceMaster, Domain Silver schemas.",
        "logicalRole": "Processing",
    },
    {
        "displayName": "SupplyChain_Gold_Warehouse",
        "description": "Dedicated Supply Chain Gold serving warehouse for Direct Lake semantic models.",
        "logicalRole": "GoldServing",
    },
]


def az_rest(method: str, url: str, body: dict | None = None) -> dict:
    cmd = [
        "az",
        "rest",
        "--method",
        method,
        "--resource",
        FABRIC_RESOURCE,
        "--url",
        url,
        "--output",
        "json",
    ]
    if body is not None:
        cmd.extend(["--headers", "Content-Type=application/json", "--body", json.dumps(body)])
    result = subprocess.run(cmd, capture_output=True, text=True)
    parsed = None
    if result.stdout.strip():
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            parsed = {"raw": result.stdout.strip()}
    return {
        "returncode": result.returncode,
        "stdout": parsed,
        "stderr": result.stderr.strip(),
        "method": method,
        "url": url,
    }


def list_items() -> list[dict]:
    response = az_rest("GET", f"{FABRIC_BASE}/workspaces/{WORKSPACE_ID}/items")
    if response["returncode"] != 0:
        raise RuntimeError(response["stderr"])
    return response["stdout"]["value"]


def find_item(display_name: str, item_type: str = "Warehouse") -> dict | None:
    for item in list_items():
        if item["displayName"] == display_name and item["type"] == item_type:
            return item
    return None


def wait_for_item(display_name: str, timeout_seconds: int = 240) -> dict:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        item = find_item(display_name)
        if item:
            return item
        time.sleep(10)
    raise TimeoutError(f"Timed out waiting for Warehouse item {display_name}")


def create_or_get_warehouse(spec: dict) -> dict:
    existing = find_item(spec["displayName"])
    if existing:
        return {"action": "existing", "item": existing, "create_response": None, **spec}

    body = {"displayName": spec["displayName"], "description": spec["description"]}
    create_response = az_rest("POST", f"{FABRIC_BASE}/workspaces/{WORKSPACE_ID}/warehouses", body)
    if create_response["returncode"] != 0:
        return {"action": "create_failed", "create_response": create_response, **spec}

    created = create_response["stdout"] if isinstance(create_response["stdout"], dict) else None
    if created and created.get("id"):
        item = created
    else:
        item = wait_for_item(spec["displayName"])

    return {"action": "created", "item": item, "create_response": create_response, **spec}


def get_warehouse_details(item_id: str) -> dict:
    response = az_rest("GET", f"{FABRIC_BASE}/workspaces/{WORKSPACE_ID}/warehouses/{item_id}")
    if response["returncode"] != 0:
        return {"returncode": response["returncode"], "error": response["stderr"]}
    return response["stdout"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    output = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "workspace_id": WORKSPACE_ID,
        "warehouses": [],
    }

    for spec in WAREHOUSES:
        result = create_or_get_warehouse(spec)
        if result["action"] != "create_failed" and result.get("item", {}).get("id"):
            result["warehouse_details"] = get_warehouse_details(result["item"]["id"])
        output["warehouses"].append(result)

    output["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    Path(args.out).write_text(json.dumps(output, indent=2, sort_keys=True), encoding="utf-8")

    failed = [item for item in output["warehouses"] if item["action"] == "create_failed"]
    print(
        json.dumps(
            {
                "warehouse_count": len(output["warehouses"]),
                "failed_count": len(failed),
                "items": [
                    {
                        "displayName": item["displayName"],
                        "action": item["action"],
                        "id": item.get("item", {}).get("id"),
                    }
                    for item in output["warehouses"]
                ],
            },
            sort_keys=True,
        )
    )
    return 0 if not failed else 2


if __name__ == "__main__":
    raise SystemExit(main())
