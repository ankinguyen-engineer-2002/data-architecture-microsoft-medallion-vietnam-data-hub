from __future__ import annotations

import unittest

from scanner.sql_reader import SqlReader


class FakeProgrammingError(Exception):
    pass


class FakePyodbc:
    ProgrammingError = FakeProgrammingError


class FakeCursor:
    def execute(self, _query: str) -> None:
        raise FakeProgrammingError(
            "The SELECT permission was denied on the object "
            "'sql_expression_dependencies', database 'mssqlsystemresource', schema 'sys'."
        )


class FakeConnection:
    def __enter__(self) -> "FakeConnection":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return FakeCursor()


class SqlReaderTests(unittest.TestCase):
    def test_dependency_permission_denial_uses_baseline_boundary(self) -> None:
        reader = SqlReader.__new__(SqlReader)
        reader._pyodbc = FakePyodbc()
        reader.warnings = []
        reader.connect = lambda _database: FakeConnection()

        rows = reader.fetch_view_dependencies("SupplyChain_Processing_Warehouse")

        self.assertEqual(rows, [])
        self.assertEqual(len(reader.warnings), 1)
        self.assertIn("timestamped live lineage baseline", reader.warnings[0])


if __name__ == "__main__":
    unittest.main()
