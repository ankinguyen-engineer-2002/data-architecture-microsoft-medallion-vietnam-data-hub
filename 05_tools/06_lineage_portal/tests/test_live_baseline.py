from __future__ import annotations

from datetime import UTC, datetime
import unittest

from scanner.live_baseline import validate_live_baseline


class LiveBaselineTests(unittest.TestCase):
    def test_validates_timestamped_complete_baseline(self) -> None:
        baseline = {
            "generated_at_utc": "2026-08-03T08:00:00Z",
            "summary": {"view_count": 1, "dependency_edge_count": 1},
            "views": [{
                "database": "SupplyChain_Processing_Warehouse",
                "schema": "ReferenceMaster_Enh_Wrk",
                "object_name": "v_ItemMaster",
                "dependencies": [{"database": "Enterprise_Lakehouse", "schema": "ItemMaster_AFI", "object_name": "ITMRVA"}],
            }],
        }
        result = validate_live_baseline(
            baseline,
            max_age_hours=6,
            now=datetime(2026, 8, 3, 10, tzinfo=UTC),
        )
        self.assertTrue(result["valid"])
        self.assertEqual(result["status"], "valid")

    def test_rejects_stale_or_incomplete_baseline(self) -> None:
        stale = {
            "generated_at_utc": "2026-08-03T01:00:00Z",
            "summary": {"view_count": 1, "dependency_edge_count": 1},
            "views": [{"database": "db", "schema": "s", "object_name": "v", "dependencies": [{"database": "db", "schema": "s", "object_name": "t"}]}],
        }
        self.assertEqual(
            validate_live_baseline(stale, max_age_hours=6, now=datetime(2026, 8, 3, 10, tzinfo=UTC))["status"],
            "stale",
        )
        incomplete = {**stale, "generated_at_utc": "2026-08-03T09:00:00Z", "summary": {"view_count": 2, "dependency_edge_count": 1}}
        self.assertEqual(
            validate_live_baseline(incomplete, max_age_hours=6, now=datetime(2026, 8, 3, 10, tzinfo=UTC))["status"],
            "incomplete",
        )


if __name__ == "__main__":
    unittest.main()
