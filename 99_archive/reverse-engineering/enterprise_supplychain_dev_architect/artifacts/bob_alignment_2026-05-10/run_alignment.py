#!/usr/bin/env python3
"""Bob alignment runner — executes generated SQL scripts against Fabric Warehouse.

Usage:
    python3 run_alignment.py backup
    python3 run_alignment.py step <N>          # 1..12, runs single step
    python3 run_alignment.py verify            # post-rebuild row count check
    python3 run_alignment.py all               # backup + steps 1..12 sequential
"""
from __future__ import annotations
import json, struct, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path

import pyodbc

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
PROCESSING_DB = "SupplyChain_Processing_Warehouse"
GOLD_DB = "SupplyChain_Gold_Warehouse"

ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql_scripts"
LOG_DIR = ROOT / "run_logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
BACKUP_DIR = ROOT / "backup"
BACKUP_DIR.mkdir(parents=True, exist_ok=True)

OLD_SCHEMAS = ["Staging_WRK", "ReferenceMaster_ENH", "SalesHistory_ENH",
               "ForecastHistory_ENH", "OpenOrderHistory_ENH"]
NEW_SCHEMAS = ["Staging_Wrk", "ReferenceMaster_Enh", "SalesHistory_Enh",
               "ForecastHistory_Enh", "OpenOrderHistory_Enh"]


def get_token():
    raw = subprocess.run(
        ["az", "account", "get-access-token", "--resource",
         "https://database.windows.net/", "--output", "json"],
        check=True, capture_output=True, text=True)
    token = json.loads(raw.stdout)["accessToken"].encode("UTF-16-LE")
    return struct.pack(f"<I{len(token)}s", len(token), token)


def connect(db):
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};"
        f"DATABASE={db};Encrypt=yes;TrustServerCertificate=no",
        attrs_before={1256: get_token()}, timeout=120, autocommit=True
    )


def split_batches(sql_text: str) -> list[str]:
    """Split a SQL script by 'GO' delimiters (case-insensitive, line-anchored)."""
    batches = []
    current = []
    for line in sql_text.splitlines():
        if line.strip().upper() == "GO":
            blob = "\n".join(current).strip()
            if blob:
                batches.append(blob)
            current = []
        else:
            current.append(line)
    blob = "\n".join(current).strip()
    if blob:
        batches.append(blob)
    return batches


def split_semicolons(sql_text: str) -> list[str]:
    """For scripts without GO — split on semicolons."""
    parts = []
    buf = []
    for line in sql_text.splitlines():
        # skip comment-only and empty
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        buf.append(line)
        if s.endswith(";"):
            blob = "\n".join(buf).strip()
            if blob:
                parts.append(blob)
            buf = []
    if buf:
        blob = "\n".join(buf).strip()
        if blob:
            parts.append(blob)
    return parts


def run_step(step_num: int, db: str = PROCESSING_DB, dry_run: bool = False):
    files = sorted(SQL_DIR.glob(f"{step_num:02d}_*.sql"))
    if not files:
        print(f"[step {step_num}] no SQL file found")
        return
    sql_path = files[0]
    sql_text = sql_path.read_text()

    # Steps 04, 06, 07, 10, 12 contain CREATE VIEW/PROC bodies separated by GO
    has_go = any(line.strip().upper() == "GO" for line in sql_text.splitlines())
    batches = split_batches(sql_text) if has_go else split_semicolons(sql_text)

    print(f"[step {step_num}] {sql_path.name} → {len(batches)} batches → DB={db}")
    if dry_run:
        for i, b in enumerate(batches[:3]):
            print(f"  [batch {i}] {b[:80]}...")
        return

    results = {"step": step_num, "file": sql_path.name, "db": db,
               "started": datetime.now(timezone.utc).isoformat(),
               "batches": []}

    conn = connect(db)
    cur = conn.cursor()
    ok = 0
    for i, batch in enumerate(batches):
        first_line = batch.splitlines()[0][:90] if batch.splitlines() else "(empty)"
        try:
            cur.execute(batch)
            results["batches"].append({"i": i, "status": "ok", "first": first_line})
            ok += 1
        except Exception as e:
            err = str(e)
            results["batches"].append({"i": i, "status": "error",
                                        "first": first_line, "error": err})
            print(f"  [batch {i}] ERROR: {first_line[:60]} — {err[:200]}")
    cur.close()
    conn.close()

    results["ended"] = datetime.now(timezone.utc).isoformat()
    results["ok"] = ok
    results["total"] = len(batches)

    log_path = LOG_DIR / f"step_{step_num:02d}_{datetime.now().strftime('%H%M%S')}.json"
    log_path.write_text(json.dumps(results, indent=2))
    print(f"  → {ok}/{len(batches)} ok. Log: {log_path.name}")
    return results


def backup_state():
    """Capture pre-rebuild state to JSON for rollback reference."""
    print("[backup] connecting to Processing WH...")
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()

    snap = {"timestamp": datetime.now(timezone.utc).isoformat(),
            "processing_warehouse": {}}

    # AssetRegistry
    cur.execute("SELECT * FROM Meta.AssetRegistry")
    cols = [d[0] for d in cur.description]
    snap["processing_warehouse"]["AssetRegistry"] = [
        dict(zip(cols, [str(v) if v is not None else None for v in row]))
        for row in cur.fetchall()
    ]

    # DQRule
    cur.execute("SELECT * FROM Meta.DQRule")
    cols = [d[0] for d in cur.description]
    snap["processing_warehouse"]["DQRule"] = [
        dict(zip(cols, [str(v) if v is not None else None for v in row]))
        for row in cur.fetchall()
    ]

    # LineageEdge
    try:
        cur.execute("SELECT * FROM Meta.LineageEdge")
        cols = [d[0] for d in cur.description]
        snap["processing_warehouse"]["LineageEdge"] = [
            dict(zip(cols, [str(v) if v is not None else None for v in row]))
            for row in cur.fetchall()
        ]
    except Exception as e:
        snap["processing_warehouse"]["LineageEdge"] = f"error: {e}"

    # SourceContract
    try:
        cur.execute("SELECT * FROM Meta.SourceContract")
        cols = [d[0] for d in cur.description]
        snap["processing_warehouse"]["SourceContract"] = [
            dict(zip(cols, [str(v) if v is not None else None for v in row]))
            for row in cur.fetchall()
        ]
    except Exception as e:
        snap["processing_warehouse"]["SourceContract"] = f"error: {e}"

    # Row counts per old schema
    snap["processing_warehouse"]["row_counts_pre"] = {}
    for sch in OLD_SCHEMAS:
        try:
            cur.execute(f"""
                SELECT t.name AS table_name
                FROM sys.tables t
                JOIN sys.schemas s ON s.schema_id = t.schema_id
                WHERE s.name = '{sch}'
            """)
            tables = [r[0] for r in cur.fetchall()]
            counts = {}
            for tname in tables:
                try:
                    cur.execute(f"SELECT COUNT(*) FROM [{sch}].[{tname}]")
                    counts[tname] = cur.fetchone()[0]
                except Exception as e:
                    counts[tname] = f"error: {e}"
            snap["processing_warehouse"]["row_counts_pre"][sch] = counts
        except Exception as e:
            snap["processing_warehouse"]["row_counts_pre"][sch] = f"error: {e}"

    # List views per schema
    snap["processing_warehouse"]["views_pre"] = {}
    for sch in OLD_SCHEMAS:
        try:
            cur.execute(f"""
                SELECT v.name FROM sys.views v
                JOIN sys.schemas s ON s.schema_id = v.schema_id
                WHERE s.name = '{sch}'
            """)
            snap["processing_warehouse"]["views_pre"][sch] = [r[0] for r in cur.fetchall()]
        except Exception as e:
            snap["processing_warehouse"]["views_pre"][sch] = f"error: {e}"

    # SP list in Meta
    try:
        cur.execute("""
            SELECT p.name FROM sys.procedures p
            JOIN sys.schemas s ON s.schema_id = p.schema_id
            WHERE s.name = 'Meta'
        """)
        snap["processing_warehouse"]["meta_sps_pre"] = [r[0] for r in cur.fetchall()]
    except Exception as e:
        snap["processing_warehouse"]["meta_sps_pre"] = f"error: {e}"

    cur.close()
    conn.close()

    # Gold WH
    print("[backup] connecting to Gold WH...")
    conn = connect(GOLD_DB)
    cur = conn.cursor()
    snap["gold_warehouse"] = {}
    cur.execute("""
        SELECT v.name FROM sys.views v
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE s.name = 'ForecastAccuracy_DW'
    """)
    snap["gold_warehouse"]["views_pre"] = [r[0] for r in cur.fetchall()]
    cur.execute("""
        SELECT t.name FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'ForecastAccuracy_DW'
    """)
    tables = [r[0] for r in cur.fetchall()]
    counts = {}
    for tname in tables:
        try:
            cur.execute(f"SELECT COUNT(*) FROM ForecastAccuracy_DW.[{tname}]")
            counts[tname] = cur.fetchone()[0]
        except Exception as e:
            counts[tname] = f"error: {e}"
    snap["gold_warehouse"]["row_counts_pre"] = counts
    cur.close()
    conn.close()

    out = BACKUP_DIR / f"pre_state_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    out.write_text(json.dumps(snap, indent=2, default=str))
    print(f"[backup] → {out}")
    print(f"  Old schemas captured: {list(snap['processing_warehouse']['row_counts_pre'].keys())}")
    return snap


def verify_post():
    """Post-rebuild verification: row counts in new schemas match pre."""
    print("[verify] connecting to Processing WH...")
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    snap = {}
    for sch in NEW_SCHEMAS:
        cur.execute(f"""
            SELECT t.name FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = '{sch}'
        """)
        tables = [r[0] for r in cur.fetchall()]
        counts = {}
        for tname in tables:
            cur.execute(f"SELECT COUNT(*) FROM [{sch}].[{tname}]")
            counts[tname] = cur.fetchone()[0]
        snap[sch] = counts

    print(json.dumps(snap, indent=2, default=str))
    out = LOG_DIR / f"verify_post_{datetime.now().strftime('%H%M%S')}.json"
    out.write_text(json.dumps(snap, indent=2, default=str))
    cur.close()
    conn.close()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "backup":
        backup_state()
    elif cmd == "verify":
        verify_post()
    elif cmd == "step":
        step = int(sys.argv[2])
        # Routing: steps 1-4, 7-9, 10-12 → Processing WH; 5,6 → Gold WH; 8 also touches Meta only
        if step in (5, 6):
            run_step(step, db=GOLD_DB)
        else:
            run_step(step, db=PROCESSING_DB)
    elif cmd == "all":
        backup_state()
        for i in range(1, 13):
            print("=" * 60)
            print(f"=== STEP {i:02d} ===")
            print("=" * 60)
            db = GOLD_DB if i in (5, 6) else PROCESSING_DB
            run_step(i, db=db)
            time.sleep(2)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
