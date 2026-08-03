from __future__ import annotations

import argparse
from pathlib import Path

from .auth import az_cli_token, client_credentials_token
from .builder import build_snapshot, load_fixture
from .config import (
    DEFAULT_LIVE_BASELINE_MAX_AGE_HOURS,
    DEFAULT_SEMANTIC_BINDING_COUNT,
    ScannerConfig,
)
from .fabric_rest import get_semantic_definition, list_workspace_items, resolve_semantic_model_id
from .live_baseline import (
    build_live_baseline,
    load_live_baseline,
    validate_live_baseline,
    write_live_baseline,
)
from .mart_catalog import find_repo_root, load_mart_catalog
from .repository_manifest import load_repository_manifest
from .snapshot_writer import sanitize_snapshot_source_sql, write_snapshot
from .sql_reader import SqlReader


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build GitHub Pages lineage portal snapshot.")
    parser.add_argument("--out", type=Path, default=Path("site/public/lineage_snapshot.json"))
    parser.add_argument("--fixture", type=Path, help="Build snapshot from fixture input instead of live Fabric.")
    parser.add_argument("--repo-root", type=Path, help="Repository root containing 02_marts catalog folders.")
    parser.add_argument("--repository-manifest", type=Path, help="Generated data-edw-fabric lineage manifest.")
    parser.add_argument("--live-baseline", type=Path, help="Last verified live dependency baseline used only as a fallback.")
    parser.add_argument("--write-live-baseline", type=Path, help="Write the current read-only live dependency scan as a fallback baseline.")
    parser.add_argument("--skip-semantic", action="store_true", help="Skip semantic model definition scan.")
    parser.add_argument("--allow-incomplete-semantic", action="store_true", help="Write a diagnostic snapshot without failing when semantic TMDL is unavailable or incomplete.")
    parser.add_argument("--sanitize-snapshot", type=Path, help="Redact raw source_sql from an existing public snapshot in place.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.sanitize_snapshot:
        redacted = sanitize_snapshot_source_sql(args.sanitize_snapshot)
        print(f"sanitized {redacted} raw SQL definition(s): {args.sanitize_snapshot}")
        return 0
    repo_root = args.repo_root or find_repo_root(Path.cwd())
    mart_catalog = load_mart_catalog(repo_root)
    repository_manifest = load_repository_manifest(args.repository_manifest)
    live_baseline = load_live_baseline(args.live_baseline)
    if args.fixture:
        fixture = load_fixture(args.fixture)
        snapshot = build_snapshot(
            workspace_id=fixture.get("workspace", {}).get("id", ""),
            workspace_name=fixture.get("workspace", {}).get("name", ""),
            workspace_items=fixture.get("workspace_items", []),
            sql_scan=fixture["sql_scan"],
            semantic_definition=fixture.get("semantic_definition"),
            semantic_model_name=fixture.get("semantic_model_name", "sc_control_tower"),
            generated_at_utc=fixture.get("generated_at_utc"),
            mart_catalog=mart_catalog,
            repository_manifest=repository_manifest,
            live_baseline=live_baseline,
        )
        write_snapshot(args.out, snapshot)
        print(f"wrote fixture snapshot: {args.out}")
        return 0

    cfg = ScannerConfig.from_env()
    if cfg.use_az_cli:
        database_token = az_cli_token("https://database.windows.net/")
        fabric_token = az_cli_token("https://api.fabric.microsoft.com/")
    else:
        database_token = client_credentials_token(
            tenant_id=cfg.tenant_id,
            client_id=cfg.client_id,
            client_secret=cfg.client_secret,
            scope="https://database.windows.net/.default",
        )
        fabric_token = client_credentials_token(
            tenant_id=cfg.tenant_id,
            client_id=cfg.client_id,
            client_secret=cfg.client_secret,
            scope="https://api.fabric.microsoft.com/.default",
        )
    items = list_workspace_items(cfg.workspace_id, fabric_token)
    reader = SqlReader(cfg.sql_server, database_token)
    sql_scan = reader.scan_all()
    if args.write_live_baseline:
        live_baseline = build_live_baseline(
            sql_scan,
            workspace_id=cfg.workspace_id,
            workspace_name=cfg.workspace_name,
        )
        write_live_baseline(args.write_live_baseline, live_baseline)
        print(f"wrote live lineage baseline: {args.write_live_baseline}")
    baseline_validation = validate_live_baseline(
        live_baseline,
        max_age_hours=DEFAULT_LIVE_BASELINE_MAX_AGE_HOURS,
    )
    if live_baseline is not None and not baseline_validation["valid"]:
        # Never silently apply an incomplete or stale baseline as current live evidence.
        live_baseline = None
    semantic_definition = None
    semantic_failure_reason = ""
    if not args.skip_semantic:
        semantic_model_id = cfg.semantic_model_id
        try:
            semantic_definition = get_semantic_definition(cfg.workspace_id, semantic_model_id, fabric_token)
        except Exception as exc:
            semantic_failure_reason = f"Semantic getDefinition failed: {exc}"
            print(f"warning: semantic getDefinition failed for id={semantic_model_id}: {exc}")
            # Fallback: resolve id from display name and retry once
            resolved = resolve_semantic_model_id(cfg.workspace_id, cfg.semantic_model_name, fabric_token)
            if resolved and resolved != semantic_model_id:
                print(f"info: retrying semantic getDefinition with resolved id={resolved} (name={cfg.semantic_model_name})")
                try:
                    semantic_definition = get_semantic_definition(cfg.workspace_id, resolved, fabric_token)
                except Exception as exc2:
                    semantic_failure_reason = f"Semantic getDefinition retry failed: {exc2}"
                    print(f"warning: semantic getDefinition retry failed: {exc2}")
            elif resolved is None:
                semantic_failure_reason = "Could not resolve semantic model id by name."
                print(f"warning: could not resolve semantic model id by name '{cfg.semantic_model_name}' — check workspace/permissions.")
    else:
        semantic_failure_reason = "Semantic model scan was explicitly skipped."

    snapshot = build_snapshot(
        workspace_id=cfg.workspace_id,
        workspace_name=cfg.workspace_name,
        workspace_items=items,
        sql_scan=sql_scan,
        semantic_definition=semantic_definition,
        semantic_model_name=cfg.semantic_model_name,
        mart_catalog=mart_catalog,
        repository_manifest=repository_manifest,
        live_baseline=live_baseline,
        live_baseline_validation=baseline_validation,
        semantic_expected_binding_count=DEFAULT_SEMANTIC_BINDING_COUNT,
        semantic_failure_reason=semantic_failure_reason,
    )
    dependency_fallback_rejected = (
        not baseline_validation["valid"]
        and any("dependency metadata is not readable" in warning for warning in sql_scan.get("warnings", []))
    )
    if dependency_fallback_rejected:
        raise RuntimeError(f"Live dependency fallback rejected: {baseline_validation['reason']}")
    if not snapshot["semantic_validation"]["complete"] and not args.allow_incomplete_semantic:
        raise RuntimeError(f"Semantic lineage incomplete: {snapshot['semantic_validation']['reason']}")
    # Only an explicit diagnostic invocation may write an incomplete snapshot.
    write_snapshot(args.out, snapshot)
    print(f"wrote live snapshot: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
