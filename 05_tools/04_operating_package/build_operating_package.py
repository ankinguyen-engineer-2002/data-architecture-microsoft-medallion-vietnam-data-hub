#!/usr/bin/env python3
"""Build DQ and lineage/catalog operating packages from repo artifacts.

This generator is intentionally repo-local and read-only against Fabric. It
uses existing mart SQL files, DQ evidence JSON, orchestration manifests, and
semantic model files to create machine-readable contracts that agents can use
for audits, ad-hoc refreshes, and mart onboarding.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


SQL_OBJECT_RE = re.compile(
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"(?:\s*\.\s*(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*)))?"
)

SQL_KEYWORDS = {
    "AS",
    "BY",
    "CASE",
    "CAST",
    "COUNT",
    "DATEADD",
    "DATEDIFF",
    "DECIMAL",
    "ELSE",
    "END",
    "FROM",
    "GROUP",
    "HAVING",
    "INNER",
    "JOIN",
    "LEFT",
    "MAX",
    "MIN",
    "NULLIF",
    "ON",
    "OR",
    "ORDER",
    "OVER",
    "RIGHT",
    "SELECT",
    "SUM",
    "THEN",
    "WHEN",
    "WHERE",
}


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def normalize_asset_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", ".", name.lower()).strip(".")


def display_from_asset_key(asset_key: str) -> str:
    return ".".join(part for part in asset_key.split(".") if part)


def strip_sql_noise(text: str) -> str:
    text = re.sub(r"--.*?$", " ", text, flags=re.MULTILINE)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"'(?:''|[^'])*'", "''", text)
    return text


def first_row(check: dict[str, Any] | None) -> dict[str, Any]:
    if not check:
        return {}
    rows = check.get("rows") or check.get("value") or []
    return rows[0] if rows else {}


def count_positive(*values: Any) -> bool:
    for value in values:
        if value in (None, "", "null"):
            continue
        try:
            if int(value) > 0:
                return True
        except (TypeError, ValueError):
            continue
    return False


def dq_issue_summary(dq: dict[str, Any]) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    nulls = first_row(dq.get("latest_partition_null_blank"))
    if count_positive(nulls.get("latest_partition_null_blank_key_rows")):
        issues.append(
            {
                "check": "latest_partition_null_blank_key",
                "metric": "latest_partition_null_blank_key_rows",
                "value": nulls.get("latest_partition_null_blank_key_rows"),
            }
        )
    dup = first_row(dq.get("latest_partition_duplicate"))
    if count_positive(dup.get("latest_partition_duplicate_groups"), dup.get("latest_partition_duplicate_extra_rows")):
        issues.append(
            {
                "check": "latest_partition_grain_duplicate",
                "groups": dup.get("latest_partition_duplicate_groups"),
                "extra_rows": dup.get("latest_partition_duplicate_extra_rows"),
            }
        )
    full_dup = first_row(dq.get("full_row_duplicate"))
    if count_positive(
        full_dup.get("latest_full_row_duplicate_groups"),
        full_dup.get("latest_full_row_duplicate_extra_rows"),
        full_dup.get("full_row_duplicate_groups"),
        full_dup.get("full_row_duplicate_extra_rows"),
    ):
        issues.append(
            {
                "check": "full_row_duplicate",
                "groups": full_dup.get("latest_full_row_duplicate_groups") or full_dup.get("full_row_duplicate_groups"),
                "extra_rows": full_dup.get("latest_full_row_duplicate_extra_rows") or full_dup.get("full_row_duplicate_extra_rows"),
            }
        )
    hist_dup = first_row(dq.get("all_history_grain_duplicate"))
    if count_positive(hist_dup.get("duplicate_groups"), hist_dup.get("duplicate_extra_rows")):
        issues.append(
            {
                "check": "all_history_grain_duplicate",
                "groups": hist_dup.get("duplicate_groups"),
                "extra_rows": hist_dup.get("duplicate_extra_rows"),
            }
        )
    for check_name in [
        "latest_partition_null_blank",
        "latest_partition_duplicate",
        "full_row_duplicate",
        "all_history_grain_duplicate",
    ]:
        check = dq.get(check_name) or {}
        if check.get("status") in {"ERROR", "TIMEOUT"}:
            issues.append({"check": check_name, "status": check.get("status"), "error": check.get("error")})
    return issues


def build_dq_pack(mart_dir: Path, generated_at: str) -> dict[str, Any]:
    mart = mart_dir.name
    dq_dir = mart_dir / "04_dq"
    source_dir = dq_dir / "bronze_sources"
    source_files = sorted(source_dir.glob("*.dq.json"))
    sources: list[dict[str, Any]] = []
    rules: list[dict[str, Any]] = []
    exceptions: list[dict[str, Any]] = []

    for path in source_files:
        payload = read_json(path)
        dq = payload.get("dq") or {}
        asset_key = payload.get("asset_key") or normalize_asset_key(payload.get("display", path.stem))
        status = payload.get("dq_status") or dq.get("status") or "UNKNOWN"
        issues = dq_issue_summary(dq)
        rule_set = [
            "table_exists",
            "schema_snapshot",
            "freshness_observed",
            "latest_partition_null_blank_key",
            "latest_partition_grain_duplicate",
            "full_row_duplicate",
        ]
        if dq.get("all_history_grain_duplicate", {}).get("status") != "SKIPPED":
            rule_set.append("all_history_grain_duplicate")

        source_contract = {
            "asset_key": asset_key,
            "display": payload.get("display") or dq.get("ref") or display_from_asset_key(asset_key),
            "mart": mart,
            "layer": "bronze",
            "source_system": "Enterprise_Lakehouse",
            "dq_status": status,
            "review_required": status != "PASS",
            "freshness": dq.get("freshness") or {},
            "freshness_columns": dq.get("freshness_columns") or [],
            "key_columns": dq.get("key_columns") or [],
            "column_count": dq.get("column_count"),
            "row_count_metadata": dq.get("row_count_metadata"),
            "rule_set": rule_set,
            "evidence_file": str(path.relative_to(mart_dir.parents[1])),
            "sql_rerun_template": str(path.with_suffix(".sql").relative_to(mart_dir.parents[1])),
        }
        sources.append(source_contract)

        rules.append(
            {
                "asset_key": asset_key,
                "rules": [
                    {"rule": "table_exists", "severity": "critical", "status": "PASS" if dq.get("exists") else "FAIL"},
                    {"rule": "schema_snapshot", "severity": "info", "column_count": dq.get("column_count")},
                    {"rule": "freshness_observed", "severity": "warning", "observed_values": dq.get("freshness") or {}},
                    {
                        "rule": "latest_partition_null_blank_key",
                        "severity": "critical",
                        "key_columns": dq.get("key_columns") or [],
                        "status": (dq.get("latest_partition_null_blank") or {}).get("status"),
                        "metric": first_row(dq.get("latest_partition_null_blank")),
                    },
                    {
                        "rule": "latest_partition_grain_duplicate",
                        "severity": "critical",
                        "grain": dq.get("key_columns") or [],
                        "status": (dq.get("latest_partition_duplicate") or {}).get("status"),
                        "metric": first_row(dq.get("latest_partition_duplicate")),
                    },
                    {
                        "rule": "full_row_duplicate",
                        "severity": "warning",
                        "status": (dq.get("full_row_duplicate") or {}).get("status"),
                        "metric": first_row(dq.get("full_row_duplicate")),
                    },
                    {
                        "rule": "all_history_grain_duplicate",
                        "severity": "warning",
                        "status": (dq.get("all_history_grain_duplicate") or {}).get("status"),
                        "metric": first_row(dq.get("all_history_grain_duplicate")),
                    },
                ],
            }
        )

        if status != "PASS":
            exceptions.append(
                {
                    "asset_key": asset_key,
                    "display": source_contract["display"],
                    "dq_status": status,
                    "owner": "DE/source owner or business data owner",
                    "disposition": "open_review",
                    "issues": issues or [{"check": "status", "value": status}],
                    "evidence_file": source_contract["evidence_file"],
                }
            )

    counts = Counter(source["dq_status"] for source in sources)
    run_payload = {
        "generated_at_utc": generated_at,
        "mart": mart,
        "layer": "bronze",
        "source_count": len(sources),
        "status_counts": dict(sorted(counts.items())),
        "pass_count": counts.get("PASS", 0),
        "review_count": sum(count for status, count in counts.items() if status != "PASS"),
        "sources": [
            {
                "asset_key": source["asset_key"],
                "display": source["display"],
                "dq_status": source["dq_status"],
                "review_required": source["review_required"],
                "freshness": source["freshness"],
                "key_columns": source["key_columns"],
            }
            for source in sources
        ],
    }

    write_json(dq_dir / "contracts" / "bronze_sources.json", {"generated_at_utc": generated_at, "mart": mart, "sources": sources})
    write_json(dq_dir / "contracts" / "rules.json", {"generated_at_utc": generated_at, "mart": mart, "rule_contracts": rules})
    write_json(dq_dir / "contracts" / "exceptions.json", {"generated_at_utc": generated_at, "mart": mart, "exceptions": exceptions})
    write_json(dq_dir / "runs" / "latest.json", run_payload)
    write_json(dq_dir / "runs" / f"{generated_at.replace(':', '').replace('-', '').replace('Z', 'Z')}.json", run_payload)
    return run_payload


def target_from_sql_path(repo_root: Path, mart_dir: Path, path: Path) -> dict[str, Any] | None:
    rel = path.relative_to(mart_dir)
    parts = rel.parts
    stem = path.name.removesuffix(".sql")
    object_type = "sql_object"
    schema: str | None = None
    object_name: str | None = None
    display: str

    if parts[0] == "01_bronze":
        display = stem
        object_type = "source_shortcut"
        bits = display.split(".")
        schema = bits[1] if len(bits) >= 3 else None
        object_name = bits[2] if len(bits) >= 3 else bits[-1]
        layer = "bronze"
    elif parts[0] == "00_source_wrk":
        display = stem
        bits = display.split(".")
        schema = bits[0] if len(bits) >= 2 else parts[-2]
        object_name = bits[1] if len(bits) >= 2 else stem
        layer = "source_wrk"
        object_type = "wrk_view" if object_name.startswith("v_") or str(schema).endswith("_Wrk") else "source_seed_or_target"
    elif parts[0] in {"02_silver", "03_gold"}:
        layer = "silver" if parts[0] == "02_silver" else "gold"
        schema = parts[1] if len(parts) > 2 else None
        if stem.endswith(".table"):
            object_name = stem.removesuffix(".table")
            object_type = "final_table_contract"
        else:
            object_name = stem
            object_type = "wrk_view" if object_name.startswith("v_") or str(schema).endswith("_Wrk") else "sql_object"
        display = f"{schema}.{object_name}" if schema else object_name
    else:
        return None

    return {
        "asset_key": normalize_asset_key(display),
        "display": display,
        "mart": mart_dir.name,
        "layer": layer,
        "object_type": object_type,
        "schema": schema,
        "object": object_name,
        "file_path": str(path.relative_to(repo_root)),
    }


def discover_assets(repo_root: Path, mart_dir: Path) -> list[dict[str, Any]]:
    assets: list[dict[str, Any]] = []
    for folder in ["00_source_wrk", "01_bronze", "02_silver", "03_gold"]:
        for path in sorted((mart_dir / folder).glob("**/*.sql")):
            asset = target_from_sql_path(repo_root, mart_dir, path)
            if asset:
                assets.append(asset)
    for path in sorted((repo_root / "04_semantic").glob("**/*")):
        if path.is_file() and path.suffix.lower() in {".tmdl", ".dax", ".md"}:
            assets.append(
                {
                    "asset_key": normalize_asset_key(f"semantic.{path.stem}"),
                    "display": f"semantic.{path.stem}",
                    "mart": mart_dir.name,
                    "layer": "semantic",
                    "object_type": "semantic_artifact",
                    "schema": None,
                    "object": path.stem,
                    "file_path": str(path.relative_to(repo_root)),
                }
            )
    return assets


def sql_refs(text: str, known_two_part_refs: set[str]) -> set[str]:
    clean = strip_sql_noise(text)
    refs: set[str] = set()
    for match in SQL_OBJECT_RE.finditer(clean):
        p1 = match.group(1) or match.group(2)
        p2 = match.group(3) or match.group(4)
        p3 = match.group(5) or match.group(6)
        if not p1 or not p2:
            continue
        if p1.upper() in SQL_KEYWORDS or p2.upper() in SQL_KEYWORDS:
            continue
        if p3:
            if p1 in {
                "Enterprise_Lakehouse",
                "SupplyChain_Lakehouse",
                "SupplyChain_Processing_Warehouse",
                "SupplyChain_Gold_Warehouse",
                "ETL_Framework",
            }:
                refs.add(f"{p1}.{p2}.{p3}")
        else:
            ref = f"{p1}.{p2}"
            if ref.lower() in known_two_part_refs:
                refs.add(ref)
    return refs


def build_lineage_edges(repo_root: Path, mart_dir: Path, assets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_display = {asset["display"].lower(): asset for asset in assets}
    by_short = {
        f"{asset.get('schema')}.{asset.get('object')}".lower(): asset
        for asset in assets
        if asset.get("schema") and asset.get("object")
    }
    known_two_part_refs = set(by_short)
    edges: dict[tuple[str, str, str], dict[str, Any]] = {}

    def add_edge(source: str, target: str, edge_type: str, evidence: str | None = None) -> None:
        if normalize_asset_key(source) == normalize_asset_key(target):
            return
        key = (normalize_asset_key(source), normalize_asset_key(target), edge_type)
        edges[key] = {
            "source_asset_key": key[0],
            "source": source,
            "target_asset_key": key[1],
            "target": target,
            "edge_type": edge_type,
            "evidence_file": evidence,
        }

    for asset in assets:
        path_value = asset.get("file_path")
        if not path_value or not path_value.endswith(".sql"):
            continue
        path = repo_root / path_value
        if not path.exists():
            continue
        for ref in sorted(sql_refs(path.read_text(encoding="utf-8", errors="ignore"), known_two_part_refs)):
            ref_asset = by_display.get(ref.lower()) or by_short.get(ref.lower())
            source_display = ref_asset["display"] if ref_asset else ref
            add_edge(source_display, asset["display"], "sql_reference", path_value)

    for asset in assets:
        schema = asset.get("schema") or ""
        obj = asset.get("object") or ""
        if asset.get("object_type") != "wrk_view" or not schema.endswith("_Wrk") or not obj.startswith("v_"):
            continue
        final_schema = schema.removesuffix("_Wrk")
        final_object = obj.removeprefix("v_")
        final = by_short.get(f"{final_schema}.{final_object}".lower())
        if final:
            add_edge(asset["display"], final["display"], "bob_wrk_view_materializes_final_table", asset.get("file_path"))

    return sorted(edges.values(), key=lambda row: (row["target"], row["source"], row["edge_type"]))


def build_run_order(repo_root: Path, mart_dir: Path, assets: list[dict[str, Any]]) -> dict[str, Any]:
    manifest_path = repo_root / "03_operations" / "orchestration" / mart_dir.name / "manifest.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {"sequence": []}
    asset_keys = {asset["display"].lower(): asset["asset_key"] for asset in assets}
    steps = []
    for step in manifest.get("sequence", []):
        obj = step.get("object") or step.get("project") or step.get("purpose")
        steps.append(
            {
                **step,
                "resolved_asset_key": asset_keys.get(str(obj).lower()),
                "dq_gate": "bronze_source_contracts" if step.get("step", 0) >= 90 else None,
            }
        )
    return {
        "mart": mart_dir.name,
        "manifest": str(manifest_path.relative_to(repo_root)) if manifest_path.exists() else None,
        "pipeline": manifest.get("pipeline"),
        "default_mode": manifest.get("default_mode", "dry_run"),
        "sequence": steps,
        "post_run_checks": manifest.get("post_run_checks", []),
    }


def build_semantic_bindings(repo_root: Path, mart_dir: Path, assets: list[dict[str, Any]]) -> dict[str, Any]:
    semantic_files = [p for p in sorted((repo_root / "04_semantic").glob("**/*")) if p.is_file() and p.suffix.lower() in {".tmdl", ".dax"}]
    gold_assets = [asset for asset in assets if asset["layer"] == "gold"]
    bindings: list[dict[str, Any]] = []
    for sem_file in semantic_files:
        text = sem_file.read_text(encoding="utf-8", errors="ignore").lower()
        for asset in gold_assets:
            needles = [asset["display"].lower()]
            if asset.get("object"):
                needles.append(str(asset["object"]).lower())
            if any(needle and needle in text for needle in needles):
                bindings.append(
                    {
                        "semantic_file": str(sem_file.relative_to(repo_root)),
                        "gold_asset_key": asset["asset_key"],
                        "gold_asset": asset["display"],
                        "match_type": "text_reference",
                    }
                )
    return {
        "mart": mart_dir.name,
        "semantic_root": "04_semantic",
        "bindings": sorted(bindings, key=lambda row: (row["semantic_file"], row["gold_asset"])),
    }


def write_catalog_readme(path: Path, mart: str) -> None:
    path.write_text(
        f"# {mart} Catalog\n\n"
        "Machine-readable operating registry for this mart.\n\n"
        "| File | Purpose |\n"
        "|---|---|\n"
        "| `assets.json` | All repo-known mart assets by layer and file path. |\n"
        "| `lineage_edges.json` | Table/view/source edges inferred from SQL references plus BOB `_Wrk` materialization edges. |\n"
        "| `run_order.json` | Manifest-backed refresh order and post-run check contract. |\n"
        "| `semantic_bindings.json` | Gold-to-semantic references inferred from local semantic artifacts. |\n",
        encoding="utf-8",
    )


def build_catalog_pack(repo_root: Path, mart_dir: Path, generated_at: str) -> dict[str, Any]:
    catalog_dir = mart_dir / "05_catalog"
    assets = discover_assets(repo_root, mart_dir)
    edges = build_lineage_edges(repo_root, mart_dir, assets)
    run_order = build_run_order(repo_root, mart_dir, assets)
    semantic_bindings = build_semantic_bindings(repo_root, mart_dir, assets)

    asset_payload = {"generated_at_utc": generated_at, "mart": mart_dir.name, "assets": assets}
    edge_payload = {"generated_at_utc": generated_at, "mart": mart_dir.name, "edges": edges}
    run_order["generated_at_utc"] = generated_at
    semantic_bindings["generated_at_utc"] = generated_at

    write_json(catalog_dir / "assets.json", asset_payload)
    write_json(catalog_dir / "lineage_edges.json", edge_payload)
    write_json(catalog_dir / "run_order.json", run_order)
    write_json(catalog_dir / "semantic_bindings.json", semantic_bindings)
    write_catalog_readme(catalog_dir / "README.md", mart_dir.name)
    return {
        "mart": mart_dir.name,
        "asset_count": len(assets),
        "edge_count": len(edges),
        "run_step_count": len(run_order.get("sequence", [])),
        "semantic_binding_count": len(semantic_bindings.get("bindings", [])),
    }


def build_global_registry(repo_root: Path, generated_at: str, dq_runs: list[dict[str, Any]], catalogs: list[dict[str, Any]]) -> None:
    out_dir = repo_root / "03_operations" / "operating_registry"
    out_dir.mkdir(parents=True, exist_ok=True)
    all_assets: list[dict[str, Any]] = []
    all_edges: list[dict[str, Any]] = []
    all_run_orders: list[dict[str, Any]] = []
    for mart_dir in sorted((repo_root / "02_marts").iterdir()):
        if not mart_dir.is_dir():
            continue
        assets_path = mart_dir / "05_catalog" / "assets.json"
        edges_path = mart_dir / "05_catalog" / "lineage_edges.json"
        run_path = mart_dir / "05_catalog" / "run_order.json"
        if assets_path.exists():
            all_assets.extend(read_json(assets_path).get("assets", []))
        if edges_path.exists():
            all_edges.extend(read_json(edges_path).get("edges", []))
        if run_path.exists():
            all_run_orders.append(read_json(run_path))
    write_json(out_dir / "assets.json", {"generated_at_utc": generated_at, "assets": all_assets})
    write_json(out_dir / "lineage_edges.json", {"generated_at_utc": generated_at, "edges": all_edges})
    write_json(out_dir / "dq_summary.json", {"generated_at_utc": generated_at, "marts": dq_runs})
    write_json(out_dir / "run_order.json", {"generated_at_utc": generated_at, "marts": all_run_orders})
    write_json(
        out_dir / "summary.json",
        {
            "generated_at_utc": generated_at,
            "mart_count": len(catalogs),
            "asset_count": len(all_assets),
            "edge_count": len(all_edges),
            "dq_source_count": sum(run.get("source_count", 0) for run in dq_runs),
            "dq_review_count": sum(run.get("review_count", 0) for run in dq_runs),
            "catalogs": catalogs,
        },
    )
    (out_dir / "README.md").write_text(
        "# Operating Registry\n\n"
        "Repo-level generated registry assembled from `02_marts/*/04_dq` and `02_marts/*/05_catalog`.\n\n"
        "| File | Purpose |\n"
        "|---|---|\n"
        "| `summary.json` | Counts and high-level package health. |\n"
        "| `assets.json` | All mart assets. |\n"
        "| `lineage_edges.json` | All mart lineage edges. |\n"
        "| `dq_summary.json` | Bronze DQ run summaries by mart. |\n"
        "| `run_order.json` | All mart run-order manifests. |\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Build repo-local DQ and catalog operating packages.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    args = parser.parse_args()
    repo_root = Path(args.repo_root).resolve()
    generated_at = utc_now()
    mart_dirs = [p for p in sorted((repo_root / "02_marts").iterdir()) if p.is_dir() and not p.name.startswith(".")]
    dq_runs = []
    catalogs = []
    for mart_dir in mart_dirs:
        if (mart_dir / "04_dq" / "bronze_sources").exists():
            dq_runs.append(build_dq_pack(mart_dir, generated_at))
        catalogs.append(build_catalog_pack(repo_root, mart_dir, generated_at))
    build_global_registry(repo_root, generated_at, dq_runs, catalogs)
    print(
        json.dumps(
            {
                "generated_at_utc": generated_at,
                "mart_count": len(mart_dirs),
                "dq_source_count": sum(run.get("source_count", 0) for run in dq_runs),
                "catalogs": catalogs,
            },
            indent=2,
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
