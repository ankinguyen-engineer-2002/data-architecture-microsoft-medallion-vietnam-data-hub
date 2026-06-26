from __future__ import annotations

import unittest
from pathlib import Path

from scanner.builder import build_snapshot, load_fixture


FIXTURE = Path(__file__).resolve().parent / "fixtures" / "minimal_live_input.json"


class BuilderTests(unittest.TestCase):
    def test_builds_snapshot_from_fixture(self) -> None:
        fixture = load_fixture(FIXTURE)
        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture["semantic_definition"],
            semantic_model_name=fixture["semantic_model_name"],
        )
        node_ids = {node["id"] for node in snapshot["nodes"]}
        edge_keys = {(edge["source"], edge["target"], edge["relationship_type"]) for edge in snapshot["edges"]}
        self.assertIn("Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA", node_ids)
        self.assertIn("SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi", node_ids)
        self.assertIn("SemanticModel.sc_control_tower.FactForecastKpi", node_ids)
        self.assertIn(
            (
                "SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi",
                "SemanticModel.sc_control_tower.FactForecastKpi",
                "semantic_binding",
            ),
            edge_keys,
        )
        self.assertGreaterEqual(len(snapshot["layers"]), 4)


if __name__ == "__main__":
    unittest.main()
