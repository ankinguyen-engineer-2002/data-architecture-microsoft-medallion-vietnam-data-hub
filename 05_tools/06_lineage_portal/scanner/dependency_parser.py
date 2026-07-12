from __future__ import annotations

import re
from dataclasses import dataclass


KNOWN_DATABASES = {
    "Enterprise_Lakehouse",
    "SupplyChain_Processing_Warehouse",
    "SupplyChain_Gold_Warehouse",
    "ETL_Framework",
}

KNOWN_SCHEMAS = {
    "DW_Developer",
    "dbo",
    "ForecastAccuracy_DW",
    "ForecastAccuracy_DW_Wrk",
    "ForecastHistory_Enh",
    "ForecastHistory_Enh_Wrk",
    "InventoryHealth_DW",
    "InventoryHealth_DW_Wrk",
    "InventoryHistory_Enh",
    "InventoryHistory_Enh_Wrk",
    "Meta",
    "OpenOrderHistory_Enh",
    "OpenOrderHistory_Enh_Wrk",
    "ProcessingSeed",
    "ReferenceMaster_Enh",
    "ReferenceMaster_Enh_Wrk",
    "SalesHistory_Enh",
    "SalesHistory_Enh_Wrk",
    "Shared_DW",
    "Shared_DW_Wrk",
    "Staging",
    "Staging_Wrk",
}

SQL_KEYWORDS = {
    "AS",
    "BY",
    "CASE",
    "CAST",
    "COALESCE",
    "CONVERT",
    "CROSS",
    "DATEADD",
    "DATEDIFF",
    "FROM",
    "FULL",
    "GROUP",
    "INNER",
    "JOIN",
    "LEFT",
    "NULLIF",
    "ON",
    "OUTER",
    "RIGHT",
    "SELECT",
    "TRIM",
    "UNION",
    "WHERE",
}

THREE_PART_RE = re.compile(
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
)
TWO_PART_RE = re.compile(
    r"(?<!\.)"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
)


@dataclass(frozen=True, order=True)
class ObjectRef:
    database: str | None
    schema: str
    object_name: str

    @property
    def full_name(self) -> str:
        if self.database:
            return f"{self.database}.{self.schema}.{self.object_name}"
        return f"{self.schema}.{self.object_name}"


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    return re.sub(r"--.*?$", " ", sql, flags=re.MULTILINE)


def _part(*values: str | None) -> str:
    return next((v for v in values if v), "")


def extract_object_refs(sql: str, default_database: str | None = None) -> list[ObjectRef]:
    text = strip_comments(sql)
    refs: set[ObjectRef] = set()
    consumed: list[tuple[int, int]] = []

    for match in THREE_PART_RE.finditer(text):
        db = _part(match.group(1), match.group(2))
        schema = _part(match.group(3), match.group(4))
        obj = _part(match.group(5), match.group(6))
        if schema.upper() not in SQL_KEYWORDS and obj.upper() not in SQL_KEYWORDS:
            refs.add(ObjectRef(db, schema, obj))
            consumed.append(match.span())

    def inside_consumed(start: int, end: int) -> bool:
        return any(start >= a and end <= b for a, b in consumed)

    for match in TWO_PART_RE.finditer(text):
        if inside_consumed(*match.span()):
            continue
        schema = _part(match.group(1), match.group(2))
        obj = _part(match.group(3), match.group(4))
        if schema in KNOWN_DATABASES:
            continue
        if schema.upper() in SQL_KEYWORDS or obj.upper() in SQL_KEYWORDS:
            continue
        if schema in KNOWN_SCHEMAS:
            refs.add(ObjectRef(default_database, schema, obj))

    return sorted(refs)
