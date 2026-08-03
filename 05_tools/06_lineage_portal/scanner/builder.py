from __future__ import annotations

import json
import hashlib
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
from .semantic_reader import extract_semantic_table_sources, semantic_binding_metadata
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
    repository_manifest: dict[str, Any] | None = None,
    live_baseline: dict[str, Any] | None = None,
    live_baseline_validation: dict[str, Any] | None = None,
    semantic_expected_binding_count: int | None = None,
    semantic_failure_reason: str = "",
) -> dict[str, Any]:
    nodes: dict[str, dict[str, Any]] = {}
    edges: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    warnings: list[str] = []
    catalog = mart_catalog or empty_catalog()
    live_baseline_views_used: set[str] = set()
    warnings.extend(str(item) for item in sql_scan.get("warnings", []) if item)

    def add_node(node: dict[str, Any]) -> None:
        enriched = enrich_node(node, catalog)
        nodes[enriched["id"]] = {**nodes.get(enriched["id"], {}), **enriched}

    def add_edge(
        source: str,
        target: str,
        rel: str,
        confidence: str,
        evidence: str,
        *,
        provenance: str = "live",
        evidence_timestamp: str = "",
        repository_sha: str = "",
        source_file: str = "",
    ) -> None:
        if source == target:
            return
        key = (source, target, rel, provenance)
        edges[key] = {
            "id": f"{source}::{rel}::{target}::{provenance}",
            "source": source,
            "target": target,
            "relationship_type": rel,
            "confidence": confidence,
            "evidence": evidence,
            "provenance": provenance,
            "sync_status": "unassessed",
            "evidence_timestamp": evidence_timestamp,
            "repository_sha": repository_sha,
            "source_file": source_file,
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

    dependency_refs_by_id: dict[str, list[ObjectRef]] = {}
    for database, rows in sql_scan.get("dependencies", {}).items():
        for row in rows:
            node_id = stable_node_id(
                database,
                str(row.get("referencing_schema_name") or ""),
                str(row.get("referencing_object_name") or ""),
            )
            dependency_refs_by_id.setdefault(node_id, []).append(
                ObjectRef(
                    str(row.get("referenced_database_name") or database),
                    str(row.get("referenced_schema_name") or ""),
                    str(row.get("referenced_object_name") or ""),
                )
            )

    baseline_refs_by_id: dict[str, list[ObjectRef]] = {}
    for view in (live_baseline or {}).get("views", []):
        node_id = stable_node_id(
            str(view.get("database") or ""),
            str(view.get("schema") or ""),
            str(view.get("object_name") or ""),
        )
        baseline_refs_by_id[node_id] = [
            ObjectRef(
                str(dep.get("database") or ""),
                str(dep.get("schema") or ""),
                str(dep.get("object_name") or ""),
            )
            for dep in view.get("dependencies", [])
            if dep.get("schema") and dep.get("object_name")
        ]

    relevant_module_ids: set[str] = set()

    if catalog.business_marts:
        for asset in catalog.assets:
            database, schema, object_name = asset_ref_parts(asset)
            object_type = str(asset.get("object_type") or "")
            # Semantic source files are catalog documentation, not SQL objects.
            # The semantic reader adds the real model/table nodes separately.
            if not schema or object_type.lower() == "semantic_artifact":
                continue
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
                    "object_type": str(meta.get("type_desc") or object_type or "CATALOG_ASSET"),
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
            if node_id in modules_by_id or node_id in baseline_refs_by_id:
                relevant_module_ids.add(node_id)

        # Catalog assets still provide mart/role/wave classification. Their
        # lineage edges are intentionally not loaded because they are static
        # repository evidence and previously masqueraded as live runtime truth.

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
        if definition and node_id in nodes:
            nodes[node_id]["source_sql_sha256"] = hashlib.sha256(definition.encode("utf-8")).hexdigest()
            nodes[node_id]["evidence"] = sorted(set(nodes[node_id].get("evidence", []) + ["sys.sql_modules"]))
        module_meta = module_meta_by_id.get(node_id, {})
        default_database = str(module_meta.get("database_name") or node_id.split(".", 1)[0])
        refs = dependency_refs_by_id.get(node_id, [])
        confidence = "verified"
        evidence = f"sys.sql_expression_dependencies:{node_id}"
        evidence_timestamp = ""
        if not refs and definition:
            refs = extract_object_refs(definition, default_database=default_database)
            confidence = "parsed"
            evidence = f"sys.sql_modules:{node_id}"
        if not refs and node_id in baseline_refs_by_id:
            refs = baseline_refs_by_id[node_id]
            confidence = "live_snapshot"
            evidence_timestamp = str((live_baseline or {}).get("generated_at_utc") or "")
            evidence = f"live lineage baseline:{node_id}"
            live_baseline_views_used.add(node_id)

        for ref in sorted(set(refs)):
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
                        evidence=[evidence],
                        catalog=catalog,
                    )
                )
            nodes[source_id]["role"] = "business"
            if nodes[source_id].get("mart") in {None, "", "unresolved"}:
                nodes[source_id]["mart"] = nodes.get(node_id, {}).get("mart", "unresolved")
            add_edge(
                source_id,
                node_id,
                "uses",
                confidence,
                evidence,
                evidence_timestamp=evidence_timestamp,
            )
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
            nodes[target_id]["source_sql_sha256"] = hashlib.sha256(view_sql.encode("utf-8")).hexdigest()
        for edge in list(edges.values()):
            if edge["target"] == view_id and edge["source"] != target_id:
                add_edge(
                    edge["source"],
                    target_id,
                    "transforms_to",
                    edge["confidence"],
                    edge["evidence"],
                    provenance=str(edge.get("provenance") or "live"),
                    evidence_timestamp=str(edge.get("evidence_timestamp") or ""),
                    repository_sha=str(edge.get("repository_sha") or ""),
                    source_file=str(edge.get("source_file") or ""),
                )

    add_repository_overlay(
        repository_manifest=repository_manifest,
        workspace_name=workspace_name,
        nodes=nodes,
        add_node=add_node,
        add_edge=add_edge,
        object_meta=object_meta,
        catalog=catalog,
    )

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
            "wave": 1,
            "load_method": "Direct Lake",
            "source_sql": "",
            "row_count": None,
            "last_modified": "",
            "status": "active",
            "evidence": ["Fabric semantic model definition"],
        }
    )
    allowed_semantic_sources = {
        f"{row.get('schema_name')}.{row.get('object_name')}"
        for row in object_meta.values()
        if str(row.get("database_name") or "") == GOLD_DATABASE
        and str(row.get("type_desc") or "").upper() in {"USER_TABLE", "TABLE"}
    }
    semantic_validation = semantic_binding_metadata(
        semantic_definition,
        semantic_model_name,
        expected_binding_count=semantic_expected_binding_count,
        allowed_source_ids=allowed_semantic_sources,
        failure_reason=semantic_failure_reason,
    )
    if semantic_validation["complete"]:
        for semantic_row in extract_semantic_table_sources(semantic_definition or {}, semantic_model_name):
            source_id = stable_node_id(GOLD_DATABASE, semantic_row["source_schema"], semantic_row["source_table"])
            if source_id not in nodes:
                # TMDL may bind an active Gold object omitted from the mart catalog.
                add_node(
                    node_from_ref(
                        workspace_name=workspace_name,
                        database=GOLD_DATABASE,
                        schema=semantic_row["source_schema"],
                        object_name=semantic_row["source_table"],
                        object_type=object_type_for(source_id, object_meta, "SEMANTIC_SOURCE"),
                        status="semantic_referenced",
                        evidence=["sc_control_tower TMDL partition"],
                        catalog=catalog,
                    )
                )
            add_edge(
                source_id,
                semantic_model_id,
                "feeds_semantic",
                "verified",
                f"sc_control_tower TMDL partition:{semantic_row['semantic_table']}",
            )
    else:
        warnings.append(f"Semantic lineage is {semantic_validation['status']}: {semantic_validation['reason']}")

    node_list = sorted(nodes.values(), key=lambda n: (str(n.get("layer")), str(n.get("mart")), str(n.get("full_name"))))
    edge_list = sorted(edges.values(), key=lambda e: (e["source"], e["target"], e["relationship_type"]))
    if catalog.business_marts:
        node_list, edge_list = simplify_to_table_graph(node_list, edge_list)
    edge_list = reconcile_lineage_edges(edge_list)
    if live_baseline_views_used:
        baseline_time = str((live_baseline or {}).get("generated_at_utc") or "unknown time")
        warnings.append(
            f"Live SQL dependency baseline from {baseline_time} was used for "
            f"{len(live_baseline_views_used)} view(s) because current dependency metadata was unavailable."
        )
    warnings.extend(assign_waves(node_list, edge_list))
    for node in node_list:
        # Public GitHub Pages snapshots retain only a stable hash, never source SQL.
        node["source_sql"] = ""
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
        "repository": repository_snapshot_metadata(repository_manifest),
        "live_baseline": live_baseline_snapshot_metadata(live_baseline, live_baseline_views_used, live_baseline_validation),
        "semantic_validation": semantic_validation,
        "warnings": sorted(set(warnings)),
        "scan_evidence": {
            "workspace_item_count": len(workspace_items or []),
            "table_dictionary_rows": len(sql_scan.get("table_dictionary", [])),
            "processing_object_count": len(sql_scan.get("objects", {}).get(PROCESSING_DATABASE, [])),
            "gold_object_count": len(sql_scan.get("objects", {}).get(GOLD_DATABASE, [])),
            "source_object_count": len(sql_scan.get("objects", {}).get(SOURCE_DATABASE, [])),
            "live_module_definition_count": sum(
                1
                for rows in sql_scan.get("modules", {}).values()
                for row in rows
                if row.get("definition")
            ),
            "live_dependency_row_count": sum(
                len(rows) for rows in sql_scan.get("dependencies", {}).values()
            ),
            "live_baseline_view_count": len(live_baseline_views_used),
            "repository_view_count": int(
                ((repository_manifest or {}).get("summary") or {}).get("view_count") or 0
            ),
            "repository_procedure_count": int(
                ((repository_manifest or {}).get("summary") or {}).get("procedure_count") or 0
            ),
            "repository_table_count": int(
                ((repository_manifest or {}).get("summary") or {}).get("table_count") or 0
            ),
            "lineage_sync": lineage_sync_summary(edge_list),
            "semantic_model": semantic_model_name,
            "semantic_binding_count": int(semantic_validation["binding_count"]),
            "semantic_complete": bool(semantic_validation["complete"]),
        },
}


def add_repository_overlay(
    *,
    repository_manifest: dict[str, Any] | None,
    workspace_name: str,
    nodes: dict[str, dict[str, Any]],
    add_node: Any,
    add_edge: Any,
    object_meta: dict[str, dict[str, Any]],
    catalog: MartCatalog,
) -> None:
    if not repository_manifest:
        return
    commit_sha = str(repository_manifest.get("commit_sha") or "")
    generated_at = str(repository_manifest.get("generated_at_utc") or "")
    repository = str(repository_manifest.get("repository") or "repository")

    for view in repository_manifest.get("views", []):
        target = view.get("target") or {}
        target_db = str(target.get("database") or view.get("database") or "")
        target_schema = str(target.get("schema") or view.get("schema") or "")
        target_object = str(target.get("object_name") or view.get("object_name") or "")
        target_id = stable_node_id(target_db, target_schema, target_object)
        view_id = stable_node_id(
            str(view.get("database") or ""),
            str(view.get("schema") or ""),
            str(view.get("object_name") or ""),
        )
        relationship = "uses" if target_id == view_id else "transforms_to"
        source_file = str(view.get("path") or "")
        repo_evidence = f"{repository}@{commit_sha[:12]}:{source_file}"

        if target_id not in nodes:
            add_node(
                node_from_ref(
                    workspace_name=workspace_name,
                    database=target_db,
                    schema=target_schema,
                    object_name=target_object,
                    object_type=object_type_for(target_id, object_meta, "REPOSITORY_TARGET"),
                    status="repository_target",
                    evidence=[repo_evidence],
                    catalog=catalog,
                )
            )
        else:
            nodes[target_id]["evidence"] = sorted(
                set(nodes[target_id].get("evidence", []) + [repo_evidence])
            )

        for dep in view.get("dependencies", []):
            source_db = str(dep.get("database") or target_db)
            source_schema = str(dep.get("schema") or "")
            source_object = str(dep.get("object_name") or "")
            if not source_schema or not source_object:
                continue
            source_id = stable_node_id(source_db, source_schema, source_object)
            if source_id not in nodes:
                add_node(
                    node_from_ref(
                        workspace_name=workspace_name,
                        database=source_db,
                        schema=source_schema,
                        object_name=source_object,
                        object_type=object_type_for(source_id, object_meta, "REPOSITORY_SOURCE"),
                        status="repository_target",
                        evidence=[repo_evidence],
                        catalog=catalog,
                    )
                )
            nodes[source_id]["role"] = "business"
            if nodes[source_id].get("mart") in {None, "", "unresolved"}:
                nodes[source_id]["mart"] = nodes[target_id].get("mart", "unresolved")
            add_edge(
                source_id,
                target_id,
                relationship,
                "repository",
                repo_evidence,
                provenance="repository_target",
                evidence_timestamp=generated_at,
                repository_sha=commit_sha,
                source_file=source_file,
            )


def reconcile_lineage_edges(edges: list[dict[str, Any]]) -> list[dict[str, Any]]:
    comparable_types = {"transforms_to", "uses"}
    comparable = [
        edge for edge in edges if edge.get("relationship_type") in comparable_types
    ]
    live_pairs = {
        (edge["source"], edge["target"], edge["relationship_type"])
        for edge in comparable
        if edge.get("provenance") == "live"
    }
    repo_pairs = {
        (edge["source"], edge["target"], edge["relationship_type"])
        for edge in comparable
        if edge.get("provenance") == "repository_target"
    }
    live_targets = {target for _, target, _ in live_pairs}
    repo_targets = {target for _, target, _ in repo_pairs}

    reconciled: list[dict[str, Any]] = []
    aligned_seen: set[tuple[str, str, str]] = set()
    by_pair: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for edge in comparable:
        by_pair.setdefault(
            (edge["source"], edge["target"], edge["relationship_type"]), []
        ).append(edge)

    for edge in edges:
        if edge.get("relationship_type") not in comparable_types:
            reconciled.append({**edge, "sync_status": "not_applicable"})
            continue
        pair = (edge["source"], edge["target"], edge["relationship_type"])
        if pair in live_pairs and pair in repo_pairs:
            if pair in aligned_seen:
                continue
            aligned_seen.add(pair)
            pair_edges = by_pair[pair]
            live_edge = next(item for item in pair_edges if item.get("provenance") == "live")
            repo_edge = next(
                item for item in pair_edges if item.get("provenance") == "repository_target"
            )
            reconciled.append(
                {
                    **live_edge,
                    "id": (
                        f"{edge['source']}::{edge['relationship_type']}::"
                        f"{edge['target']}::aligned"
                    ),
                    "provenance": "live+repository_target",
                    "sync_status": "aligned",
                    "confidence": "verified+repository",
                    "evidence": f"{live_edge['evidence']} | {repo_edge['evidence']}",
                    "repository_sha": repo_edge.get("repository_sha", ""),
                    "source_file": repo_edge.get("source_file", ""),
                }
            )
            continue

        provenance = str(edge.get("provenance") or "live")
        target = str(edge.get("target") or "")
        if provenance == "live":
            status = "drift" if target in repo_targets else "live_only"
        else:
            status = "drift" if target in live_targets else "repository_only"
        reconciled.append({**edge, "sync_status": status})

    return sorted(
        reconciled,
        key=lambda item: (
            str(item.get("source") or ""),
            str(item.get("target") or ""),
            str(item.get("relationship_type") or ""),
            str(item.get("provenance") or ""),
        ),
    )


def lineage_sync_summary(edges: list[dict[str, Any]]) -> dict[str, int]:
    statuses = {"aligned": 0, "drift": 0, "live_only": 0, "repository_only": 0}
    for edge in edges:
        status = str(edge.get("sync_status") or "")
        if status in statuses:
            statuses[status] += 1
    statuses["compared_edges"] = sum(statuses.values())
    statuses["drift_targets"] = len(
        {edge["target"] for edge in edges if edge.get("sync_status") == "drift"}
    )
    statuses["repository_only_targets"] = len(
        {
            edge["target"]
            for edge in edges
            if edge.get("sync_status") == "repository_only"
        }
    )
    statuses["live_only_targets"] = len(
        {edge["target"] for edge in edges if edge.get("sync_status") == "live_only"}
    )
    return statuses


def repository_snapshot_metadata(manifest: dict[str, Any] | None) -> dict[str, Any] | None:
    if not manifest:
        return None
    repository = str(manifest.get("repository") or "")
    pull_request = manifest.get("pull_request")
    return {
        "repository": repository,
        "commit_sha": str(manifest.get("commit_sha") or ""),
        "pull_request": pull_request,
        "pull_request_url": (
            f"https://github.com/{repository}/pull/{pull_request}"
            if repository and pull_request
            else ""
        ),
        "generated_at_utc": str(manifest.get("generated_at_utc") or ""),
        "summary": manifest.get("summary") or {},
    }


def live_baseline_snapshot_metadata(
    baseline: dict[str, Any] | None,
    used_views: set[str],
    validation: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    if not baseline and not validation:
        return None
    return {
        "generated_at_utc": str((baseline or {}).get("generated_at_utc") or ""),
        "used_view_count": len(used_views),
        "summary": (baseline or {}).get("summary") or {},
        "validation": validation or {},
    }


def classify_with_catalog(catalog: MartCatalog, schema: str, object_name: str) -> str:
    return catalog.classify_object(schema, object_name) or classify_mart(schema, object_name)


def simplify_to_table_graph(nodes: list[dict[str, Any]], edges: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    hidden = {node["id"] for node in nodes if is_work_view_node(node)}
    visible_ids = {node["id"] for node in nodes if node["id"] not in hidden}
    adjacency: dict[str, list[dict[str, Any]]] = {}
    for edge in edges:
        adjacency.setdefault(edge["source"], []).append(edge)

    simplified: dict[tuple[str, str, str, str], dict[str, Any]] = {}

    def add_simplified(source: str, target: str, source_edge: dict[str, Any], evidence: str) -> None:
        if source == target:
            return
        provenance = str(source_edge.get("provenance") or "live")
        key = (source, target, "transforms_to", provenance)
        simplified[key] = {
            "id": f"{source}::transforms_to::{target}::{provenance}",
            "source": source,
            "target": target,
            "relationship_type": "transforms_to",
            "confidence": str(source_edge.get("confidence") or "collapsed"),
            "evidence": evidence,
            "provenance": provenance,
            "sync_status": str(source_edge.get("sync_status") or "unassessed"),
            "evidence_timestamp": str(source_edge.get("evidence_timestamp") or ""),
            "repository_sha": str(source_edge.get("repository_sha") or ""),
            "source_file": str(source_edge.get("source_file") or ""),
        }

    for edge in edges:
        source = edge["source"]
        target = edge["target"]
        if source in visible_ids and target in visible_ids:
            provenance = str(edge.get("provenance") or "live")
            simplified[(source, target, edge["relationship_type"], provenance)] = edge
            continue
        if source not in visible_ids:
            continue
        stack = [(target, [edge.get("evidence", "")])]
        seen: set[str] = set()
        while stack:
            current, evidence_chain = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            if current in visible_ids:
                add_simplified(
                    source,
                    current,
                    edge,
                    " -> ".join(item for item in evidence_chain if item),
                )
                continue
            for next_edge in adjacency.get(current, []):
                stack.append((next_edge["target"], evidence_chain + [next_edge.get("evidence", "")]))

    visible_nodes = [node for node in nodes if node["id"] in visible_ids]
    return visible_nodes, sorted(simplified.values(), key=lambda e: (e["source"], e["target"], e["relationship_type"]))


def is_work_view_node(node: dict[str, Any]) -> bool:
    schema = str(node.get("schema") or "")
    object_name = str(node.get("object_name") or "")
    object_type = str(node.get("object_type") or "").lower()
    if schema == "Staging_Wrk":
        return False
    return schema.endswith("_Wrk") or object_name.startswith("v_") or object_type == "wrk_view"


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
        number = safe_int(wave, 1)
        return 200 + number, f"02 Silver W{number:02d}"
    if layer == "Gold":
        number = safe_int(wave, 1)
        if role == "support" or schema == "Shared_DW":
            return 300, "03 Gold W01 Shared"
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
