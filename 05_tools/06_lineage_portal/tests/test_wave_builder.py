from __future__ import annotations

import unittest

from scanner.wave_builder import assign_waves


class WaveBuilderTests(unittest.TestCase):
    def test_assigns_same_layer_topological_waves(self) -> None:
        nodes = [
            {"id": "a", "layer": "Silver"},
            {"id": "b", "layer": "Silver"},
            {"id": "c", "layer": "Silver"},
        ]
        edges = [
            {"source": "a", "target": "b"},
            {"source": "b", "target": "c"},
        ]
        warnings = assign_waves(nodes, edges)
        waves = {node["id"]: node["wave"] for node in nodes}
        self.assertEqual(warnings, [])
        self.assertEqual(waves, {"a": 1, "b": 2, "c": 3})

    def test_preserves_catalog_wave(self) -> None:
        nodes = [
            {"id": "shared_dim", "layer": "Gold", "wave": 1},
            {"id": "fact", "layer": "Gold", "wave": 30},
        ]
        edges = [{"source": "shared_dim", "target": "fact"}]

        warnings = assign_waves(nodes, edges)
        waves = {node["id"]: node["wave"] for node in nodes}

        self.assertEqual(warnings, [])
        self.assertEqual(waves, {"shared_dim": 1, "fact": 30})


if __name__ == "__main__":
    unittest.main()
