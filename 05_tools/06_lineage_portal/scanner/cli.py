from __future__ import annotations

import argparse
from pathlib import Path

from .auth import az_cli_token, client_credentials_token
from .builder import build_snapshot, load_fixture
from .config import ScannerConfig
from .fabric_rest import get_semantic_definition, list_workspace_items, resolve_semantic_model_id
from .live_baseline import build_live_baseline, load_live_baseline, write_live_baseline
from .mart_catalog import find_repo_root, load_mart_catalog
from .repository_manifest import load_repository_manifest
from .snapshot_writer import write_snapshot
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
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
    semantic_definition = None
    if not args.skip_semantic:
        semantic_model_id = cfg.semantic_model_id
        try:
            semantic_definition = get_semantic_definition(cfg.workspace_id, semantic_model_id, fabric_token)
        except Exception as exc:
            print(f"warning: semantic getDefinition failed for id={semantic_model_id}: {exc}")
            # Fallback: resolve id from display name and retry once
            resolved = resolve_semantic_model_id(cfg.workspace_id, cfg.semantic_model_name, fabric_token)
            if resolved and resolved != semantic_model_id:
                print(f"info: retrying semantic getDefinition with resolved id={resolved} (name={cfg.semantic_model_name})")
                try:
                    semantic_definition = get_semantic_definition(cfg.workspace_id, resolved, fabric_token)
                except Exception as exc2:
                    print(f"warning: semantic getDefinition retry failed: {exc2}")
            elif resolved is None:
                print(f"warning: could not resolve semantic model id by name '{cfg.semantic_model_name}' — check workspace/permissions.")

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
    )
    write_snapshot(args.out, snapshot)
    print(f"wrote live snapshot: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
