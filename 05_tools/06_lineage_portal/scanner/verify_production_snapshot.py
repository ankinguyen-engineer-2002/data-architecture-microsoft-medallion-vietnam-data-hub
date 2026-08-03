from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any


def _parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def validate_snapshot(
    snapshot: dict[str, Any],
    *,
    expected_manifest_sha: str,
    expected_pull_request: int,
    expected_workspace_id: str,
    expected_workspace_name: str,
    baseline_max_age_hours: int,
    expected_baseline_view_count: int,
    now: datetime | None = None,
) -> list[str]:
    """Return every production-safety violation instead of publishing partial truth."""
    errors: list[str] = []
    repository = snapshot.get("repository") or {}
    if repository.get("commit_sha") != expected_manifest_sha:
        errors.append("repository manifest SHA does not match the approved PR head")
    if repository.get("pull_request") != expected_pull_request:
        errors.append("repository manifest PR does not match the approved PR")

    workspace = snapshot.get("workspace") or {}
    if workspace.get("id") != expected_workspace_id:
        errors.append("snapshot workspace id does not match the approved DEV workspace")
    if workspace.get("name") != expected_workspace_name:
        errors.append("snapshot workspace name does not match the approved DEV workspace")
    try:
        snapshot_age = (now or datetime.now(UTC)) - _parse_utc(str(snapshot.get("generated_at_utc") or ""))
    except ValueError:
        errors.append("snapshot generated_at_utc is missing or invalid")
    else:
        if snapshot_age > timedelta(hours=baseline_max_age_hours):
            errors.append(f"snapshot is older than {baseline_max_age_hours} hours")
        if snapshot_age < timedelta(0):
            errors.append("snapshot generated_at_utc is in the future")

    semantic_validation = snapshot.get("semantic_validation") or {}
    semantic_edges = [
        edge
        for edge in snapshot.get("edges") or []
        if edge.get("relationship_type") == "feeds_semantic"
    ]
    warnings = [str(item).lower() for item in snapshot.get("warnings") or []]
    if semantic_validation.get("complete") is not True:
        errors.append("semantic validation is not complete")
    if semantic_validation.get("definition_read") is not True:
        errors.append("semantic definition was not read")
    if semantic_validation.get("binding_count") != 14:
        errors.append("semantic validation does not report exactly 14 bindings")
    if len(semantic_edges) != 14:
        errors.append("snapshot does not contain exactly 14 feeds_semantic edges")
    if any(edge.get("confidence") != "verified" for edge in semantic_edges):
        errors.append("feeds_semantic edges must all have verified confidence")
    if any("semantic lineage is incomplete" in warning for warning in warnings):
        errors.append("snapshot reports incomplete semantic lineage")

    if any(str(node.get("source_sql") or "").strip() for node in snapshot.get("nodes") or []):
        errors.append("public snapshot contains raw source_sql")

    evidence = snapshot.get("scan_evidence") or {}
    baseline_used = int(evidence.get("live_baseline_view_count") or 0)
    if baseline_used:
        baseline = snapshot.get("live_baseline") or {}
        baseline_time = str(baseline.get("generated_at_utc") or "")
        try:
            age = (now or datetime.now(UTC)) - _parse_utc(baseline_time)
        except ValueError:
            errors.append("live baseline timestamp is missing or invalid")
        else:
            if age > timedelta(hours=baseline_max_age_hours):
                errors.append(f"live baseline is older than {baseline_max_age_hours} hours")
            if age < timedelta(0):
                errors.append("live baseline timestamp is in the future")
        if baseline_used != expected_baseline_view_count:
            errors.append(
                "live baseline is incomplete: "
                f"used {baseline_used} views, expected {expected_baseline_view_count}"
            )
        if int((baseline.get("summary") or {}).get("dependency_edge_count") or 0) == 0:
            errors.append("live baseline has no dependency edges")
    elif int(evidence.get("live_dependency_row_count") or 0) == 0:
        errors.append("no current live dependencies and no complete fallback baseline")

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fail closed before publishing a lineage snapshot.")
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--expected-manifest-sha", required=True)
    parser.add_argument("--expected-pull-request", type=int, required=True)
    parser.add_argument("--expected-workspace-id", required=True)
    parser.add_argument("--expected-workspace-name", required=True)
    parser.add_argument("--baseline-max-age-hours", type=int, default=6)
    parser.add_argument("--expected-baseline-view-count", type=int, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    errors = validate_snapshot(
        snapshot,
        expected_manifest_sha=args.expected_manifest_sha,
        expected_pull_request=args.expected_pull_request,
        expected_workspace_id=args.expected_workspace_id,
        expected_workspace_name=args.expected_workspace_name,
        baseline_max_age_hours=args.baseline_max_age_hours,
        expected_baseline_view_count=args.expected_baseline_view_count,
    )
    if errors:
        raise SystemExit("Production lineage snapshot rejected:\n- " + "\n- ".join(errors))
    print("production lineage snapshot safety gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
