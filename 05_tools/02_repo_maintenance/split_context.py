#!/usr/bin/env python3
"""Split root CONTEXT.md into chronological chunks.

The project keeps context entries under headings that start with
`## YYYY-MM-DD ...`. This script preserves the original file, writes chunked
files that cover at most four calendar days, and rewrites the root
CONTEXT.md as a pointer to the new 00_CONTEXT/ folder.
"""

from __future__ import annotations

import argparse
import re
import shutil
from dataclasses import dataclass
from datetime import date
from pathlib import Path


HEADING_RE = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\b")


@dataclass
class Entry:
    day: date
    text: str


def parse_entries(text: str) -> tuple[str, list[Entry]]:
    lines = text.splitlines(keepends=True)
    preamble: list[str] = []
    entries: list[Entry] = []
    current: list[str] = []
    current_day: date | None = None

    for line in lines:
        match = HEADING_RE.match(line)
        if match:
            if current_day is not None:
                entries.append(Entry(current_day, "".join(current).rstrip() + "\n"))
            elif current:
                preamble.extend(current)
            current = [line]
            current_day = date.fromisoformat(match.group(1))
        else:
            current.append(line)

    if current_day is not None:
        entries.append(Entry(current_day, "".join(current).rstrip() + "\n"))
    elif current:
        preamble.extend(current)

    return "".join(preamble).rstrip() + "\n", entries


def group_entries(entries: list[Entry], max_days: int) -> list[list[Entry]]:
    groups: list[list[Entry]] = []
    current: list[Entry] = []
    start_day: date | None = None

    for entry in entries:
        if not current:
            current = [entry]
            start_day = entry.day
            continue

        assert start_day is not None
        if (entry.day - start_day).days >= max_days:
            groups.append(current)
            current = [entry]
            start_day = entry.day
        else:
            current.append(entry)

    if current:
        groups.append(current)
    return groups


def write_chunk(context_dir: Path, group: list[Entry], preamble: str | None = None) -> Path:
    start = group[0].day.isoformat()
    end = group[-1].day.isoformat()
    name = f"{start}_to_{end}.md"
    path = context_dir / name

    body: list[str] = [f"# Context {start} to {end}\n\n"]
    if preamble:
        body.append("## Source Preamble\n\n")
        body.append(preamble.strip() + "\n\n")
    body.extend(entry.text + "\n" for entry in group)
    path.write_text("".join(body).rstrip() + "\n", encoding="utf-8")
    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Repo root")
    parser.add_argument("--max-days", type=int, default=4)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    source = root / "CONTEXT.md"
    context_dir = root / "00_CONTEXT"
    source_dir = context_dir / "_source"

    text = source.read_text(encoding="utf-8")
    preamble, entries = parse_entries(text)
    groups = group_entries(entries, args.max_days)

    print(f"source={source}")
    print(f"entries={len(entries)} groups={len(groups)} max_days={args.max_days}")
    for group in groups:
        print(f"chunk={group[0].day.isoformat()}..{group[-1].day.isoformat()} entries={len(group)}")

    if not args.execute:
        return

    context_dir.mkdir(exist_ok=True)
    source_dir.mkdir(exist_ok=True)
    backup = source_dir / "CONTEXT_full_before_split_20260623.md"
    shutil.copy2(source, backup)

    chunk_paths: list[Path] = []
    for index, group in enumerate(groups):
        chunk_paths.append(write_chunk(context_dir, group, preamble if index == 0 else None))

    current = context_dir / "current.md"
    shutil.copy2(chunk_paths[-1], current)

    readme_lines = [
        "# CONTEXT\n\n",
        "This folder replaces the old single root `CONTEXT.md` log.\n\n",
        "Rules:\n\n",
        "- Each dated context chunk covers at most four calendar days.\n",
        "- `current.md` mirrors the latest chunk and is the default append target for active work.\n",
        "- `_source/CONTEXT_full_before_split_20260623.md` preserves the original unsplit file.\n",
        "- Do not create parallel context folders; update this folder and keep `AGENTS.md` in sync.\n\n",
        "Chunks:\n\n",
    ]
    for path in chunk_paths:
        readme_lines.append(f"- [{path.name}]({path.name})\n")
    (context_dir / "README.md").write_text("".join(readme_lines), encoding="utf-8")

    source.write_text(
        "# CONTEXT moved\n\n"
        "The active project context is now stored in [`00_CONTEXT/current.md`](00_CONTEXT/current.md).\n\n"
        "Historical context chunks live in [`00_CONTEXT/`](00_CONTEXT/), with each file covering at most four calendar days.\n"
        "The original full file is preserved at [`00_CONTEXT/_source/CONTEXT_full_before_split_20260623.md`](00_CONTEXT/_source/CONTEXT_full_before_split_20260623.md).\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
