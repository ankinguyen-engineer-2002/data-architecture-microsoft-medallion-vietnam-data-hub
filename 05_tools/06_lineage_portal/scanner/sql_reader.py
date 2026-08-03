from __future__ import annotations

import struct
from typing import Any

from .config import ETL_DATABASE, GOLD_DATABASE, PROCESSING_DATABASE, SOURCE_DATABASE


SQL_COPT_SS_ACCESS_TOKEN = 1256


def token_attr(access_token: str) -> bytes:
    raw = access_token.encode("UTF-16-LE")
    return struct.pack(f"<I{len(raw)}s", len(raw), raw)


class SqlReader:
    def __init__(self, server: str, access_token: str) -> None:
        import pyodbc

        self._pyodbc = pyodbc
        self.server = server
        self.token = token_attr(access_token)
        self.warnings: list[str] = []

    def connect(self, database: str):
        return self._pyodbc.connect(
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={self.server};DATABASE={database};"
            "Encrypt=yes;TrustServerCertificate=no;",
            attrs_before={SQL_COPT_SS_ACCESS_TOKEN: self.token},
            timeout=120,
            autocommit=True,
        )

    @staticmethod
    def rows_as_dicts(cur) -> list[dict[str, Any]]:
        columns = [desc[0] for desc in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]

    def fetch_objects(self, database: str) -> list[dict[str, Any]]:
        with self.connect(database) as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT
                    DB_NAME() AS database_name,
                    s.name AS schema_name,
                    o.name AS object_name,
                    o.type_desc,
                    CONVERT(varchar(33), o.modify_date, 126) AS modify_date
                FROM sys.objects o
                JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE o.is_ms_shipped = 0
                  AND o.type IN ('U','V','P')
                ORDER BY s.name, o.name
                """
            )
            return self.rows_as_dicts(cur)

    def fetch_view_modules(self, database: str) -> list[dict[str, Any]]:
        with self.connect(database) as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT
                    DB_NAME() AS database_name,
                    s.name AS schema_name,
                    o.name AS object_name,
                    o.type_desc,
                    m.definition
                FROM sys.sql_modules m
                JOIN sys.objects o ON o.object_id = m.object_id
                JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE o.is_ms_shipped = 0
                  AND o.type IN ('V','P')
                ORDER BY s.name, o.name
                """
            )
            return self.rows_as_dicts(cur)

    def fetch_view_dependencies(self, database: str) -> list[dict[str, Any]]:
        with self.connect(database) as conn:
            cur = conn.cursor()
            try:
                cur.execute(
                    """
                    SELECT
                        DB_NAME() AS database_name,
                        s.name AS referencing_schema_name,
                        o.name AS referencing_object_name,
                        COALESCE(d.referenced_database_name, DB_NAME()) AS referenced_database_name,
                        d.referenced_schema_name,
                        d.referenced_entity_name AS referenced_object_name
                    FROM sys.sql_expression_dependencies d
                    JOIN sys.objects o ON o.object_id = d.referencing_id
                    JOIN sys.schemas s ON s.schema_id = o.schema_id
                    WHERE o.is_ms_shipped = 0
                      AND o.type = 'V'
                      AND d.referenced_schema_name IS NOT NULL
                      AND d.referenced_entity_name IS NOT NULL
                    ORDER BY s.name, o.name, referenced_database_name,
                             d.referenced_schema_name, d.referenced_entity_name
                    """
                )
            except self._pyodbc.ProgrammingError as exc:
                message = str(exc)
                if "sql_expression_dependencies" not in message or "permission was denied" not in message.lower():
                    raise
                self.warnings.append(
                    f"{database}: current sys.sql_expression_dependencies is not readable; "
                    "using the timestamped live lineage baseline."
                )
                return []
            return self.rows_as_dicts(cur)

    def fetch_table_dictionary(self) -> list[dict[str, Any]]:
        with self.connect(ETL_DATABASE) as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT
                    SchemaName,
                    TableName,
                    ReplicatedSource,
                    UpdateMethod,
                    DateKey,
                    DateRangeDays,
                    Modified,
                    [RowCount] AS [RowCount]
                FROM DW_Developer.TableDictionary
                ORDER BY SchemaName, TableName
                """
            )
            return self.rows_as_dicts(cur)

    def scan_all(self) -> dict[str, Any]:
        return {
            "table_dictionary": self.fetch_table_dictionary(),
            "objects": {
                ETL_DATABASE: self.fetch_objects(ETL_DATABASE),
                PROCESSING_DATABASE: self.fetch_objects(PROCESSING_DATABASE),
                GOLD_DATABASE: self.fetch_objects(GOLD_DATABASE),
                SOURCE_DATABASE: self.fetch_objects(SOURCE_DATABASE),
            },
            "modules": {
                PROCESSING_DATABASE: self.fetch_view_modules(PROCESSING_DATABASE),
                GOLD_DATABASE: self.fetch_view_modules(GOLD_DATABASE),
            },
            "dependencies": {
                PROCESSING_DATABASE: self.fetch_view_dependencies(PROCESSING_DATABASE),
                GOLD_DATABASE: self.fetch_view_dependencies(GOLD_DATABASE),
            },
            "warnings": self.warnings,
        }
