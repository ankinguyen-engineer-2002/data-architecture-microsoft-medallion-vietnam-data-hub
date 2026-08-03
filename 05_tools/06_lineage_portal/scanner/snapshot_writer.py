from __future__ import annotations

import json
import hashlib
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def write_snapshot(path: Path, snapshot: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(snapshot, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")


def sanitize_snapshot_source_sql(path: Path) -> int:
    """Redact legacy raw SQL in an existing public snapshot in place."""
    snapshot = json.loads(path.read_text(encoding="utf-8"))
    redacted = 0
    for node in snapshot.get("nodes", []):
        source_sql = str(node.get("source_sql") or "")
        if not source_sql:
            continue
        node["source_sql_sha256"] = hashlib.sha256(source_sql.encode("utf-8")).hexdigest()
        node["source_sql"] = ""
        redacted += 1
    write_snapshot(path, snapshot)
    return redacted


def now_utc() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
