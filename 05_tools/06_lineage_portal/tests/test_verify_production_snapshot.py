from __future__ import annotations

import unittest
from datetime import UTC, datetime

from scanner.verify_production_snapshot import validate_snapshot


NOW = datetime(2026, 8, 3, 9, 0, tzinfo=UTC)
SHA = "7282973e4fdad2464907ca0ea4b3f3d43b1a5f31"
WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
WORKSPACE_NAME = "Enterprise SupplyChain-Dev"


def snapshot(*, baseline_used: int = 0, baseline_time: str = "2026-08-03T08:00:00Z", semantic: bool = True) -> dict:
    edges = [{"relationship_type": "feeds_semantic", "confidence": "verified"} for _ in range(14)] if semantic else []
    return {
        "generated_at_utc": "2026-08-03T08:00:00Z",
        "workspace": {"id": WORKSPACE_ID, "name": WORKSPACE_NAME},
        "repository": {"commit_sha": SHA, "pull_request": 694},
        "edges": edges,
        "warnings": [],
        "semantic_validation": {
            "complete": semantic,
            "definition_read": semantic,
            "binding_count": 14 if semantic else 0,
        },
        "scan_evidence": {
            "live_dependency_row_count": 203 if not baseline_used else 0,
            "live_baseline_view_count": baseline_used,
        },
        "live_baseline": {
            "generated_at_utc": baseline_time,
            "summary": {"dependency_edge_count": 203},
        },
    }


class ProductionSnapshotGateTests(unittest.TestCase):
    def validate(self, data: dict) -> list[str]:
        return validate_snapshot(
            data,
            expected_manifest_sha=SHA,
            expected_pull_request=694,
            expected_workspace_id=WORKSPACE_ID,
            expected_workspace_name=WORKSPACE_NAME,
            baseline_max_age_hours=6,
            expected_baseline_view_count=50,
            now=NOW,
        )

    def test_accepts_current_live_dependencies(self) -> None:
        self.assertEqual(self.validate(snapshot()), [])

    def test_accepts_only_fresh_complete_baseline(self) -> None:
        self.assertEqual(self.validate(snapshot(baseline_used=50)), [])

    def test_rejects_stale_or_partial_baseline(self) -> None:
        errors = self.validate(snapshot(baseline_used=49, baseline_time="2026-08-03T01:00:00Z"))
        self.assertTrue(any("older" in error for error in errors))
        self.assertTrue(any("incomplete" in error for error in errors))

    def test_rejects_missing_semantic_lineage_and_manifest_drift(self) -> None:
        data = snapshot(semantic=False)
        data["repository"]["commit_sha"] = "wrong"
        errors = self.validate(data)
        self.assertTrue(any("semantic" in error for error in errors))
        self.assertTrue(any("SHA" in error for error in errors))

    def test_rejects_wrong_semantic_edge_shape(self) -> None:
        data = snapshot()
        data["semantic_validation"]["binding_count"] = 13
        data["edges"][0]["confidence"] = "parsed"
        data["warnings"] = ["Semantic lineage is incomplete: missing definition."]
        errors = self.validate(data)
        self.assertTrue(any("14 bindings" in error for error in errors))
        self.assertTrue(any("verified confidence" in error for error in errors))
        self.assertTrue(any("incomplete semantic" in error for error in errors))

    def test_rejects_stale_snapshot_or_wrong_workspace(self) -> None:
        data = snapshot()
        data["generated_at_utc"] = "2026-08-03T01:00:00Z"
        data["workspace"]["name"] = "wrong workspace"
        errors = self.validate(data)
        self.assertTrue(any("snapshot is older" in error for error in errors))
        self.assertTrue(any("workspace name" in error for error in errors))

    def test_rejects_public_raw_sql(self) -> None:
        data = snapshot()
        data["nodes"] = [{"id": "Warehouse.Schema.View", "source_sql": "SELECT 1"}]
        self.assertTrue(any("source_sql" in error for error in self.validate(data)))


if __name__ == "__main__":
    unittest.main()
