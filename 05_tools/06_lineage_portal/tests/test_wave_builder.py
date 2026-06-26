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
        self.assertEqual(waves, {"a": 0, "b": 1, "c": 2})


if __name__ == "__main__":
    unittest.main()
