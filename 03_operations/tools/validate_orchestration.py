#!/usr/bin/env python3
"""Orchestration validation, SP generation, and cross-mart deadlock detection.

Uses the lineage snapshot JSON (pre-built by scanner with topological waves)
to:
  1. Validate that SP wrapper EXEC order respects dependencies.
  2. Auto-generate SP wrapper SQL from dependency graph.
  3. Detect cross-mart cycles and suggest optimal execution order.

Usage:
  python3 validate_orchestration.py --snapshot <path>  [--validate] [--generate] [--cross-mart]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]


# ── Graph building ──

def load_graph(snapshot_path: Path) -> tuple[dict[str, Any], dict[str, Any], list[dict], list[dict]]:
    """Return (node_by_id, id_by_key, nodes, edges) from snapshot."""
    snap = json.loads(snapshot_path.read_text(encoding="utf-8"))
    nodes = snap["nodes"]
    edges = snap["edges"]
    node_by_id = {n["id"]: n for n in nodes}
    id_by_key: dict[str, str] = {}
    for n in nodes:
        key = f"{n.get('schema','')}.{n.get('object_name','')}"
        id_by_key[key] = n["id"]
    return node_by_id, id_by_key, nodes, edges


def build_dependency_graph(
    nodes: list[dict], edges: list[dict], node_by_id: dict, layer: str | None = None
) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """Build adjacency: {node_key: {dependencies}} and reverse {node_key: {dependents}}.

    Only includes business/support nodes within the given layer (or all if None).
    """
    deps: dict[str, set[str]] = defaultdict(set)  # key -> {keys it depends on}
    rdeps: dict[str, set[str]] = defaultdict(set)  # key -> {keys that depend on it}

    for edge in edges:
        src = node_by_id.get(edge["source"])
        tgt = node_by_id.get(edge["target"])
        if not src or not tgt:
            continue
        if src.get("role") not in ("business", "support"):
            continue
        if tgt.get("role") not in ("business", "support"):
            continue
        if layer and (src.get("layer") != layer or tgt.get("layer") != layer):
            continue

        src_key = f"{src['schema']}.{src['object_name']}"
        tgt_key = f"{tgt['schema']}.{tgt['object_name']}"
        deps[tgt_key].add(src_key)
        rdeps[src_key].add(tgt_key)

    return dict(deps), dict(rdeps)


def topological_sort(deps: dict[str, set[str]]) -> list[list[str]]:
    """Kahn's algorithm: return list of wave groups (each group is independent)."""
    remaining = {k: len(v) for k, v in deps.items()}
    # Also include nodes that are only sources (in rdeps but not deps)
    all_nodes = set(deps.keys())
    for v in deps.values():
        all_nodes.update(v)
    for n in all_nodes:
        if n not in remaining:
            remaining[n] = 0

    waves: list[list[str]] = []
    processed: set[str] = set()

    while True:
        wave = sorted(n for n, c in remaining.items() if c == 0 and n not in processed)
        if not wave:
            break
        waves.append(wave)
        for n in wave:
            processed.add(n)
            # This node being processed doesn't reduce remaining directly
            # in the simple Kahn's; we need to track rdeps
        # Recalculate remaining for next wave
        for n in wave:
            for dependent in rdeps.get(n, set()):
                if dependent in remaining:
                    remaining[dependent] = max(0, remaining[dependent] - 1)
        # Actually, Kahn's is: remove node, decrease remaining of its dependents
        # Let me fix this properly

    # Actually let me redo this properly
    return _kahn_sort(deps, rdeps)


def _kahn_sort(deps: dict[str, set[str]], rdeps: dict[str, set[str]]) -> list[list[str]]:
    """Proper Kahn's algorithm returning wave groups."""
    # Build complete node set
    all_nodes = set(deps.keys())
    for v in deps.values():
        all_nodes.update(v)
    for n in list(rdeps.keys()):
        all_nodes.add(n)
    for v in rdeps.values():
        all_nodes.update(v)

    # remaining = indegree
    indegree: dict[str, int] = {}
    for n in all_nodes:
        indegree[n] = len(deps.get(n, set()))

    queue = deque(sorted(n for n, c in indegree.items() if c == 0))
    waves: list[list[str]] = []
    processed: set[str] = set()

    while queue:
        wave = []
        for _ in range(len(queue)):
            n = queue.popleft()
            if n in processed:
                continue
            processed.add(n)
            wave.append(n)

        if wave:
            waves.append(wave)

        # Decrease indegree of dependents
        for n in wave:
            for dep in rdeps.get(n, set()):
                if dep in indegree:
                    indegree[dep] -= 1
                    if indegree[dep] == 0:
                        queue.append(dep)

    # Unresolved = cycle
    unresolved = sorted(all_nodes - processed)
    if unresolved:
        waves.append([f"CYCLE:{x}" for x in unresolved])

    return waves


# ── Validation ──

def parse_sp_order(sp_sql: str) -> list[str]:
    """Extract ordered table list from SP wrapper SQL."""
    import re
    tables = []
    for line in sp_sql.split("\n"):
        m = re.search(r"usp_RefreshCuratedTableFromView\s+'[^']+',\s*'([^']+)',\s*'([^']+)'", line)
        if m:
            tables.append(f"{m.group(1)}.{m.group(2)}")
        m2 = re.search(r"usp_IncrementalTableLoad\s+'[^']+',\s*'([^']+)',\s*'([^']+)'", line)
        if m2:
            tables.append(f"{m2.group(1)}.{m2.group(2)}")
    return tables


def validate_sp_order(sp_name: str, sp_tables: list[str], deps: dict[str, set[str]]) -> list[str]:
    """Check that tables in SP are in topological order. Returns list of violations."""
    violations = []
    table_positions = {t: i for i, t in enumerate(sp_tables)}

    for tgt, src_set in deps.items():
        if tgt not in table_positions:
            continue
        for src in src_set:
            if src not in table_positions:
                continue
            if table_positions[src] >= table_positions[tgt]:
                violations.append(
                    f"  {sp_name}: [{src}] (pos {table_positions[src]}) called before "
                    f"[{tgt}] (pos {table_positions[tgt]}) but [{tgt}] depends on [{src}]. "
                    f"Move [{src}] before [{tgt}]."
                )

    return violations


# ── SP Generation ──

def generate_sp_sql(
    mart: str,
    database: str,
    procedure_name: str,
    layer: str,
    tables_by_wave: list[list[tuple[str, str, str]]],
) -> str:
    """Generate CREATE OR ALTER PROCEDURE SQL.

    tables_by_wave: list of waves, each wave is list of (schema, table, load_method)
    """
    lines = [
        f"-- Target database: {database}",
        f"-- Mart: {mart}",
        f"-- Auto-generated from topological dependency graph.",
        f"-- Wave order: Kahn's algorithm — catalog wave = floor, deps push upward.",
        f"CREATE OR ALTER PROCEDURE [dbo].[{procedure_name}]",
        f"AS",
        f"BEGIN",
        f"    SET NOCOUNT ON;",
        f"",
    ]

    for wave_idx, tables in enumerate(tables_by_wave):
        if not tables:
            continue
        lines.append(f"    -- {layer} Wave {wave_idx:02d}")
        for schema, table, method in tables:
            if "incremental" in method.lower():
                lines.append(
                    f"    EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]"
                    f" '{database}', '{schema}', '{table}', 'NULL';"
                )
            else:
                lines.append(
                    f"    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]"
                    f" '{database}', '{schema}', '{table}';"
                )
            lines.append("")

    lines.append("END;")
    return "\n".join(lines)


# ── Cross-mart Detection ──

def detect_cross_mart_issues(
    deps: dict[str, set[str]],
    node_mart: dict[str, str],
) -> list[str]:
    """Detect cross-mart dependency issues and suggest optimal order."""
    issues = []

    # Find cross-mart dependencies
    cross = []
    for tgt, src_set in deps.items():
        tgt_mart = node_mart.get(tgt, "?")
        for src in src_set:
            src_mart = node_mart.get(src, "?")
            if src_mart != tgt_mart and src_mart != "?" and tgt_mart != "?":
                cross.append((src, src_mart, tgt, tgt_mart))

    if cross:
        issues.append(f"  Cross-mart dependencies found: {len(cross)}")
        for src, sm, tgt, tm in cross:
            issues.append(f"    [{sm}] {src} → [{tm}] {tgt}")

    # Build mart-level dependency graph
    mart_deps: dict[str, set[str]] = defaultdict(set)
    for tgt, src_set in deps.items():
        tgt_mart = node_mart.get(tgt, "?")
        for src in src_set:
            src_mart = node_mart.get(src, "?")
            if src_mart != tgt_mart and src_mart != "?" and tgt_mart != "?":
                mart_deps[tgt_mart].add(src_mart)

    # Kahn's on marts
    all_marts = set(mart_deps.keys())
    for v in mart_deps.values():
        all_marts.update(v)

    indegree = {m: len(mart_deps.get(m, set())) for m in all_marts}
    queue = deque(sorted(m for m, c in indegree.items() if c == 0))
    order = []
    while queue:
        m = queue.popleft()
        order.append(m)
        for dependent in list(all_marts):
            if m in mart_deps.get(dependent, set()):
                indegree[dependent] -= 1
                if indegree[dependent] == 0:
                    queue.append(dependent)

    if len(order) < len(all_marts):
        issues.append(f"  ⚠ CYCLE detected in mart-level dependency graph!")
        issues.append(f"    Unresolved: {sorted(all_marts - set(order))}")

    issues.append(f"  Suggested mart execution order: {' → '.join(order)}")
    return issues


# ── Main ──

def main() -> int:
    parser = argparse.ArgumentParser(description="Orchestration validation, SP generation, cross-mart detection.")
    parser.add_argument("--snapshot", type=Path, required=True, help="Lineage snapshot JSON from scanner.")
    parser.add_argument("--validate", action="store_true", help="Validate SP wrapper order against dependency graph.")
    parser.add_argument("--generate", action="store_true", help="Generate SP wrapper SQL from dependency graph.")
    parser.add_argument("--cross-mart", action="store_true", help="Detect cross-mart cycles and suggest order.")
    parser.add_argument("--all", action="store_true", help="Run all checks.")
    args = parser.parse_args()

    if not any([args.validate, args.generate, args.cross_mart, args.all]):
        parser.print_help()
        return 1

    run_validate = args.validate or args.all
    run_generate = args.generate or args.all
    run_cross = args.cross_mart or args.all

    print("=" * 90)
    print("  ORCHESTRATION VALIDATION & GENERATION")
    print(f"  Snapshot: {args.snapshot}")
    print("=" * 90)

    node_by_id, id_by_key, nodes, edges = load_graph(args.snapshot)

    # Build dependency graphs per layer
    silver_deps, silver_rdeps = build_dependency_graph(nodes, edges, node_by_id, "Silver")
    gold_deps, gold_rdeps = build_dependency_graph(nodes, edges, node_by_id, "Gold")

    # Layer for a key
    node_layer: dict[str, str] = {}
    node_mart: dict[str, str] = {}
    for n in nodes:
        key = f"{n.get('schema','')}.{n.get('object_name','')}"
        node_layer[key] = n.get("layer", "?")
        node_mart[key] = n.get("mart", "?")

    all_deps = {}
    all_deps.update(silver_deps)
    all_deps.update(gold_deps)
    all_rdeps = {}
    all_rdeps.update(silver_rdeps)
    all_rdeps.update(gold_rdeps)

    # ── Validate ──
    if run_validate:
        print(f"\n{'─' * 60}")
        print("  1. PRE-FLIGHT VALIDATION")
        print(f"{'─' * 60}")

        # Find SP files in orchestration folder
        orch_dir = REPO_ROOT / "03_operations" / "orchestration"
        violations_all: list[str] = []

        for sp_file in sorted(orch_dir.rglob("*.sql")):
            sp_name = sp_file.name.replace(".sql", "")
            sp_sql = sp_file.read_text(encoding="utf-8")
            tables = parse_sp_order(sp_sql)
            if not tables:
                continue

            layer = "Silver" if "Silver" in sp_name else "Gold"
            deps = silver_deps if layer == "Silver" else gold_deps

            violations = validate_sp_order(sp_name, tables, deps)
            if violations:
                violations_all.extend(violations)
            else:
                print(f"  ✅ {sp_name}: {len(tables)} tables in correct topological order")

        if violations_all:
            print(f"\n  ❌ {len(violations_all)} VIOLATIONS FOUND:")
            for v in violations_all:
                print(v)
        else:
            print(f"\n  ✅ All SP wrappers pass topological validation.")

    # ── Generate ──
    if run_generate:
        print(f"\n{'─' * 60}")
        print("  2. SP GENERATION (topological sort of managed tables)")
        print(f"{'─' * 60}")

        orch_dir = REPO_ROOT / "03_operations" / "orchestration"

        for sp_file in sorted(orch_dir.rglob("*.sql")):
            sp_name = sp_file.name.replace(".sql", "")
            sp_sql = sp_file.read_text(encoding="utf-8")
            existing_tables = parse_sp_order(sp_sql)
            if not existing_tables:
                continue

            # Determine mart and layer
            mart = "forecast_accuracy" if "Forecast" in sp_name else "inventory_health"
            layer = "Silver" if "Silver" in sp_name else "Gold"
            db = "SupplyChain_Processing_Warehouse" if layer == "Silver" else "SupplyChain_Gold_Warehouse"

            # Get dependency graph for this layer
            deps = silver_deps if layer == "Silver" else gold_deps

            # Topological sort only the tables that are in this SP
            # Build subgraph with only these tables
            sub_deps: dict[str, set[str]] = {}
            for t in existing_tables:
                sub_deps[t] = {s for s in deps.get(t, set()) if s in existing_tables}

            sub_rdeps: dict[str, set[str]] = defaultdict(set)
            for t, src_set in sub_deps.items():
                for s in src_set:
                    sub_rdeps[s].add(t)

            waves = _kahn_sort(sub_deps, sub_rdeps)

            # Filter out cycle markers
            clean_waves = [[t for t in w if not t.startswith("CYCLE:")] for w in waves]
            clean_waves = [w for w in clean_waves if w]

            # Map tables to load methods from existing SP or use defaults
            table_methods: dict[str, str] = {}
            import re
            for line in sp_sql.split("\n"):
                m = re.search(r"usp_RefreshCuratedTableFromView\s+'[^']+',\s*'([^']+)',\s*'([^']+)'", line)
                if m:
                    table_methods[f"{m.group(1)}.{m.group(2)}"] = "overwrite"
                m2 = re.search(r"usp_IncrementalTableLoad\s+'[^']+',\s*'([^']+)',\s*'([^']+)'", line)
                if m2:
                    table_methods[f"{m2.group(1)}.{m2.group(2)}"] = "incremental"

            tables_by_wave = []
            for wave in clean_waves:
                entries = []
                for t in wave:
                    schema, table = t.split(".", 1)
                    method = table_methods.get(t, "overwrite")
                    entries.append((schema, table, method))
                tables_by_wave.append(entries)

            if not tables_by_wave:
                continue

            sql = generate_sp_sql(mart, db, sp_name, layer, tables_by_wave)

            out_dir = orch_dir / mart / "sql"
            out_dir.mkdir(parents=True, exist_ok=True)
            out_file = out_dir / f"{db}.dbo.{sp_name}.sql"
            out_file.write_text(sql, encoding="utf-8")

            total_tables = sum(len(w) for w in tables_by_wave)
            cycle_count = sum(1 for w in waves for t in w if t.startswith("CYCLE:"))
            cycle_warn = f" ⚠ {cycle_count} in cycle" if cycle_count else ""
            print(f"  ✅ {sp_name}: {total_tables} tables, {len(tables_by_wave)} waves{cycle_warn}")

    # ── Cross-mart ──
    if run_cross:
        print(f"\n{'─' * 60}")
        print("  3. CROSS-MART DEPENDENCY DETECTION")
        print(f"{'─' * 60}")

        # For cross-mart analysis, assign each table to its PRIMARY mart
        # to avoid false cycles from shared tables appearing in multiple marts.
        primary_mart: dict[str, str] = {}
        for n in nodes:
            key = f"{n.get('schema','')}.{n.get('object_name','')}"
            mart = n.get("mart", "?")
            role = n.get("role", "")
            if role in ("business", "support"):
                # Prefer non-shared classification
                if key not in primary_mart or primary_mart[key] == "shared":
                    primary_mart[key] = mart

        issues = detect_cross_mart_issues(all_deps, primary_mart)
        for i in issues:
            print(i)

        # Also show topological wave summary
        print(f"\n  Full topological sort (all marts, Silver):")
        silver_waves = _kahn_sort(silver_deps, silver_rdeps)
        for wi, wave in enumerate(silver_waves):
            marts_in_wave = defaultdict(list)
            for key in wave:
                marts_in_wave[node_mart.get(key, "?")].append(key)
            mart_summary = ", ".join(f"{m}({len(v)})" for m, v in sorted(marts_in_wave.items()))
            print(f"    Wave {wi:02d}: {mart_summary}")

        print(f"\n  Full topological sort (all marts, Gold):")
        gold_waves = _kahn_sort(gold_deps, gold_rdeps)
        for wi, wave in enumerate(gold_waves):
            marts_in_wave = defaultdict(list)
            for key in wave:
                marts_in_wave[node_mart.get(key, "?")].append(key)
            mart_summary = ", ".join(f"{m}({len(v)})" for m, v in sorted(marts_in_wave.items()))
            print(f"    Wave {wi:02d}: {mart_summary}")

    print(f"\n{'=' * 90}")
    print("  DONE")
    print(f"{'=' * 90}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
