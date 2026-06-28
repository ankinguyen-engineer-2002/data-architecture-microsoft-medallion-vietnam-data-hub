from __future__ import annotations

from collections import defaultdict, deque
from typing import Any


def assign_waves(nodes: list[dict[str, Any]], edges: list[dict[str, Any]]) -> list[str]:
    """Topological wave assignment within each layer (Silver, Gold).

    Catalog explicit waves act as a FLOOR (minimum), never an override.
    Edges always flow from lower wave to higher wave — no same-wave or
    backward dependencies within a layer.
    """
    warnings: list[str] = []
    node_by_id = {node["id"]: node for node in nodes}

    for layer in ("Silver", "Gold"):
        layer_nodes = [n for n in nodes if n.get("layer") == layer]
        ids = {n["id"] for n in layer_nodes}

        # Catalog explicit waves as minimum floor.
        explicit = {n["id"]: int(n["wave"]) for n in layer_nodes if n.get("wave") is not None}

        # Build adjacency for same-layer edges.
        outgoing: dict[str, set[str]] = {nid: set() for nid in ids}
        remaining: dict[str, int] = {nid: 0 for nid in ids}
        for edge in edges:
            src, tgt = edge["source"], edge["target"]
            if src in ids and tgt in ids:
                outgoing[src].add(tgt)
                remaining[tgt] += 1

        # Track the highest wave seen among processed sources for each target.
        max_source_wave: dict[str, int] = {nid: -1 for nid in ids}

        # Kahn's algorithm: start with nodes that have zero remaining dependencies.
        queue = deque(sorted(nid for nid, count in remaining.items() if count == 0))
        processed: set[str] = set()

        while queue:
            src = queue.popleft()
            if src in processed:
                continue
            processed.add(src)

            # Wave = max(floor from catalog, 1 + highest dependency wave).
            wave = max_source_wave.get(src, -1) + 1
            floor = explicit.get(src)
            if floor is not None:
                wave = max(wave, floor)
            node_by_id[src]["wave"] = wave

            for tgt in outgoing[src]:
                max_source_wave[tgt] = max(max_source_wave[tgt], wave)
                remaining[tgt] -= 1
                if remaining[tgt] == 0:
                    queue.append(tgt)

        # Handle cycles or unresolvable nodes.
        unresolved = ids - processed
        if unresolved:
            fallback = max(
                (node_by_id[nid].get("wave") or 0 for nid in processed),
                default=0,
            )
            warnings.append(
                f"{layer} cycle or unresolved same-layer dependency: "
                + ", ".join(sorted(unresolved)[:10])
            )
            for nid in sorted(unresolved):
                fallback = max(max_source_wave.get(nid, -1) + 1, fallback + 1)
                floor = explicit.get(nid)
                if floor is not None:
                    fallback = max(fallback, floor)
                node_by_id[nid]["wave"] = fallback

    return warnings


def layer_summary(nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, int] = defaultdict(int)
    for node in nodes:
        grouped[str(node.get("layer") or "Unknown")] += 1
    return [{"layer": layer, "node_count": count} for layer, count in sorted(grouped.items())]


def mart_summary(nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, int] = defaultdict(int)
    for node in nodes:
        grouped[str(node.get("mart") or "unresolved")] += 1
    return [{"mart": mart, "node_count": count} for mart, count in sorted(grouped.items())]
