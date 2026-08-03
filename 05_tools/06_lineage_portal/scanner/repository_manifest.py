from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .dependency_parser import extract_object_refs


PROJECT_DATABASES = (
    "SupplyChain_Processing_Warehouse",
    "SupplyChain_Gold_Warehouse",
)
CREATE_OBJECT_RE = re.compile(
    r"\bCREATE\s+(?:OR\s+ALTER\s+)?"
    r"(?P<kind>VIEW|TABLE|PROCEDURE|PROC)\s+"
    r"\[?(?P<schema>[A-Za-z_][A-Za-z0-9_]*)\]?\s*\.\s*"
    r"\[?(?P<object>[A-Za-z_][A-Za-z0-9_]*)\]?",
    flags=re.IGNORECASE,
)


def load_repository_manifest(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def build_repository_manifest(
    repo_root: Path,
    *,
    expected_sha: str | None = None,
    repository: str = "afi-internal/data-edw-fabric",
    pull_request: int | None = None,
) -> dict[str, Any]:
    root = repo_root.resolve()
    commit_sha = _git(root, "rev-parse", "HEAD")
    if expected_sha and commit_sha != expected_sha:
        raise RuntimeError(f"EDW worktree SHA mismatch: expected {expected_sha}, found {commit_sha}")

    views: list[dict[str, Any]] = []
    procedures: list[dict[str, Any]] = []
    tables: list[dict[str, Any]] = []

    for database in PROJECT_DATABASES:
        project_root = root / database
        if not project_root.exists():
            raise RuntimeError(f"Missing EDW project directory: {project_root}")
        for path in sorted(project_root.rglob("*.sql")):
            text = path.read_text(encoding="utf-8-sig")
            match = CREATE_OBJECT_RE.search(text)
            if not match:
                continue
            kind = match.group("kind").upper()
            item = {
                "database": database,
                "schema": match.group("schema"),
                "object_name": match.group("object"),
                "path": str(path.relative_to(root)),
                "definition_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            }
            if kind == "VIEW":
                item["dependencies"] = [
                    {
                        "database": ref.database or database,
                        "schema": ref.schema,
                        "object_name": ref.object_name,
                    }
                    for ref in extract_object_refs(text, default_database=database)
                ]
                views.append(item)
            elif kind == "TABLE":
                tables.append(item)
            else:
                procedures.append(item)

    table_keys = {
        (item["database"], item["schema"].lower(), item["object_name"].lower())
        for item in tables
    }
    for view in views:
        target_schema = str(view["schema"])
        target_object = str(view["object_name"])
        if target_schema.endswith("_Wrk") and target_object.startswith("v_"):
            candidate = (
                str(view["database"]),
                target_schema.removesuffix("_Wrk"),
                target_object.removeprefix("v_"),
            )
            key = (candidate[0], candidate[1].lower(), candidate[2].lower())
            if key in table_keys:
                view["target"] = {
                    "database": candidate[0],
                    "schema": candidate[1],
                    "object_name": candidate[2],
                }
                continue
        view["target"] = {
            "database": view["database"],
            "schema": view["schema"],
            "object_name": view["object_name"],
        }

    source_contracts = {
        f"{dep['database']}.{dep['schema']}.{dep['object_name']}"
        for view in views
        for dep in view["dependencies"]
        if dep["database"] not in PROJECT_DATABASES
    }
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "schema_version": 1,
        "repository": repository,
        "commit_sha": commit_sha,
        "pull_request": pull_request,
        "generated_at_utc": generated_at,
        "summary": {
            "view_count": len(views),
            "procedure_count": len(procedures),
            "table_count": len(tables),
            "dependency_edge_count": sum(len(view["dependencies"]) for view in views),
            "external_contract_count": len(source_contracts),
        },
        "views": sorted(views, key=_object_sort_key),
        "procedures": sorted(procedures, key=_object_sort_key),
        "tables": sorted(tables, key=_object_sort_key),
    }


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _object_sort_key(item: dict[str, Any]) -> tuple[str, str, str]:
    return str(item["database"]), str(item["schema"]), str(item["object_name"])


def _git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate an EDW repository lineage manifest.")
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--expected-sha")
    parser.add_argument("--repository", default="afi-internal/data-edw-fabric")
    parser.add_argument("--pull-request", type=int)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = build_repository_manifest(
        args.repo_root,
        expected_sha=args.expected_sha,
        repository=args.repository,
        pull_request=args.pull_request,
    )
    write_manifest(args.out, manifest)
    print(
        "wrote repository lineage manifest: "
        f"{args.out} ({manifest['summary']['view_count']} views, "
        f"{manifest['summary']['dependency_edge_count']} edges)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
