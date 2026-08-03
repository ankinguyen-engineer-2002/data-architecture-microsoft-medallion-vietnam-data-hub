from __future__ import annotations

import base64
import unittest

from scanner.semantic_reader import semantic_binding_metadata


def part(path: str, text: str) -> dict[str, str]:
    return {
        "path": path,
        "payload": base64.b64encode(text.encode("utf-8")).decode("ascii"),
        "payloadType": "InlineBase64",
    }


class SemanticReaderTests(unittest.TestCase):
    def test_fourteen_gold_bindings_and_thirteen_calculated_tables_are_complete(self) -> None:
        parts = [
            part(
                f"definition/tables/Gold{i}.tmdl",
                f"entityName: Gold{i} schemaName: Shared_DW",
            )
            for i in range(14)
        ]
        parts.extend(
            part(f"definition/tables/Calculated{i}.tmdl", "table calculatedOnly")
            for i in range(13)
        )
        metadata = semantic_binding_metadata(
            {"definition": {"parts": parts}},
            "sc_control_tower",
            expected_binding_count=14,
            allowed_source_ids={f"Shared_DW.Gold{i}" for i in range(14)},
        )
        self.assertTrue(metadata["complete"])
        self.assertEqual(metadata["binding_count"], 14)
        self.assertEqual(metadata["table_part_count"], 27)
        self.assertEqual(metadata["non_binding_table_count"], 13)

    def test_duplicate_or_unknown_gold_binding_is_incomplete(self) -> None:
        definition = {
            "definition": {
                "parts": [
                    part("definition/tables/A.tmdl", "entityName: Same schemaName: Shared_DW"),
                    part("definition/tables/B.tmdl", "entityName: Same schemaName: Shared_DW"),
                ]
            }
        }
        metadata = semantic_binding_metadata(
            definition,
            "sc_control_tower",
            expected_binding_count=2,
            allowed_source_ids={"Shared_DW.Same"},
        )
        self.assertFalse(metadata["complete"])
        self.assertTrue(metadata["duplicate_source_bindings"])


if __name__ == "__main__":
    unittest.main()
