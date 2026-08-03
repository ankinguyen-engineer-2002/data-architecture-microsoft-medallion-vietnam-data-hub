from __future__ import annotations

import re
from dataclasses import dataclass


KNOWN_DATABASES = {
    "Enterprise_Lakehouse",
    "Source_Data",
    "Wholesale_Warehouse",
    "MasterData_Warehouse",
    "SupplyChain_Warehouse",
    "SupplyChain_Processing_Warehouse",
    "SupplyChain_Gold_Warehouse",
    "ETL_Framework",
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
SOURCE_TWO_PART_RE = re.compile(
    r"\b(?:FROM|JOIN|APPLY)\s+"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"(?!\s*\.)",
    flags=re.IGNORECASE,
)
SQLCMD_DATABASE_RE = re.compile(r"\[?\s*\$\(([^)]+)\)\s*\]?")


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
    sql = re.sub(r"--.*?$", " ", sql, flags=re.MULTILINE)
    return re.sub(r"N?'(?:''|[^'])*'", " ", sql, flags=re.IGNORECASE)


def _part(*values: str | None) -> str:
    return next((v for v in values if v), "")


def extract_object_refs(sql: str, default_database: str | None = None) -> list[ObjectRef]:
    text = SQLCMD_DATABASE_RE.sub(lambda match: f"[{match.group(1)}]", strip_comments(sql))
    refs: set[ObjectRef] = set()
    consumed: list[tuple[int, int]] = []

    for match in THREE_PART_RE.finditer(text):
        db = _part(match.group(1), match.group(2))
        schema = _part(match.group(3), match.group(4))
        obj = _part(match.group(5), match.group(6))
        if (
            db in KNOWN_DATABASES
            and schema.upper() not in SQL_KEYWORDS
            and obj.upper() not in SQL_KEYWORDS
        ):
            refs.add(ObjectRef(db, schema, obj))
            consumed.append(match.span())

    def inside_consumed(start: int, end: int) -> bool:
        return any(start >= a and end <= b for a, b in consumed)

    # Two-part references are accepted only in a table-source position. Parsing
    # every alias.column token created hundreds of false lineage nodes.
    for match in SOURCE_TWO_PART_RE.finditer(text):
        if inside_consumed(*match.span()):
            continue
        schema = _part(match.group(1), match.group(2))
        obj = _part(match.group(3), match.group(4))
        if schema in KNOWN_DATABASES:
            continue
        if schema.upper() in SQL_KEYWORDS or obj.upper() in SQL_KEYWORDS:
            continue
        refs.add(ObjectRef(default_database, schema, obj))

    return sorted(refs)
