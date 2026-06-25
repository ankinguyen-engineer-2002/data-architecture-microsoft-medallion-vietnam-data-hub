#!/usr/bin/env python3
"""
Build a Fabric updateDefinition payload (TMDL) from a decoded `definition/` folder.

Input folder layout (example):
  definition/
    database.tmdl
    model.tmdl
    expressions.tmdl
    relationships.tmdl
    roles/*.tmdl
    tables/*.tmdl

Output JSON:
  {
    "definition": {
      "format": "TMDL",
      "parts": [
        {"path":"definition/model.tmdl","payload":"<base64>"},
        ...
      ]
    }
  }
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--definition-dir", required=True)
    parser.add_argument(
        "--pbism",
        help="Path to definition.pbism (required by Fabric semantic model updateDefinition).",
    )
    parser.add_argument("--out-json", required=True)
    args = parser.parse_args()

    definition_dir = Path(args.definition_dir).resolve()
    pbism_path = Path(args.pbism).resolve() if args.pbism else None
    out_json = Path(args.out_json).resolve()
    if not definition_dir.is_dir():
        raise SystemExit(f"Not a directory: {definition_dir}")
    if pbism_path and not pbism_path.is_file():
        raise SystemExit(f"Not a file: {pbism_path}")

    parts: list[dict[str, str]] = []
    if pbism_path:
        payload = base64.b64encode(pbism_path.read_bytes()).decode("ascii")
        parts.append({"path": "definition.pbism", "payload": payload, "payloadType": "InlineBase64"})

    for path in sorted(p for p in definition_dir.rglob("*") if p.is_file()):
        rel = path.relative_to(definition_dir).as_posix()
        payload = base64.b64encode(path.read_bytes()).decode("ascii")
        parts.append({"path": f"definition/{rel}", "payload": payload, "payloadType": "InlineBase64"})

    body = {"definition": {"format": "TMDL", "parts": parts}}
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(body, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"parts": len(parts), "out_json": str(out_json)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
