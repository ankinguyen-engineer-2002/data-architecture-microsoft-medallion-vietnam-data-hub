from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .classifier import (
    classify_layer,
    classify_mart,
    stable_node_id,
    tabledict_node,
    tabledict_target_database,
)
from .config import (
    DEFAULT_WORKSPACE_ID,
    DEFAULT_WORKSPACE_NAME,
    ETL_DATABASE,
    GOLD_DATABASE,
    PROCESSING_DATABASE,
    SOURCE_DATABASE,
)
from .dependency_parser import ObjectRef, extract_object_refs
from .mart_catalog import MartCatalog, empty_catalog
from .semantic_reader import extract_semantic_table_sources
from .snapshot_writer import now_utc
from .wave_builder import assign_waves, layer_summary, mart_summary


def load_fixture(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def build_snapshot(
    *,
    workspace_id: str = DEFAULT_WORKSPACE_ID,
    workspace_name: str = DEFAULT_WORKSPACE_NAME,
    workspace_items: list[dict[str, Any]] | None = None,
    sql_scan: dict[str, Any],
    semantic_definition: dict[str, Any] | None = None,
    semantic_model_name: str = "sc_control_tower",
    generated_at_utc: str | None = None,
    mart_catalog: MartCatalog | None = None,
) -> dict[str, Any]:
    nodes: dict[str, dict[str, Any]] = {}
    edges: dict[tuple[str, str, str], dict[str, Any]] = {}
    warnings: list[str] = []
    catalog = mart_catalog or empty_catalog()

    def add_node(node: dict[str, Any]) -> None:
        enriched = enrich_node(node, catalog)
        nodes[enriched["id"]] = {**nodes.get(enriched["id"], {}), **enriched}

    def add_edge(source: str, target: str, rel: str, confidence: str, evidence: str) -> None:
        if source == target:
            return
        key = (source, target, rel)
        edges[key] = {
            "id": f"{source}::{rel}::{target}",
            "source": source,
            "target": target,
            "relationship_type": rel,
            "confidence": confidence,
            "evidence": evidence,
        }

    # Final table nodes from Enterprise ETL TableDictionary.
    for row in sql_scan.get("table_dictionary", []):
        if row.get("SchemaName") and row.get("TableName"):
            node = tabledict_node(row)
            add_node(node)
            source_ref = parse_replicated_source(row.get("ReplicatedSource"), node["database"])
            if source_ref:
                view_id = stable_node_id(source_ref.database or node["database"], source_ref.schema, source_ref.object_name)
                add_edge(view_id, node["id"], "loads", "verified", "DW_Developer.TableDictionary.ReplicatedSource")

    # Live object nodes and SQL definitions.
    modules_by_id: dict[str, str] = {}
    for database, rows in sql_scan.get("objects", {}).items():
        for row in rows:
            schema = str(row.get("schema_name") or "")
            obj = str(row.get("object_name") or "")
            type_desc = str(row.get("type_desc") or "")
            if not schema or not obj:
                continue
            node_id = stable_node_id(database, schema, obj)
            add_node(
                {
                    "id": node_id,
                    "display_name": obj,
                    "full_name": node_id,
                    "workspace": workspace_name,
                    "database": database,
                    "schema": schema,
                    "object_name": obj,
                    "object_type": type_desc,
                    "layer": classify_layer(database, schema, type_desc),
                    "mart": classify_with_catalog(catalog, schema, obj),
                    "wave": None,
                    "load_method": nodes.get(node_id, {}).get("load_method", ""),
                    "source_sql": nodes.get(node_id, {}).get("source_sql", ""),
                    "row_count": nodes.get(node_id, {}).get("row_count"),
                    "last_modified": str(row.get("modify_date") or ""),
                    "status": "active",
                    "evidence": sorted(set(nodes.get(node_id, {}).get("evidence", []) + ["sys.objects"])),
                }
            )

    for database, rows in sql_scan.get("modules", {}).items():
        for row in rows:
            schema = str(row.get("schema_name") or "")
            obj = str(row.get("object_name") or "")
            definition = str(row.get("definition") or "")
            node_id = stable_node_id(database, schema, obj)
            modules_by_id[node_id] = definition
            if node_id in nodes:
                nodes[node_id]["source_sql"] = definition
            for ref in extract_object_refs(definition, default_database=database):
                ref_db = ref.database or database
                source_id = stable_node_id(ref_db, ref.schema, ref.object_name)
                if source_id not in nodes:
                    add_node(
                        {
                            "id": source_id,
                            "display_name": ref.object_name,
                            "full_name": source_id,
                            "workspace": workspace_name,
                            "database": ref_db,
                            "schema": ref.schema,
                            "object_name": ref.object_name,
                            "object_type": "REFERENCE",
                            "layer": classify_layer(ref_db, ref.schema, "REFERENCE"),
                            "mart": classify_with_catalog(catalog, ref.schema, ref.object_name),
                            "wave": None,
                            "load_method": "",
                            "source_sql": "",
                            "row_count": None,
                            "last_modified": "",
                            "status": "referenced",
                            "evidence": ["sys.sql_modules dependency parse"],
                        }
                    )
                add_edge(source_id, node_id, "uses", "parsed", f"sys.sql_modules:{node_id}")

    # Collapse _Wrk view dependencies to final table edges when TableDictionary maps them.
    for row in sql_scan.get("table_dictionary", []):
        schema = str(row.get("SchemaName") or "")
        table = str(row.get("TableName") or "")
        target_db = tabledict_target_database(schema)
        target_id = stable_node_id(target_db, schema, table)
        source_ref = parse_replicated_source(row.get("ReplicatedSource"), target_db)
        if not source_ref:
            continue
        view_id = stable_node_id(source_ref.database or target_db, source_ref.schema, source_ref.object_name)
        if view_id in nodes and target_id in nodes:
            nodes[view_id]["mart"] = nodes[target_id].get("mart", nodes[view_id].get("mart"))
            nodes[view_id]["role"] = nodes[target_id].get("role", nodes[view_id].get("role"))
            nodes[view_id]["wave"] = nodes[target_id].get("wave", nodes[view_id].get("wave"))
        view_sql = modules_by_id.get(view_id, "")
        if view_sql and target_id in nodes:
            nodes[target_id]["source_sql"] = view_sql
        for edge in list(edges.values()):
            if edge["target"] == view_id and edge["source"] != target_id:
                add_edge(edge["source"], target_id, "transforms_to", edge["confidence"], edge["evidence"])

    # Semantic edges.
    semantic_model_id = stable_node_id("SemanticModel", semantic_model_name, "Model")
    add_node(
        {
            "id": semantic_model_id,
            "display_name": semantic_model_name,
            "full_name": semantic_model_id,
            "workspace": workspace_name,
            "database": "SemanticModel",
            "schema": semantic_model_name,
            "object_name": "Model",
            "object_type": "SEMANTIC_MODEL",
            "layer": "Semantic",
            "mart": "shared",
            "role": "semantic",
            "wave": 0,
            "load_method": "Direct Lake",
            "source_sql": "",
            "row_count": None,
            "last_modified": "",
            "status": "active",
            "evidence": ["Fabric semantic model definition"],
        }
    )
    if semantic_definition:
        for semantic_row in extract_semantic_table_sources(semantic_definition, semantic_model_name):
            table_id = stable_node_id("SemanticModel", semantic_model_name, semantic_row["semantic_table"])
            add_node(
                {
                    "id": table_id,
                    "display_name": semantic_row["semantic_table"],
                    "full_name": table_id,
                    "workspace": workspace_name,
                    "database": "SemanticModel",
                    "schema": semantic_model_name,
                    "object_name": semantic_row["semantic_table"],
                    "object_type": "SEMANTIC_TABLE",
                    "layer": "Semantic",
                    "mart": classify_with_catalog(catalog, semantic_row["source_schema"], semantic_row["source_table"]),
                    "role": "semantic",
                    "wave": 0,
                    "load_method": "Direct Lake",
                    "source_sql": "",
                    "row_count": None,
                    "last_modified": "",
                    "status": "active",
                    "evidence": ["Fabric semantic model TMDL"],
                }
            )
            source_id = stable_node_id(GOLD_DATABASE, semantic_row["source_schema"], semantic_row["source_table"])
            add_edge(source_id, table_id, "semantic_binding", "verified", "sc_control_tower TMDL partition")
            add_edge(table_id, semantic_model_id, "belongs_to_model", "verified", "sc_control_tower TMDL table")
    else:
        warnings.append("Semantic model definition was not available; semantic edges are incomplete.")

    node_list = sorted(nodes.values(), key=lambda n: (str(n.get("layer")), str(n.get("mart")), str(n.get("full_name"))))
    edge_list = sorted(edges.values(), key=lambda e: (e["source"], e["target"], e["relationship_type"]))
    warnings.extend(assign_waves(node_list, edge_list))
    for node in node_list:
        lane_order, lane_label = lane_for(str(node.get("layer") or ""), str(node.get("role") or ""), node.get("wave"), str(node.get("schema") or ""))
        node["lane_order"] = lane_order
        node["lane_label"] = lane_label

    return {
        "generated_at_utc": generated_at_utc or now_utc(),
        "workspace": {"id": workspace_id, "name": workspace_name},
        "nodes": node_list,
        "edges": edge_list,
        "layers": layer_summary(node_list),
        "marts": mart_summary(node_list),
        "mart_registry": catalog.business_marts,
        "warnings": sorted(set(warnings)),
        "scan_evidence": {
            "workspace_item_count": len(workspace_items or []),
            "table_dictionary_rows": len(sql_scan.get("table_dictionary", [])),
            "processing_object_count": len(sql_scan.get("objects", {}).get(PROCESSING_DATABASE, [])),
            "gold_object_count": len(sql_scan.get("objects", {}).get(GOLD_DATABASE, [])),
            "source_object_count": len(sql_scan.get("objects", {}).get(SOURCE_DATABASE, [])),
            "semantic_model": semantic_model_name,
        },
}


def classify_with_catalog(catalog: MartCatalog, schema: str, object_name: str) -> str:
    return catalog.classify_object(schema, object_name) or classify_mart(schema, object_name)


def enrich_node(node: dict[str, Any], catalog: MartCatalog) -> dict[str, Any]:
    schema = str(node.get("schema") or "")
    object_name = str(node.get("object_name") or "")
    layer = str(node.get("layer") or "Unknown")
    mart = str(catalog.classify_object(schema, object_name) or node.get("mart") or classify_mart(schema, object_name))
    role = str(node.get("role") or catalog.role_for(schema, object_name, mart if mart not in {"shared", "unresolved"} else None))
    wave = node.get("wave")
    catalog_wave = catalog.wave_for(schema, object_name)
    if catalog_wave is not None:
        wave = catalog_wave
    lane_order, lane_label = lane_for(layer, role, wave, schema)
    return {
        **node,
        "mart": mart,
        "role": role,
        "wave": wave,
        "lane_order": lane_order,
        "lane_label": lane_label,
    }


def lane_for(layer: str, role: str, wave: Any, schema: str) -> tuple[int, str]:
    if layer == "Bronze":
        return 10, "01 Bronze Sources"
    if layer == "Silver":
        number = safe_int(wave, 0)
        return 200 + number, f"02 Silver W{number:02d}"
    if layer == "Gold":
        number = safe_int(wave, 0)
        if role == "support" or schema == "Shared_DW":
            return 300, "03 Gold W00 Shared"
        if number >= 30:
            return 330, "03 Gold W30 Facts"
        if number >= 20:
            return 320, "03 Gold W20 Helpers"
        if number >= 10:
            return 310, "03 Gold W10 Dimensions"
        return 300 + number, f"03 Gold W{number:02d}"
    if layer == "Semantic":
        return 400, "04 Semantic sc_control_tower"
    return 900, "Needs Classification"


def safe_int(raw: Any, fallback: int) -> int:
    if isinstance(raw, int):
        return raw
    if raw is None:
        return fallback
    text = str(raw)
    return int(text) if text.isdigit() else fallback


def parse_replicated_source(raw: Any, default_database: str) -> ObjectRef | None:
    if raw is None:
        return None
    text = str(raw).strip().strip("[]")
    if not text:
        return None
    parts = [part.strip().strip("[]") for part in text.split(".") if part.strip()]
    if len(parts) == 3:
        return ObjectRef(parts[0], parts[1], parts[2])
    if len(parts) == 2:
        return ObjectRef(default_database, parts[0], parts[1])
    return None
