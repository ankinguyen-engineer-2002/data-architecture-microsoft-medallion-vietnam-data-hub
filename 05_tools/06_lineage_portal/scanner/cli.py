from __future__ import annotations

import argparse
from pathlib import Path

from .auth import client_credentials_token
from .builder import build_snapshot, load_fixture
from .config import ScannerConfig
from .fabric_rest import get_semantic_definition, list_workspace_items
from .mart_catalog import find_repo_root, load_mart_catalog
from .snapshot_writer import write_snapshot
from .sql_reader import SqlReader


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build GitHub Pages lineage portal snapshot.")
    parser.add_argument("--out", type=Path, default=Path("site/public/lineage_snapshot.json"))
    parser.add_argument("--fixture", type=Path, help="Build snapshot from fixture input instead of live Fabric.")
    parser.add_argument("--repo-root", type=Path, help="Repository root containing 02_marts catalog folders.")
    parser.add_argument("--skip-semantic", action="store_true", help="Skip semantic model definition scan.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root or find_repo_root(Path.cwd())
    mart_catalog = load_mart_catalog(repo_root)
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
        )
        write_snapshot(args.out, snapshot)
        print(f"wrote fixture snapshot: {args.out}")
        return 0

    cfg = ScannerConfig.from_env()
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
    semantic_definition = None
    if not args.skip_semantic:
        semantic_definition = get_semantic_definition(cfg.workspace_id, cfg.semantic_model_id, fabric_token)

    snapshot = build_snapshot(
        workspace_id=cfg.workspace_id,
        workspace_name=cfg.workspace_name,
        workspace_items=items,
        sql_scan=sql_scan,
        semantic_definition=semantic_definition,
        semantic_model_name=cfg.semantic_model_name,
        mart_catalog=mart_catalog,
    )
    write_snapshot(args.out, snapshot)
    print(f"wrote live snapshot: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
