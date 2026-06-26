from __future__ import annotations

import re

from .fabric_rest import decode_definition_parts


def extract_semantic_table_sources(definition: dict, model_name: str) -> list[dict[str, str]]:
    parts = decode_definition_parts(definition)
    rows: list[dict[str, str]] = []
    for path, text in parts.items():
        if not path.startswith("definition/tables/") or not path.endswith(".tmdl"):
            continue
        table = path.split("/")[-1].removesuffix(".tmdl")
        source = extract_partition_source(text)
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


def extract_partition_source(tmdl: str) -> tuple[str, str] | None:
    direct_lake = re.search(
        r"entityName:\s*([^\s]+)\s+schemaName:\s*([^\s]+)",
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if direct_lake:
        return direct_lake.group(2).strip("'\""), direct_lake.group(1).strip("'\"")

    schema_item = re.search(
        r'Schema\s*=\s*"([^"]+)"\s*,\s*Item\s*=\s*"([^"]+)"',
        tmdl,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if schema_item:
        return schema_item.group(1), schema_item.group(2)

    bracket = re.search(
        r"\[(Shared_DW|ForecastAccuracy_DW|InventoryHealth_DW)\]\.\[([^\]]+)\]",
        tmdl,
        flags=re.IGNORECASE,
    )
    if bracket:
        return bracket.group(1), bracket.group(2)
    return None
