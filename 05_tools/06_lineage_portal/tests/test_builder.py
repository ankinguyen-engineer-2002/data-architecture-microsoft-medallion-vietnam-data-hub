from __future__ import annotations

import copy
import unittest
from pathlib import Path

from scanner.builder import build_snapshot, load_fixture
from scanner.mart_catalog import load_mart_catalog
from scanner.snapshot_writer import sanitize_snapshot_source_sql


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
        self.assertIn(
            (
                "SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi",
                "SemanticModel.sc_control_tower.Model",
                "feeds_semantic",
            ),
            edge_keys,
        )
        self.assertGreaterEqual(len(snapshot["layers"]), 4)
        self.assertTrue(snapshot["semantic_validation"]["complete"])
        self.assertTrue(all(not node["source_sql"] for node in snapshot["nodes"]))
        self.assertTrue(
            any(node.get("source_sql_sha256") for node in snapshot["nodes"]),
            "public snapshots retain module hashes but never raw SQL",
        )

    def test_compares_live_edges_with_repository_target(self) -> None:
        fixture = load_fixture(FIXTURE)
        repository_manifest = {
            "repository": "afi-internal/data-edw-fabric",
            "commit_sha": "7282973e4fdad2464907ca0ea4b3f3d43b1a5f31",
            "pull_request": 694,
            "generated_at_utc": "2026-08-03T08:00:00Z",
            "summary": {"view_count": 2, "procedure_count": 14, "table_count": 51},
            "views": [
                {
                    "database": "SupplyChain_Processing_Warehouse",
                    "schema": "ReferenceMaster_Enh_Wrk",
                    "object_name": "v_ItemMaster",
                    "path": "SupplyChain_Processing_Warehouse/ReferenceMaster_Enh_Wrk/Views/v_ItemMaster.sql",
                    "target": {
                        "database": "SupplyChain_Processing_Warehouse",
                        "schema": "ReferenceMaster_Enh",
                        "object_name": "ItemMaster",
                    },
                    "dependencies": [
                        {
                            "database": "Source_Data",
                            "schema": "MasterData_ItemMaster_AFI",
                            "object_name": "ITMRVA",
                        }
                    ],
                },
                {
                    "database": "SupplyChain_Gold_Warehouse",
                    "schema": "ForecastAccuracy_DW_Wrk",
                    "object_name": "v_FactForecastKpi",
                    "path": "SupplyChain_Gold_Warehouse/ForecastAccuracy_DW_Wrk/Views/v_FactForecastKpi.sql",
                    "target": {
                        "database": "SupplyChain_Gold_Warehouse",
                        "schema": "ForecastAccuracy_DW",
                        "object_name": "FactForecastKpi",
                    },
                    "dependencies": [
                        {
                            "database": "SupplyChain_Processing_Warehouse",
                            "schema": "ForecastHistory_Enh",
                            "object_name": "ForecastDemandMonthly",
                        }
                    ],
                },
            ],
        }

        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture["semantic_definition"],
            semantic_model_name=fixture["semantic_model_name"],
            repository_manifest=repository_manifest,
        )

        statuses = {
            (edge["source"], edge["target"], edge["provenance"]): edge["sync_status"]
            for edge in snapshot["edges"]
        }
        self.assertEqual(
            statuses[
                (
                    "SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly",
                    "SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi",
                    "live+repository_target",
                )
            ],
            "aligned",
        )
        self.assertEqual(
            statuses[
                (
                    "Source_Data.MasterData_ItemMaster_AFI.ITMRVA",
                    "SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ItemMaster",
                    "repository_target",
                )
            ],
            "drift",
        )
        self.assertEqual(snapshot["repository"]["pull_request"], 694)

    def test_uses_timestamped_live_baseline_when_module_metadata_is_unavailable(self) -> None:
        fixture = copy.deepcopy(load_fixture(FIXTURE))
        for rows in fixture["sql_scan"]["modules"].values():
            for row in rows:
                row["definition"] = None
        live_baseline = {
            "generated_at_utc": "2026-08-03T08:13:10Z",
            "summary": {"view_count": 1, "dependency_edge_count": 1},
            "views": [
                {
                    "database": "SupplyChain_Processing_Warehouse",
                    "schema": "ReferenceMaster_Enh_Wrk",
                    "object_name": "v_ItemMaster",
                    "dependencies": [
                        {
                            "database": "Enterprise_Lakehouse",
                            "schema": "ItemMaster_AFI",
                            "object_name": "ITMRVA",
                        }
                    ],
                }
            ],
        }

        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture["semantic_definition"],
            semantic_model_name=fixture["semantic_model_name"],
            live_baseline=live_baseline,
        )

        self.assertEqual(snapshot["scan_evidence"]["live_baseline_view_count"], 1)
        self.assertTrue(any("baseline" in warning for warning in snapshot["warnings"]))

    def test_catalog_snapshot_hides_work_view_nodes(self) -> None:
        fixture = load_fixture(FIXTURE)
        repo_root = Path(__file__).resolve().parents[3]
        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture["semantic_definition"],
            semantic_model_name=fixture["semantic_model_name"],
            mart_catalog=load_mart_catalog(repo_root),
        )

        visible_views = [
            node
            for node in snapshot["nodes"]
            if node["schema"].endswith("_Wrk") or node["object_name"].startswith("v_")
        ]

        self.assertFalse(
            any(node["object_type"].lower() == "semantic_artifact" for node in snapshot["nodes"])
        )
        self.assertFalse(any(not node["schema"] for node in snapshot["nodes"]))
        self.assertTrue(visible_views)
        self.assertTrue(all(node["schema"] == "Staging_Wrk" for node in visible_views))
        self.assertIn(
            (
                "Enterprise_Lakehouse.SupplyChain_Enh.CurFcstSnapshotWeekly",
                "SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly",
                "transforms_to",
            ),
            {(edge["source"], edge["target"], edge["relationship_type"]) for edge in snapshot["edges"]},
        )

    def test_semantic_source_missing_from_catalog_is_added_before_binding(self) -> None:
        fixture = load_fixture(FIXTURE)
        fixture["sql_scan"]["objects"]["SupplyChain_Gold_Warehouse"].append(
            {
                "database_name": "SupplyChain_Gold_Warehouse",
                "schema_name": "ForecastAccuracy_DW",
                "object_name": "OrphanGoldTable",
                "type_desc": "USER_TABLE",
                "modify_date": "2026-06-25T00:00:00",
            }
        )
        fixture["semantic_definition"] = {
            "definition": {
                "parts": [
                    {
                        "path": "definition/tables/OrphanSemanticTable.tmdl",
                        "payload": "ZW50aXR5TmFtZTogT3JwaGFuR29sZFRhYmxlIHNjaGVtYU5hbWU6IEZvcmVjYXN0QWNjdXJhY3lfRFc=",
                        "payloadType": "InlineBase64",
                    }
                ]
            }
        }
        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture["semantic_definition"],
            semantic_model_name=fixture["semantic_model_name"],
        )
        node_ids = {node["id"] for node in snapshot["nodes"]}
        self.assertIn("SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.OrphanGoldTable", node_ids)
        self.assertTrue(
            all(edge["source"] in node_ids and edge["target"] in node_ids for edge in snapshot["edges"])
        )

    def test_incomplete_semantic_definition_emits_no_unverified_bindings(self) -> None:
        fixture = load_fixture(FIXTURE)
        snapshot = build_snapshot(
            workspace_id=fixture["workspace"]["id"],
            workspace_name=fixture["workspace"]["name"],
            workspace_items=fixture["workspace_items"],
            sql_scan=fixture["sql_scan"],
            semantic_definition=None,
            semantic_model_name=fixture["semantic_model_name"],
            semantic_expected_binding_count=14,
            semantic_failure_reason="permission denied",
        )
        self.assertFalse(snapshot["semantic_validation"]["complete"])
        self.assertEqual(snapshot["semantic_validation"]["status"], "unavailable")
        self.assertFalse(any(edge["relationship_type"] == "feeds_semantic" for edge in snapshot["edges"]))

    def test_legacy_snapshot_sanitizer_removes_raw_sql(self) -> None:
        path = Path(self._testMethodName + ".json")
        try:
            path.write_text('{"nodes":[{"source_sql":"SELECT secret_free_sql"}]}', encoding="utf-8")
            self.assertEqual(sanitize_snapshot_source_sql(path), 1)
            sanitized = load_fixture(path)
            self.assertEqual(sanitized["nodes"][0]["source_sql"], "")
            self.assertTrue(sanitized["nodes"][0]["source_sql_sha256"])
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
