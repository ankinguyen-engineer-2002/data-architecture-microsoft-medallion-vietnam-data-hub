import json
import tempfile
import unittest
from pathlib import Path

from scanner.mart_catalog import load_mart_catalog


class MartCatalogTests(unittest.TestCase):
    def test_discovers_marts_and_excludes_support_from_business_filter(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            catalog_dir = root / "02_marts" / "new_mart" / "05_catalog"
            catalog_dir.mkdir(parents=True)
            (catalog_dir / "assets.json").write_text(
                json.dumps(
                    {
                        "assets": [
                            {
                                "display": "NewMart_DW.FactNewMetric",
                                "schema": "NewMart_DW",
                                "object": "FactNewMetric",
                                "layer": "gold",
                                "mart": "new_mart",
                            },
                            {
                                "display": "Shared_DW.DimProduct",
                                "schema": "Shared_DW",
                                "object": "DimProduct",
                                "layer": "gold",
                                "mart": "new_mart",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            (catalog_dir / "run_order.json").write_text(
                json.dumps(
                    {
                        "mart": "new_mart",
                        "sequence": [
                            {"object": "NewMart_DW.FactNewMetric", "wave": "gold_fact", "step": 500},
                            {"object": "Shared_DW.DimProduct", "wave": "gold_shared", "step": 100},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            catalog = load_mart_catalog(root)

        self.assertEqual([mart["id"] for mart in catalog.business_marts], ["new_mart"])
        self.assertEqual(catalog.classify_object("NewMart_DW", "FactNewMetric"), "new_mart")
        self.assertEqual(catalog.role_for("Shared_DW", "DimProduct", "new_mart"), "support")
        self.assertEqual(catalog.wave_for("NewMart_DW", "FactNewMetric"), 30)
        self.assertEqual(catalog.wave_for("Shared_DW", "DimProduct"), 1)

    def test_wildcard_run_order_applies_wave_to_matching_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            catalog_dir = root / "02_marts" / "inventory_health" / "05_catalog"
            catalog_dir.mkdir(parents=True)
            (catalog_dir / "assets.json").write_text(
                json.dumps(
                    {
                        "assets": [
                            {
                                "display": "ReferenceMaster_Enh.Calendar",
                                "schema": "ReferenceMaster_Enh",
                                "object": "Calendar",
                                "layer": "silver",
                                "mart": "inventory_health",
                            },
                            {
                                "display": "ReferenceMaster_Enh.Warehouse",
                                "schema": "ReferenceMaster_Enh",
                                "object": "Warehouse",
                                "layer": "silver",
                                "mart": "inventory_health",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            (catalog_dir / "run_order.json").write_text(
                json.dumps(
                    {
                        "mart": "inventory_health",
                        "sequence": [
                            {"object": "ReferenceMaster_Enh.*", "wave": 1, "step": 90},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            catalog = load_mart_catalog(root)

        self.assertEqual(catalog.wave_for("ReferenceMaster_Enh", "Calendar"), 1)
        self.assertEqual(catalog.wave_for("ReferenceMaster_Enh", "Warehouse"), 1)


if __name__ == "__main__":
    unittest.main()
