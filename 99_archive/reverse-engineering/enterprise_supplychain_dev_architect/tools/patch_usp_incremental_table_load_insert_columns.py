#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    """Compatibility wrapper.

    Use `patch_usp_incremental_table_load_insert_columns_v2.py` as the source of truth.
    """

    target = Path(__file__).with_name("patch_usp_incremental_table_load_insert_columns_v2.py")
    if not target.exists():
        print(f"Missing required script: {target}", file=sys.stderr)
        return 2
    return subprocess.call([sys.executable, str(target), *sys.argv[1:]])


if __name__ == "__main__":
    raise SystemExit(main())
