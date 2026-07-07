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

    def test_runtime_wave_is_authoritative_even_when_dependency_points_later(self) -> None:
        nodes = [
            {"id": "invoice_detail", "layer": "Silver", "wave": 2},
            {"id": "awd_helper", "layer": "Silver", "wave": 3},
        ]
        edges = [{"source": "invoice_detail", "target": "awd_helper"}]

        warnings = assign_waves(nodes, edges)
        waves = {node["id"]: node["wave"] for node in nodes}

        self.assertEqual(warnings, [])
        self.assertEqual(waves, {"invoice_detail": 2, "awd_helper": 3})


if __name__ == "__main__":
    unittest.main()
