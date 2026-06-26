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

    object_meta = {
        stable_node_id(str(row.get("database_name") or ""), str(row.get("schema_name") or ""), str(row.get("object_name") or "")): row
        for rows in sql_scan.get("objects", {}).values()
        for row in rows
    }
    modules_by_id: dict[str, str] = {}
    module_meta_by_id: dict[str, dict[str, Any]] = {}
    for database, rows in sql_scan.get("modules", {}).items():
        for row in rows:
            node_id = stable_node_id(database, str(row.get("schema_name") or ""), str(row.get("object_name") or ""))
            modules_by_id[node_id] = str(row.get("definition") or "")
            module_meta_by_id[node_id] = row

    relevant_module_ids: set[str] = set()

    if catalog.business_marts:
        for asset in catalog.assets:
            database, schema, object_name = asset_ref_parts(asset)
            node_id = stable_node_id(database, schema, object_name)
            meta = object_meta.get(node_id, {})
            add_node(
                {
                    "id": node_id,
                    "display_name": object_name,
                    "full_name": node_id,
                    "workspace": workspace_name,
                    "database": database,
                    "schema": schema,
                    "object_name": object_name,
                    "object_type": str(meta.get("type_desc") or asset.get("object_type") or "CATALOG_ASSET"),
                    "layer": layer_from_catalog(str(asset.get("layer") or ""), database, schema),
                    "mart": asset.get("mart") or classify_with_catalog(catalog, schema, object_name),
                    "wave": catalog.wave_for(schema, object_name),
                    "load_method": "",
                    "source_sql": "",
                    "row_count": None,
                    "last_modified": str(meta.get("modify_date") or ""),
                    "status": "active" if meta else "catalog",
                    "evidence": ["02_marts/05_catalog/assets.json"],
                }
            )
            if node_id in modules_by_id:
                relevant_module_ids.add(node_id)

        for edge in catalog.edges:
            source_id = catalog_ref_to_node_id(str(edge.get("source") or ""))
            target_id = catalog_ref_to_node_id(str(edge.get("target") or ""))
            if source_id and target_id:
                add_edge(source_id, target_id, str(edge.get("edge_type") or "catalog_edge"), "catalog", str(edge.get("evidence_file") or "02_marts/05_catalog/lineage_edges.json"))

    # Final table nodes from Enterprise ETL TableDictionary.
    for row in sql_scan.get("table_dictionary", []):
        if row.get("SchemaName") and row.get("TableName"):
            node = tabledict_node(row)
            if not include_contract_node(node, catalog):
                continue
            if catalog.business_marts and node["id"] not in nodes:
                continue
            add_node(node)
            source_ref = parse_replicated_source(row.get("ReplicatedSource"), node["database"])
            if source_ref:
                view_id = stable_node_id(source_ref.database or node["database"], source_ref.schema, source_ref.object_name)
                view_node = node_from_ref(
                    workspace_name=workspace_name,
                    database=source_ref.database or node["database"],
                    schema=source_ref.schema,
                    object_name=source_ref.object_name,
                    object_type=object_type_for(view_id, object_meta, "VIEW"),
                    status="active" if view_id in object_meta else "referenced",
                    evidence=["DW_Developer.TableDictionary.ReplicatedSource"],
                    catalog=catalog,
                )
                view_node["mart"] = node.get("mart")
                view_node["role"] = node.get("role")
                view_node["wave"] = node.get("wave")
                add_node(view_node)
                relevant_module_ids.add(view_id)
                add_edge(view_id, node["id"], "loads", "verified", "DW_Developer.TableDictionary.ReplicatedSource")

    parsed_modules: set[str] = set()
    while relevant_module_ids:
        node_id = relevant_module_ids.pop()
        if node_id in parsed_modules:
            continue
        parsed_modules.add(node_id)
        definition = modules_by_id.get(node_id, "")
        if not definition:
            continue
        if node_id in nodes:
            nodes[node_id]["source_sql"] = definition
            nodes[node_id]["evidence"] = sorted(set(nodes[node_id].get("evidence", []) + ["sys.sql_modules"]))
        module_meta = module_meta_by_id.get(node_id, {})
        default_database = str(module_meta.get("database_name") or node_id.split(".", 1)[0])
        for ref in extract_object_refs(definition, default_database=default_database):
            ref_db = ref.database or default_database
            source_id = stable_node_id(ref_db, ref.schema, ref.object_name)
            if source_id not in nodes:
                add_node(
                    node_from_ref(
                        workspace_name=workspace_name,
                        database=ref_db,
                        schema=ref.schema,
                        object_name=ref.object_name,
                        object_type=object_type_for(source_id, object_meta, "REFERENCE"),
                        status="active" if source_id in object_meta else "referenced",
                        evidence=["sys.sql_modules dependency parse"],
                        catalog=catalog,
                    )
                )
            add_edge(source_id, node_id, "uses", "parsed", f"sys.sql_modules:{node_id}")
            if source_id in modules_by_id:
                relevant_module_ids.add(source_id)

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


def asset_ref_parts(asset: dict[str, Any]) -> tuple[str, str, str]:
    schema = str(asset.get("schema") or "")
    object_name = str(asset.get("object") or "")
    display = str(asset.get("display") or "")
    database = database_for_schema(schema, display)
    return database, schema, object_name


def catalog_ref_to_node_id(raw: str) -> str:
    if not raw:
        return ""
    parts = [part.strip().strip("[]") for part in raw.split(".") if part.strip()]
    if len(parts) >= 3 and parts[0] in {SOURCE_DATABASE, PROCESSING_DATABASE, GOLD_DATABASE, ETL_DATABASE, "SemanticModel"}:
        return stable_node_id(parts[0], parts[-2], parts[-1])
    if len(parts) >= 2:
        schema, object_name = parts[-2], parts[-1]
        return stable_node_id(database_for_schema(schema, raw), schema, object_name)
    return ""


def database_for_schema(schema: str, display: str = "") -> str:
    if display.startswith(f"{SOURCE_DATABASE}."):
        return SOURCE_DATABASE
    if display.startswith(f"{PROCESSING_DATABASE}."):
        return PROCESSING_DATABASE
    if display.startswith(f"{GOLD_DATABASE}."):
        return GOLD_DATABASE
    if display.startswith("SemanticModel."):
        return "SemanticModel"
    if schema.endswith("_DW") or schema.endswith("_DW_Wrk") or schema == "Shared_DW" or schema == "Shared_DW_Wrk":
        return GOLD_DATABASE
    if schema.endswith("_Enh") or schema.endswith("_Enh_Wrk") or schema in {"Staging", "Staging_Wrk", "ReferenceMaster_Enh", "ReferenceMaster_Enh_Wrk", "ProcessingSeed"}:
        return PROCESSING_DATABASE
    if schema == "Semantic":
        return "SemanticModel"
    return SOURCE_DATABASE


def layer_from_catalog(raw_layer: str, database: str, schema: str) -> str:
    normalized = raw_layer.lower()
    if normalized == "bronze":
        return "Bronze"
    if normalized in {"silver", "source_wrk"}:
        return "Silver" if database != SOURCE_DATABASE else "Bronze"
    if normalized == "gold":
        return "Gold"
    if normalized == "semantic":
        return "Semantic"
    return classify_layer(database, schema, "")


def include_contract_node(node: dict[str, Any], catalog: MartCatalog) -> bool:
    if not catalog.business_marts:
        return True
    role = catalog.role_for(str(node.get("schema") or ""), str(node.get("object_name") or ""))
    return role in {"business", "support"}


def node_from_ref(
    *,
    workspace_name: str,
    database: str,
    schema: str,
    object_name: str,
    object_type: str,
    status: str,
    evidence: list[str],
    catalog: MartCatalog,
) -> dict[str, Any]:
    node_id = stable_node_id(database, schema, object_name)
    return {
        "id": node_id,
        "display_name": object_name,
        "full_name": node_id,
        "workspace": workspace_name,
        "database": database,
        "schema": schema,
        "object_name": object_name,
        "object_type": object_type,
        "layer": classify_layer(database, schema, object_type),
        "mart": classify_with_catalog(catalog, schema, object_name),
        "wave": None,
        "load_method": "",
        "source_sql": "",
        "row_count": None,
        "last_modified": "",
        "status": status,
        "evidence": evidence,
    }


def object_type_for(node_id: str, object_meta: dict[str, dict[str, Any]], fallback: str) -> str:
    return str(object_meta.get(node_id, {}).get("type_desc") or fallback)


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
