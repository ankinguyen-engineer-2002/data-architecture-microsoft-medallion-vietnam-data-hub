from __future__ import annotations

import unittest

from scanner.classifier import classify_layer, classify_mart, tabledict_target_database


class ClassifierTests(unittest.TestCase):
    def test_classifies_layers(self) -> None:
        self.assertEqual(classify_layer("Enterprise_Lakehouse", "Anything"), "Bronze")
        self.assertEqual(classify_layer("SupplyChain_Processing_Warehouse", "ReferenceMaster_Enh"), "Silver")
        self.assertEqual(classify_layer("SupplyChain_Gold_Warehouse", "ForecastAccuracy_DW"), "Gold")
        self.assertEqual(classify_layer("SemanticModel", "sc_control_tower"), "Semantic")

    def test_classifies_known_marts(self) -> None:
        self.assertEqual(classify_mart("ForecastAccuracy_DW", "FactForecastKpi"), "forecast_accuracy")
        self.assertEqual(classify_mart("InventoryHealth_DW", "FactInventoryHealthSnapshot"), "inventory_health")
        self.assertEqual(classify_mart("Shared_DW", "DimProduct"), "shared")

    def test_tabledict_target_database(self) -> None:
        self.assertEqual(tabledict_target_database("ForecastAccuracy_DW"), "SupplyChain_Gold_Warehouse")
        self.assertEqual(tabledict_target_database("ReferenceMaster_Enh"), "SupplyChain_Processing_Warehouse")


if __name__ == "__main__":
    unittest.main()
