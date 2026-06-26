from __future__ import annotations

from collections import defaultdict, deque
from typing import Any


def assign_waves(nodes: list[dict[str, Any]], edges: list[dict[str, Any]]) -> list[str]:
    warnings: list[str] = []
    node_by_id = {node["id"]: node for node in nodes}

    for layer in ("Silver", "Gold"):
        layer_nodes = [n for n in nodes if n.get("layer") == layer]
        ids = {n["id"] for n in layer_nodes}
        explicit = {n["id"]: int(n["wave"]) for n in layer_nodes if n.get("wave") is not None}
        for node in layer_nodes:
            if node.get("wave") is None:
                node["wave"] = 0
        incoming: dict[str, set[str]] = {node_id: set() for node_id in ids}
        outgoing: dict[str, set[str]] = {node_id: set() for node_id in ids}
        for edge in edges:
            source = edge["source"]
            target = edge["target"]
            if source in ids and target in ids:
                incoming[target].add(source)
                outgoing[source].add(target)

        queue = deque(sorted({node_id for node_id, deps in incoming.items() if not deps} | set(explicit)))
        assigned: dict[str, int] = {node_id: explicit.get(node_id, 0) for node_id in queue}
        processed: set[str] = set()
        while queue:
            source = queue.popleft()
            if source in processed:
                continue
            processed.add(source)
            for target in outgoing[source]:
                incoming[target].discard(source)
                if target in explicit:
                    assigned[target] = explicit[target]
                else:
                    assigned[target] = max(assigned.get(target, 0), assigned[source] + 1)
                if not incoming[target]:
                    queue.append(target)

        if len(assigned) != len(ids):
            unresolved = sorted(ids - set(assigned))
            warnings.append(f"{layer} cycle or unresolved same-layer dependency: {', '.join(unresolved)}")
            for node_id in unresolved:
                assigned[node_id] = max(assigned.values(), default=0) + 1

        for node_id, wave in assigned.items():
            node_by_id[node_id]["wave"] = wave

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
