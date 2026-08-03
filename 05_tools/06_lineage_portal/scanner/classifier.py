from __future__ import annotations

from typing import Any

from .config import (
    GOLD_DATABASE,
    PROCESSING_DATABASE,
    REPOSITORY_SOURCE_DATABASES,
    SOURCE_DATABASE,
)


FORECAST_SCHEMAS = {
    "ForecastAccuracy_DW",
    "ForecastAccuracy_DW_Wrk",
    "ForecastHistory_Enh",
    "ForecastHistory_Enh_Wrk",
    "OpenOrderHistory_Enh",
    "OpenOrderHistory_Enh_Wrk",
    "SalesHistory_Enh",
    "SalesHistory_Enh_Wrk",
}
INVENTORY_SCHEMAS = {
    "InventoryHealth_DW",
    "InventoryHealth_DW_Wrk",
    "InventoryHistory_Enh",
    "InventoryHistory_Enh_Wrk",
}
SHARED_SCHEMAS = {
    "ReferenceMaster_Enh",
    "ReferenceMaster_Enh_Wrk",
    "Shared_DW",
    "Shared_DW_Wrk",
    "Staging",
    "Staging_Wrk",
}


def classify_layer(database: str, schema: str, object_type: str = "") -> str:
    if database == SOURCE_DATABASE or database in REPOSITORY_SOURCE_DATABASES:
        return "Bronze"
    if database == PROCESSING_DATABASE:
        return "Silver"
    if database == GOLD_DATABASE:
        return "Gold"
    if database == "SemanticModel":
        return "Semantic"
    return "Operational"


def classify_mart(schema: str, object_name: str = "") -> str:
    if schema in FORECAST_SCHEMAS or schema.startswith("Forecast"):
        return "forecast_accuracy"
    if schema in INVENTORY_SCHEMAS or schema.startswith("Inventory"):
        return "inventory_health"
    if schema in SHARED_SCHEMAS:
        return "shared"
    if "Forecast" in object_name:
        return "forecast_accuracy"
    if "Inventory" in object_name or "Vendor" in object_name:
        return "inventory_health"
    return "unresolved"


def stable_node_id(database: str, schema: str, object_name: str) -> str:
    return f"{database}.{schema}.{object_name}"


def tabledict_target_database(schema: str) -> str:
    if schema.endswith("_DW") or schema == "Shared_DW":
        return GOLD_DATABASE
    return PROCESSING_DATABASE


def tabledict_node(row: dict[str, Any]) -> dict[str, Any]:
    schema = str(row.get("SchemaName") or "")
    table = str(row.get("TableName") or "")
    database = tabledict_target_database(schema)
    return {
        "id": stable_node_id(database, schema, table),
        "display_name": table,
        "full_name": stable_node_id(database, schema, table),
        "workspace": "Enterprise SupplyChain-Dev",
        "database": database,
        "schema": schema,
        "object_name": table,
        "object_type": "TABLE",
        "layer": classify_layer(database, schema, "TABLE"),
        "mart": classify_mart(schema, table),
        "wave": None,
        "load_method": row.get("UpdateMethod") or "",
        "source_sql": "",
        "row_count": row.get("RowCount"),
        "last_modified": str(row.get("Modified") or ""),
        "status": "active",
        "evidence": ["ETL_Framework.DW_Developer.TableDictionary"],
    }
