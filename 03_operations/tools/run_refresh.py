#!/usr/bin/env python3
"""Dry-run or execute Fabric refresh manifests.

Default behavior is dry-run. Live execution requires --execute and explicit
same-conversation approval from Aric.

Supports two runtime modes:
- wrapper_sp (current): direct SP execution via pyodbc/az token
- dataPipelineExecute (legacy): Fabric DataPipeline REST trigger
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


FABRIC_RESOURCE = "https://api.fabric.microsoft.com"
SQL_SERVER = os.getenv("FABRIC_SQL_SERVER", "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com")
SQL_COPT_SS_ACCESS_TOKEN = 1256


def load_manifest(path: Path) -> dict[str, Any]:
    if path.suffix.lower() != ".json":
        raise SystemExit("Use the JSON manifest for tooling. YAML manifests are human-readable mirrors.")
    return json.loads(path.read_text(encoding="utf-8"))


def az_rest(method: str, url: str, body: dict[str, Any] | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["az", "rest", "--method", method, "--url", url, "--resource", FABRIC_RESOURCE, "--only-show-errors"]
    if body is not None:
        cmd.extend(["--body", json.dumps(body)])
    cmd.extend(["-o", "json"])
    return subprocess.run(cmd, check=False, text=True, capture_output=True)


def get_db_token() -> str:
    r = subprocess.run(
        ["az", "account", "get-access-token", "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(f"az token failed: {r.stderr}")
    return r.stdout.strip()


def execute_sp(database: str, procedure: str) -> tuple[bool, str, float]:
    """Execute a stored procedure via pyodbc. Returns (ok, message, elapsed_sec)."""
    try:
        import pyodbc
    except ImportError:
        return False, "pyodbc not installed", 0

    token = get_db_token()
    raw = token.encode("UTF-16-LE")
    token_attr = struct.pack(f"<I{len(raw)}s", len(raw), raw)

    start = time.time()
    try:
        conn = pyodbc.connect(
            f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SQL_SERVER};DATABASE={database};"
            "Encrypt=yes;TrustServerCertificate=no;",
            attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_attr},
            timeout=120, autocommit=True)
        cur = conn.cursor()
        cur.execute(f"EXEC {procedure}")
        conn.close()
        elapsed = time.time() - start
        return True, f"OK ({elapsed:.1f}s)", elapsed
    except Exception as e:
        elapsed = time.time() - start
        return False, str(e), elapsed


def print_manifest(manifest: dict[str, Any]) -> None:
    api = manifest.get("pipeline", {}).get("api", "unknown")
    wave_algo = manifest.get("wave_algorithm", "")
    print(f"manifest={manifest.get('name', manifest.get('mart', '?'))}")
    print(f"api={api}" + (f"  wave_algorithm={wave_algo}" if wave_algo else ""))

    # Print wrapper procedures if present
    wrapper_procedures = manifest.get("wrapper_procedures")
    if wrapper_procedures:
        print("wrapper_procedures:")
        for w in sorted(wrapper_procedures, key=lambda item: item.get("step", 0)):
            step = w.get("step", "")
            db = w.get("database", "")
            schema = w.get("schema", "dbo")
            proc = w.get("procedure", "")
            purpose = w.get("purpose", "")
            print(f"  {step:>4} [{db}].[{schema}].[{proc}]  -- {purpose}" if purpose else f"  {step:>4} [{db}].[{schema}].[{proc}]")

    # Print run order sequence
    sequence = manifest.get("sequence", [])
    if sequence:
        print("\nrun_order:")
        for s in sequence:
            label = s.get("object") or s.get("purpose") or s.get("project") or "?"
            wave = str(s.get("wave", ""))
            load_type = s.get("load_type", "")
            print(f"  {s['step']:>4}  wave={wave:<18} {load_type:<14} {label}")

    if manifest.get("post_run_checks"):
        print("post_run_checks:")
        for check in manifest["post_run_checks"]:
            print(f"  - {check}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Dry-run or execute Fabric refresh manifests.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--execute", action="store_true", help="Execute wrapper SPs on live Fabric.")
    parser.add_argument("--list-jobs", action="store_true", help="List recent pipeline jobs (dataPipelineExecute only).")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    print_manifest(manifest)

    api = manifest.get("pipeline", {}).get("api", "dataPipelineExecute")

    if args.list_jobs:
        if api != "dataPipelineExecute":
            print("list-jobs only supported for dataPipelineExecute manifests")
            return 1
        ws_id = manifest["workspace_id"]
        pl_id = manifest["pipeline"]["id"]
        url = f"{FABRIC_RESOURCE}/v1/workspaces/{ws_id}/dataPipelines/{pl_id}/jobs/execute/instances"
        print(f"GET {url}")
        result = az_rest("get", url)
        sys.stdout.write(result.stdout)
        return result.returncode

    if not args.execute:
        print("\ndry_run=true — use --execute to run wrapper SPs on live Fabric")
        return 0

    # Execute wrapper procedures
    wrappers = manifest.get("wrapper_procedures", [])
    if not wrappers:
        print("No wrapper_procedures found in manifest. Nothing to execute.")
        return 1

    print(f"\n=== Executing {len(wrappers)} wrapper SPs on live Fabric ===")
    total_start = time.time()
    results = []
    for w in sorted(wrappers, key=lambda item: item.get("step", 0)):
        db = w["database"]
        proc = f"[{w.get('schema', 'dbo')}].[{w['procedure']}]"
        label = w.get("purpose", w["procedure"])
        print(f"[{w['step']}] {proc} ...", end=" ", flush=True)
        ok, msg, elapsed = execute_sp(db, proc)
        results.append((w["step"], proc, ok, msg, elapsed))
        print(msg)

    total = time.time() - total_start
    ok_count = sum(1 for _, _, ok, _, _ in results if ok)
    print(f"\n=== {ok_count}/{len(results)} OK — {total:.1f}s total ===")
    for step, proc, ok, msg, elapsed in results:
        status = "OK" if ok else "FAIL"
        print(f"  [{step}] {proc}: {status} ({elapsed:.1f}s)" + (f" — {msg}" if not ok else ""))

    return 0 if ok_count == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
