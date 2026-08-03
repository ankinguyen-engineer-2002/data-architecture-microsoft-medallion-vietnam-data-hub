from __future__ import annotations

import re
from typing import Any

from .fabric_rest import decode_definition_parts


def extract_semantic_table_sources(definition: dict, model_name: str) -> list[dict[str, str]]:
    parts = decode_definition_parts(definition)
    rows: list[dict[str, str]] = []
    for path, text in parts.items():
        if not path.startswith("definition/tables/") or not path.endswith(".tmdl"):
            continue
        table = path.split("/")[-1].removesuffix(".tmdl")
        source = extract_partition_source(text)
        if not source:
            source = extract_lineage_tag_source(text)
        if source:
            rows.append(
                {
                    "semantic_model": model_name,
                    "semantic_table": table,
                    "source_schema": source[0],
                    "source_table": source[1],
                }
            )
    return rows


def semantic_binding_metadata(
    definition: dict[str, Any] | None,
    model_name: str,
    *,
    expected_binding_count: int | None = None,
    allowed_source_ids: set[str] | None = None,
    failure_reason: str = "",
) -> dict[str, Any]:
    """Describe whether TMDL was read and every table binding was recovered."""
    if definition is None:
        return {
            "status": "unavailable", "complete": False, "definition_read": False,
            "expected_binding_count": expected_binding_count, "binding_count": 0,
            "table_part_count": 0, "unbound_table_count": 0,
            "reason": failure_reason or "Semantic model definition was not available.",
        }
    parts = decode_definition_parts(definition)
    table_paths = sorted(path for path in parts if path.startswith("definition/tables/") and path.endswith(".tmdl"))
    rows = extract_semantic_table_sources(definition, model_name)
    parsed_tables = {row["semantic_table"] for row in rows}
    non_binding_paths = [path for path in table_paths if path.split("/")[-1].removesuffix(".tmdl") not in parsed_tables]
    expected = expected_binding_count if expected_binding_count is not None else len(table_paths)
    source_ids = [f"{row['source_schema']}.{row['source_table']}" for row in rows]
    duplicate_semantic_tables = len(parsed_tables) != len(rows)
    duplicate_source_bindings = len(set(source_ids)) != len(source_ids)
    invalid_source_ids = sorted(
        source_id for source_id in source_ids
        if allowed_source_ids is not None and source_id not in allowed_source_ids
    )
    complete = (
        len(rows) == expected
        and not duplicate_semantic_tables
        and not duplicate_source_bindings
        and not invalid_source_ids
    )
    return {
        "status": "complete" if complete else "incomplete", "complete": complete,
        "definition_read": True, "expected_binding_count": expected,
        "binding_count": len(rows), "table_part_count": len(table_paths),
        "non_binding_table_count": len(non_binding_paths), "non_binding_table_paths": non_binding_paths,
        "duplicate_semantic_tables": duplicate_semantic_tables,
        "duplicate_source_bindings": duplicate_source_bindings,
        "invalid_source_ids": invalid_source_ids,
        "reason": "All expected TMDL Gold bindings were parsed." if complete else "TMDL binding coverage is incomplete or ambiguous.",
    }


def extract_partition_source(tmdl: str) -> tuple[str, str] | None:
    # Direct Lake partition: entityName + schemaName inside partition source block.
    direct_lake = re.search(
        r"entityName:\s*(\S+)\s+schemaName:\s*(\S+)",
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if direct_lake:
        return direct_lake.group(2).strip("'\""), direct_lake.group(1).strip("'\"")

    # SQL source partition: Schema + Item in partition definition.
    schema_item = re.search(
        r'Schema\s*=\s*"([^"]+)"\s*,\s*Item\s*=\s*"([^"]+)"',
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if schema_item:
        return schema_item.group(1), schema_item.group(2)

    # Bracket notation [Schema].[Table] anywhere in the TMDL.
    bracket = re.search(
        r"\[(Shared_DW|ForecastAccuracy_DW|InventoryHealth_DW)\]\.\[([^\]]+)\]",
        tmdl,
        flags=re.IGNORECASE,
    )
    if bracket:
        return bracket.group(1), bracket.group(2)
    return None


def extract_lineage_tag_source(tmdl: str) -> tuple[str, str] | None:
    """Fallback: parse sourceLineageTag from table header.

    Example: sourceLineageTag: [ForecastAccuracy_DW].[DimCustomerGrouping]
    """
    tag = re.search(
        r"sourceLineageTag:\s*\[(\w+)\]\.\[(\w+)\]",
        tmdl,
        flags=re.IGNORECASE,
    )
    if tag:
        return tag.group(1), tag.group(2)

    # Try without brackets: sourceLineageTag: SchemaName.ObjectName
    tag2 = re.search(
        r"sourceLineageTag:\s*(\w+)\.(\w+)",
        tmdl,
        flags=re.IGNORECASE,
    )
    if tag2:
        return tag2.group(1), tag2.group(2)
    return None
