from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SUPPORT_SCHEMAS = {"ReferenceMaster_Enh", "ReferenceMaster_Enh_Wrk", "Shared_DW", "Shared_DW_Wrk", "Staging", "Staging_Wrk"}
WAVE_MAP = {
    "gold_shared": 1,
    "gold_dim": 10,
    "gold_helper": 20,
    "gold_fact": 30,
    "gold_dq": 40,
    "smoke": 90,
}


@dataclass(frozen=True)
class MartCatalog:
    business_marts: list[dict[str, Any]]
    object_to_mart: dict[str, str]
    object_to_role: dict[str, str]
    object_to_wave: dict[str, int]
    assets: list[dict[str, Any]]
    edges: list[dict[str, Any]]

    def classify_object(self, schema: str, object_name: str) -> str | None:
        key = object_key(schema, object_name)
        if key in self.object_to_mart:
            return self.object_to_mart[key]
        for mart in self.business_marts:
            prefixes = mart.get("schema_prefixes", [])
            if any(schema.startswith(prefix) for prefix in prefixes):
                return str(mart["id"])
        return None

    def role_for(self, schema: str, object_name: str, mart: str | None = None) -> str:
        key = object_key(schema, object_name)
        if key in self.object_to_role:
            return self.object_to_role[key]
        if schema in SUPPORT_SCHEMAS:
            return "support"
        if mart:
            return "business"
        return "unclassified"

    def wave_for(self, schema: str, object_name: str) -> int | None:
        return self.object_to_wave.get(object_key(schema, object_name))


def empty_catalog() -> MartCatalog:
    return MartCatalog(business_marts=[], object_to_mart={}, object_to_role={}, object_to_wave={}, assets=[], edges=[])


def load_mart_catalog(repo_root: Path) -> MartCatalog:
    marts_root = repo_root / "02_marts"
    if not marts_root.exists():
        return empty_catalog()

    business_marts: list[dict[str, Any]] = []
    object_to_mart: dict[str, str] = {}
    object_to_role: dict[str, str] = {}
    object_to_wave: dict[str, int] = {}
    all_assets: list[dict[str, Any]] = []
    all_edges: list[dict[str, Any]] = []

    for mart_dir in sorted(path for path in marts_root.iterdir() if path.is_dir()):
        catalog_dir = mart_dir / "05_catalog"
        assets_path = catalog_dir / "assets.json"
        edges_path = catalog_dir / "lineage_edges.json"
        run_order_path = catalog_dir / "run_order.json"
        if not assets_path.exists():
            continue
        mart_id = mart_dir.name
        assets = json.loads(assets_path.read_text(encoding="utf-8")).get("assets", [])
        edges = _load_json(edges_path).get("edges", [])
        run_order = _load_json(run_order_path).get("sequence", [])
        display_name = mart_id.replace("_", " ").title()
        schema_prefixes: set[str] = set()

        for asset in assets:
            asset = {**asset, "mart": mart_id}
            all_assets.append(asset)
            schema = str(asset.get("schema") or "")
            object_name = str(asset.get("object") or "")
            if not schema or not object_name:
                continue
            role = "support" if schema in SUPPORT_SCHEMAS else "business"
            key = object_key(schema, object_name)
            object_to_role[key] = role
            if role == "business":
                object_to_mart[key] = mart_id
                if "_" in schema:
                    schema_prefixes.add(schema.split("_", 1)[0])

        for step in run_order:
            schema, object_name = split_object(str(step.get("object") or ""))
            if not schema or not object_name:
                continue
            wave = normalize_wave(step.get("wave"))
            if object_name == "*" and wave is not None:
                for asset in assets:
                    if str(asset.get("schema") or "") == schema:
                        asset_object = str(asset.get("object") or "")
                        if asset_object:
                            object_to_wave[object_key(schema, asset_object)] = wave
                continue

            key = object_key(schema, object_name)
            if wave is not None:
                object_to_wave[key] = wave
            if schema in SUPPORT_SCHEMAS:
                object_to_role[key] = "support"
            else:
                object_to_role.setdefault(key, "business")
                object_to_mart.setdefault(key, mart_id)
                if "_" in schema:
                    schema_prefixes.add(schema.split("_", 1)[0])

        for edge in edges:
            all_edges.append({**edge, "mart": mart_id})

        business_marts.append(
            {
                "id": mart_id,
                "display_name": display_name,
                "catalog_path": str(catalog_dir.relative_to(repo_root)),
                "schema_prefixes": sorted(schema_prefixes),
            }
        )

    return MartCatalog(
        business_marts=business_marts,
        object_to_mart=object_to_mart,
        object_to_role=object_to_role,
        object_to_wave=object_to_wave,
        assets=all_assets,
        edges=all_edges,
    )


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "02_marts").exists() and (candidate / ".git").exists():
            return candidate
    return current


def split_object(raw: str) -> tuple[str, str]:
    parts = [part.strip().strip("[]") for part in raw.split(".") if part.strip()]
    if len(parts) < 2:
        return "", ""
    return parts[-2], parts[-1]


def object_key(schema: str, object_name: str) -> str:
    return f"{schema}.{object_name}".lower()


def normalize_wave(raw: Any) -> int | None:
    if raw is None:
        return None
    if isinstance(raw, int):
        return raw if raw > 0 else 1
    text = str(raw)
    if text.isdigit():
        value = int(text)
        return value if value > 0 else 1
    mapped = WAVE_MAP.get(text)
    if mapped is None:
        return None
    return mapped if mapped > 0 else 1


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))
