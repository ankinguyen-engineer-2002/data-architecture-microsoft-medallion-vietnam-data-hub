"""Update v10 forecast docs to reflect Bob alignment changes (2026-05-10).

Transforms:
  Schema casing: _ENH → _Enh, _WRK → _Wrk
  View prefix: vw_X → v_X
  TableDictionary: vw_TableDictionary → TableDictionary (now real table)

Excludes:
  _open_questions_for_bob.md (intentional historical reference)

Adds new sections to README.md about Bob alignment infrastructure.
"""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROJ = ROOT / "Enterprise_SupplyChain_Dev_architect" / "projects" / "forecast"

EXCLUDE = {PROJ / "_open_questions_for_bob.md"}

SCHEMA_RENAMES = [
    ("Staging_WRK", "Staging_Wrk"),
    ("ReferenceMaster_ENH", "ReferenceMaster_Enh"),
    ("SalesHistory_ENH", "SalesHistory_Enh"),
    ("ForecastHistory_ENH", "ForecastHistory_Enh"),
    ("OpenOrderHistory_ENH", "OpenOrderHistory_Enh"),
]

def transform(text: str) -> str:
    out = text
    # 1. Specific: vw_TableDictionary → TableDictionary (it became a real table)
    out = re.sub(r"\bMeta\.vw_TableDictionary\b", "Meta.TableDictionary", out)
    out = re.sub(r"\bvw_TableDictionary\b", "TableDictionary", out)
    # 2. General view prefix: vw_X → v_X
    out = re.sub(r"\bvw_(?=\w)", "v_", out)
    # 3. Schema renames (use word-boundary safe replace)
    for old, new in SCHEMA_RENAMES:
        out = re.sub(rf"\b{re.escape(old)}\b", new, out)
    return out

def process_file(path: Path) -> tuple[int, int]:
    """Returns (lines_changed, total_lines)."""
    if path in EXCLUDE:
        return (0, 0)
    text = path.read_text()
    new = transform(text)
    if new != text:
        path.write_text(new)
        # rough delta count
        old_lines = text.splitlines()
        new_lines = new.splitlines()
        diffs = sum(1 for a, b in zip(old_lines, new_lines) if a != b)
        return (diffs, len(old_lines))
    return (0, len(text.splitlines()))

def main():
    targets = [
        PROJ / "README.md",
        PROJ / "00_workspace.md",
        PROJ / "10_bronze.md",
        PROJ / "20_silver.md",
        PROJ / "30_gold.md",
        PROJ / "40_pipelines.md",
        PROJ / "50_semantic.md",
        PROJ / "60_lineage.md",
        PROJ / "etl" / "staging_ddl.sql",
        PROJ / "etl" / "silver_views.sql",
        PROJ / "etl" / "gold_views.sql",
        PROJ / "etl" / "meta_sps.sql",
    ]
    print(f"Updating {len(targets)} files in {PROJ}")
    print("=" * 60)
    for p in targets:
        if not p.exists():
            print(f"  SKIP (missing): {p.relative_to(PROJ)}")
            continue
        d, t = process_file(p)
        if d > 0:
            print(f"  UPDATED: {p.relative_to(PROJ)}  ({d}/{t} lines changed)")
        else:
            print(f"  unchanged: {p.relative_to(PROJ)}")

if __name__ == "__main__":
    main()
