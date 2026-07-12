#!/usr/bin/env python3
"""Module 05 — Downstream serving parity + performance baseline (READ-ONLY).

Closes the Wave 0 open gates from
`01_docs/plans/2026-07-10-inventory-gold-wave0-evidence-pack.md`:
  - Layer F (downstream serving): view-vs-table sanity for the 9 Gold targets,
    proving Module 03's frozen baseline still reconciles against the live view
    (i.e. the oracle is not silently stale).
  - Layer G (performance baseline): aggregate perf stats from
    `queryinsights.exec_requests_history` for each INSERT ... _LOAD from view,
    over a rolling window. This is the mandatory mark that any Wave 1 candidate
    B has to beat.
  - Optional end-to-end A-vs-B for the small consumers (SubStatusWeekly and
    InventoryClassificationQtyWeekly), so we prove parity of the full serving
    tuple beyond the inv_base slice already proven in Module 04.

Safety (hard contract):
  - ApplicationIntent=ReadOnly
  - SELECT + metadata only. No CREATE/ALTER/DROP/INSERT/UPDATE/DELETE.
  - No live production object is created, modified, or dropped.

Sub-commands:
  --perf                Perf baseline from queryinsights (default: 30 days).
  --sanity              Cheap view-vs-table check. Default: row count only for
                        every target + measure sums only for light targets
                        (dims + SubStatus + ClassQty). Heavy views
                         (FactSnapshot, FactFutureWeekEnding, Projected,
                         SubStatus, ClassQty) receive row-count-only checks
                         unless --measures-for is provided.
   --include-target NAME Restrict sanity to a target table name (repeatable).
   --measures-for NAME   Opt in to measure SUM recompute for a heavy target
                         (repeatable; SLOW).
  --e2e-substatus       Live-vs-live full-tuple A-vs-B for
                        InventoryHealthSubStatusWeekly + InventoryClassificationQtyWeekly.
                        (A = live final table. B = live _Wrk view recomputed.)
  --all                 Run --perf + --sanity (skips e2e by default; opt in).

Output:
  runs/<stamp>_downstream_perf_<mode>.json
  runs/<stamp>_downstream_perf_<mode>.txt

Usage:
  python3 05_tools/03_gold_parity/05_downstream_perf.py --perf --days 30
  python3 05_tools/03_gold_parity/05_downstream_perf.py --sanity
  python3 05_tools/03_gold_parity/05_downstream_perf.py --sanity-target FactInventoryHealthSnapshot
  python3 05_tools/03_gold_parity/05_downstream_perf.py --e2e-substatus
  python3 05_tools/03_gold_parity/05_downstream_perf.py --all
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import lib_conn as L

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
CONTRACTS = HERE / "contracts"


# --------------------------------------------------------------------------- #
# Layer G — Performance baseline from queryinsights.exec_requests_history
# --------------------------------------------------------------------------- #

def run_perf(conn, days: int) -> dict:
    """Aggregate INSERT ... _LOAD SELECT * FROM v_* stats per target.

    Note: allocated_cpu_time_ms is aggregate across the distributed engine, so
    it can far exceed wall clock (elapsed_sec). Both are captured.
    """
    per_target: dict[str, dict] = {}
    for t in L.GOLD_TARGETS:
        pat = f"%INSERT INTO {t.db}.{t.schema}.{t.table}_LOAD%"
        sql = f"""
            SELECT
                start_time,
                DATEDIFF(second, start_time, end_time) AS elapsed_sec,
                total_elapsed_time_ms,
                allocated_cpu_time_ms,
                data_scanned_remote_storage_mb,
                data_scanned_memory_mb,
                data_scanned_disk_mb,
                row_count,
                [status]
            FROM queryinsights.exec_requests_history
            WHERE command LIKE ?
              AND start_time >= DATEADD(day, -{days}, SYSUTCDATETIME())
              AND statement_type = 'INSERT'
              AND [status] = 'Succeeded'
            ORDER BY start_time DESC
        """
        rows = L.query(conn, sql, (pat,))
        if not rows:
            per_target[t.table] = {"executions": 0}
            continue

        def col(k):
            return [
                float(r[k])
                for r in rows
                if r.get(k) is not None
            ]

        elapsed = col("elapsed_sec")
        cpu = col("allocated_cpu_time_ms")
        rem = col("data_scanned_remote_storage_mb")
        mem = col("data_scanned_memory_mb")
        disk = col("data_scanned_disk_mb")
        rc = col("row_count")

        def stat(v: list[float]) -> dict:
            if not v:
                return {}
            v_sorted = sorted(v)
            return {
                "n": len(v),
                "min": min(v),
                "median": statistics.median(v),
                "p95": v_sorted[max(0, int(round(0.95 * (len(v) - 1))))],
                "max": max(v),
                "mean": statistics.mean(v),
            }

        per_target[t.table] = {
            "executions": len(rows),
            "window_days": days,
            "first_seen_utc": str(rows[-1]["start_time"]),
            "last_seen_utc": str(rows[0]["start_time"]),
            "elapsed_sec": stat(elapsed),
            "allocated_cpu_ms": stat(cpu),
            "remote_scan_mb": stat(rem),
            "memory_scan_mb": stat(mem),
            "disk_scan_mb": stat(disk),
            "row_count": stat(rc),
        }

    total_median_elapsed = sum(
        (v.get("elapsed_sec", {}).get("median") or 0.0)
        for v in per_target.values()
    )
    total_median_remote = sum(
        (v.get("remote_scan_mb", {}).get("median") or 0.0)
        for v in per_target.values()
    )

    return {
        "check": "Layer_G_perf_baseline",
        "source": "queryinsights.exec_requests_history",
        "window_days": days,
        "per_target": per_target,
        "chain_median_elapsed_sec_sum": total_median_elapsed,
        "chain_median_remote_scan_mb_sum": total_median_remote,
        "note": (
            "Serial dbo.Usp_Refresh_InventoryHealth_Gold is a chain of these "
            "INSERTs; chain_median_elapsed_sec_sum approximates the current "
            "typical Gold refresh wall-clock lower bound. Any Wave 1 candidate "
            "must beat this while proving business parity."
        ),
    }


# --------------------------------------------------------------------------- #
# Layer F — View vs Table sanity per target (oracle-still-valid probe)
# --------------------------------------------------------------------------- #

# Anchor measures per target: business grand totals that must match view vs table.
# Use the columns we already froze in Module 03 baseline for reproducibility.
# Recomputing these views from the live _Wrk definition is essentially a Gold
# refresh at the SELECT-only level, i.e. it takes minutes and re-scans the same
# 705M-row source that the plan already flagged as the bottleneck. Skip measure
# recompute for these by default; use --measures-for=<name> to opt in.
HEAVY_VIEW_TARGETS = {
    "FactInventoryHealthSnapshot",
    "FactInventoryHealthFutureWeekEnding",
    "ProjectedInventoryHealthSubStatus",
    "InventoryHealthSubStatusWeekly",
    "InventoryClassificationQtyWeekly",
}


SANITY_MEASURES: dict[str, list[str]] = {
    "FactInventoryHealthSnapshot": [
        "OnHandQty", "OnHandValue", "OnOrderQty", "SIQty", "ShortageValue",
    ],
    "FactInventoryHealthFutureWeekEnding": [
        "ProjectedOnHandQty", "ProjectedInboundQty", "ProjectedOutboundQty",
    ],
    "ProjectedInventoryHealthSubStatus": [],  # non-numeric-heavy, count only
    "InventoryHealthSubStatusWeekly": ["OnHandQty"],
    "InventoryClassificationQtyWeekly": [
        "QtyByInventoryClassification(InActive)",
        "QtyByInventoryClassification(SLOB)",
        "QtyByInventoryClassification(BelowTarget)",
        "QtyByInventoryClassification(SweetSpot)",
        "QtyByInventoryClassification(OverTarget)",
        "QtyByInventoryClassification(Excess)",
        "QtyByInventoryClassification(AE)",
        "QtyByInventoryClassification(TBInventory)",
    ],
    "DimCalendar": [],
    "DimProduct": [],
    "DimWarehouse": [],
    "DimVendor": [],
}

def _b(col: str) -> str:
    return "[" + col.replace("]", "]]") + "]"


def _measure_projection(cols: list[str]) -> str:
    parts = [f"COUNT(*) AS n"]
    for c in cols:
        parts.append(
            f"CAST(SUM(CAST({_b(c)} AS DECIMAL(38,6))) AS DECIMAL(38,6)) "
            f"AS {_b('sum_' + c)}"
        )
    return ", ".join(parts)


def _get_actual_view_columns(conn, t: L.GoldTarget) -> set[str]:
    sql = """
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
    """
    rows = L.query(conn, sql, (t.view_schema, t.view))
    return {r["COLUMN_NAME"] for r in rows}


def run_sanity(
    conn,
    include_targets: set[str] | None = None,
    with_measures_for: set[str] | None = None,
) -> dict:
    """For each Gold target, live view vs live table rowcount + measure sums.

    Live view is recomputed on each SELECT; live table is what serves report.
    A drift here means the oracle (Module 03 frozen baseline) is no longer
    valid until a new baseline snapshot is captured.

    include_targets: if set, only run those. Default: all 9.
    with_measures_for: targets to also run SUM measure recompute. For every
        HEAVY_VIEW_TARGETS not in this set, only rowcount is compared. This
        avoids re-running a Gold refresh through the sanity harness.
    """
    per_target: dict[str, dict] = {}
    with_measures_for = with_measures_for or set()
    for t in L.GOLD_TARGETS:
        if include_targets and t.table not in include_targets:
            continue
        do_measures = (
            t.table not in HEAVY_VIEW_TARGETS
            or t.table in with_measures_for
        )
        wanted = SANITY_MEASURES.get(t.table, []) if do_measures else []
        available = _get_actual_view_columns(conn, t)
        skipped = [c for c in wanted if c not in available]
        measures = [c for c in wanted if c in available]
        proj = _measure_projection(measures)
        table_full = f"[{t.db}].[{t.schema}].[{t.table}]"
        view_full = f"[{t.db}].[{t.view_schema}].[{t.view}]"

        t0 = time.time()
        try:
            table_row = L.query(conn, f"SELECT {proj} FROM {table_full}")[0]
        except Exception as e:
            table_row = {"__error__": str(e)[:200]}
        try:
            view_row = L.query(conn, f"SELECT {proj} FROM {view_full}")[0]
        except Exception as e:
            view_row = {"__error__": str(e)[:200]}
        elapsed = round(time.time() - t0, 1)

        diffs = {}
        if "__error__" not in table_row and "__error__" not in view_row:
            for k in table_row.keys():
                tv = table_row[k]
                vv = view_row.get(k)
                if str(tv) != str(vv):
                    diffs[k] = {
                        "table": str(tv) if tv is not None else None,
                        "view": str(vv) if vv is not None else None,
                    }

        per_target[t.table] = {
            "table": table_full,
            "view": view_full,
            "elapsed_sec": elapsed,
            "measures_checked": measures,
            "measures_skipped_not_in_view": skipped,
            "table_side": {
                k: (str(v) if v is not None else None) for k, v in table_row.items()
            },
            "view_side": {
                k: (str(v) if v is not None else None) for k, v in view_row.items()
            },
            "diffs": diffs,
            "pass": not diffs and "__error__" not in table_row
            and "__error__" not in view_row,
        }

    all_pass = all(v.get("pass") for v in per_target.values())
    return {
        "check": "Layer_F_view_vs_table_sanity",
        "per_target": per_target,
        "pass": all_pass,
        "note": (
            "View recompute vs live final table for row count and anchor SUMs. "
            "Any diff means Module 03 baseline may be stale; a new baseline "
            "should be captured before Wave 1 candidate comparison."
        ),
    }


# --------------------------------------------------------------------------- #
# Layer D end-to-end — full-tuple A-vs-B for small consumers (12 cols each)
# --------------------------------------------------------------------------- #

def _full_view_columns(conn, t: L.GoldTarget) -> list[str]:
    sql = """
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    """
    rows = L.query(conn, sql, (t.view_schema, t.view))
    return [r["COLUMN_NAME"] for r in rows]


def run_e2e_view_vs_table(conn, target_name: str, timeout: int = 1800) -> dict:
    """Full-tuple A-vs-B: live table (A) vs live view recompute (B).

    Uses key anti-join + null-safe value mismatch, same shape as Module 04 T3/T4
    for the full history.

    Business key = declared t.business_key; value cols = every non-key column.
    """
    t = L.target_by_name(target_name)
    if t is None:
        return {"check": "e2e", "target": target_name, "error": "unknown target"}

    keys = list(t.business_key)
    view_cols = _full_view_columns(conn, t)
    if not view_cols:
        return {"check": "e2e", "target": target_name, "error": "no view cols"}

    value_cols = [c for c in view_cols if c not in set(keys)]
    if not value_cols:
        return {"check": "e2e", "target": target_name, "error": "no value cols"}

    tbl = f"[{t.db}].[{t.schema}].[{t.table}]"
    vw = f"[{t.db}].[{t.view_schema}].[{t.view}]"

    key_join = " AND ".join(
        f"a.{_b(k)} = b.{_b(k)}" for k in keys
    )

    val_mismatch = " OR ".join(
        f"(a.{_b(c)} <> b.{_b(c)} "
        f"OR (a.{_b(c)} IS NULL AND b.{_b(c)} IS NOT NULL) "
        f"OR (a.{_b(c)} IS NOT NULL AND b.{_b(c)} IS NULL))"
        for c in value_cols
    )

    # Do not combine these into scalar subqueries over CTEs. Fabric inlines each
    # CTE reference, which expands the serving view repeatedly and can hold a
    # single ODBC request long enough to lose its TCP session. These four exact,
    # read-only queries each expand the view once and retain the same proof.
    #
    # Each heavy count also runs on its OWN short-lived connection with one retry:
    # a long anti-join can drop the TCP session (08S01 0x36), which otherwise
    # marks the shared connection unrecoverable (IMC06) and fails every query
    # after it. Fresh-connection-per-query isolates that failure. Read-only only.
    def one(label: str, sql: str, attempts: int = 2) -> tuple[int | None, dict]:
        t0 = time.time()
        last_err = None
        for attempt in range(1, attempts + 1):
            c2 = None
            try:
                c2 = L.connect(L.GOLD_DB, timeout=timeout)
                value = int(L.query(c2, sql)[0]["n"] or 0)
                return value, {
                    "label": label,
                    "elapsed_sec": round(time.time() - t0, 1),
                    "attempts": attempt,
                }
            except Exception as exc:
                last_err = exc
            finally:
                if c2 is not None:
                    try:
                        c2.close()
                    except Exception:
                        pass
        return None, {
            "label": label,
            "elapsed_sec": round(time.time() - t0, 1),
            "attempts": attempts,
            "error": str(last_err)[:300],
        }

    a, a_meta = one("a_rows", f"SELECT COUNT(*) AS n FROM {tbl}")
    b, b_meta = one("b_rows", f"SELECT COUNT(*) AS n FROM {vw}")
    a_not_b, ab_meta = one(
        "a_not_in_b",
        f"SELECT COUNT(*) AS n FROM {tbl} a "
        f"WHERE NOT EXISTS (SELECT 1 FROM {vw} b WHERE {key_join})",
    )
    b_not_a, ba_meta = one(
        "b_not_in_a",
        f"SELECT COUNT(*) AS n FROM {vw} b "
        f"WHERE NOT EXISTS (SELECT 1 FROM {tbl} a WHERE {key_join})",
    )
    val, val_meta = one(
        "value_mismatches",
        f"SELECT COUNT(*) AS n FROM {tbl} a "
        f"INNER JOIN {vw} b ON {key_join} WHERE {val_mismatch}",
    )
    execution = [a_meta, b_meta, ab_meta, ba_meta, val_meta]
    elapsed = round(sum(x["elapsed_sec"] for x in execution), 1)
    all_pass = (
        None not in (a, b, a_not_b, b_not_a, val)
        and a == b and a_not_b == 0 and b_not_a == 0 and val == 0
    )
    return {
        "check": f"Layer_D_e2e_{target_name}",
        "elapsed_sec": elapsed,
        "table": tbl,
        "view": vw,
        "keys": keys,
        "value_col_count": len(value_cols),
        "a_rows": a,
        "b_rows": b,
        "a_not_in_b": a_not_b,
        "b_not_in_a": b_not_a,
        "value_mismatches": val,
        "query_execution": execution,
        "pass": all_pass,
    }


# --------------------------------------------------------------------------- #
# CLI + report writer
# --------------------------------------------------------------------------- #

def write_report(out: dict, mode: str) -> tuple[Path, Path]:
    stamp = out["generated_at_utc"]
    RUNS.mkdir(exist_ok=True)
    j = RUNS / f"{stamp}_downstream_perf_{mode}.json"
    txt = RUNS / f"{stamp}_downstream_perf_{mode}.txt"
    j.write_text(json.dumps(out, indent=2, default=L.json_default), encoding="utf-8")

    lines = [
        f"Module 05 downstream + perf — mode={mode}",
        f"generated_at_utc={stamp}",
        f"overall_pass={out.get('overall_pass')}",
        f"live_ddl_dml=none",
        "",
    ]
    for c in out.get("checks", []):
        lines.append(f"[{c.get('check')}] pass={c.get('pass', 'n/a')}")
        if c.get("check") == "Layer_G_perf_baseline":
            lines.append(f"  window_days={c['window_days']}")
            lines.append(
                f"  chain_median_elapsed_sec_sum={c['chain_median_elapsed_sec_sum']:.1f}"
            )
            lines.append(
                f"  chain_median_remote_scan_mb_sum="
                f"{c['chain_median_remote_scan_mb_sum']:.1f}"
            )
            for name, s in c["per_target"].items():
                if s.get("executions", 0) == 0:
                    lines.append(f"  - {name}: no executions in window")
                    continue
                lines.append(
                    f"  - {name}: n={s['executions']} "
                    f"elapsed_med={s['elapsed_sec']['median']:.0f}s "
                    f"elapsed_p95={s['elapsed_sec']['p95']:.0f}s "
                    f"remote_med={s['remote_scan_mb']['median']:.0f}MB "
                    f"rows_med={s['row_count']['median']:.0f}"
                )
        elif c.get("check") == "Layer_F_view_vs_table_sanity":
            for name, s in c["per_target"].items():
                bad = len(s.get("diffs") or {})
                skipped = s.get("measures_skipped_not_in_view") or []
                skip_note = f" skipped={skipped}" if skipped else ""
                lines.append(
                    f"  - {name}: pass={s['pass']} "
                    f"table.n={s['table_side'].get('n')} "
                    f"view.n={s['view_side'].get('n')} "
                    f"diffs={bad} elapsed={s['elapsed_sec']}s{skip_note}"
                )
        elif str(c.get("check", "")).startswith("Layer_D_e2e_"):
            lines.append(
                f"  a_rows={c.get('a_rows')} b_rows={c.get('b_rows')} "
                f"a_not_b={c.get('a_not_in_b')} b_not_a={c.get('b_not_in_a')} "
                f"value_mismatches={c.get('value_mismatches')} "
                f"elapsed={c.get('elapsed_sec')}s"
            )
        lines.append("")

    txt.write_text("\n".join(lines), encoding="utf-8")
    return j, txt


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Module 05 downstream + perf (read-only)."
    )
    ap.add_argument("--perf", action="store_true", help="Perf baseline")
    ap.add_argument("--sanity", action="store_true", help="View vs table sanity")
    ap.add_argument(
        "--e2e-substatus", action="store_true",
        help="Full-tuple A-vs-B for SubStatusWeekly + InventoryClassificationQtyWeekly",
    )
    ap.add_argument("--all", action="store_true",
                    help="Run --perf + --sanity (excludes e2e)")
    ap.add_argument("--days", type=int, default=30,
                    help="Perf window in days (default 30)")
    ap.add_argument(
        "--include-target", action="append", default=[],
        help="Restrict --sanity to these Gold target table names (repeatable). "
             "Default: all 9.",
    )
    ap.add_argument(
        "--measures-for", action="append", default=[],
        help="Opt-in measure SUM recompute for heavy view targets. Rowcount-only "
             "otherwise. Repeatable.",
    )
    ap.add_argument("--timeout", type=int, default=1800)
    args = ap.parse_args()

    if not any([args.perf, args.sanity, args.e2e_substatus, args.all]):
        args.all = True
        print("NOTE: no flag; defaulting to --all")

    do_perf = args.perf or args.all
    do_sanity = args.sanity or args.all
    do_e2e = args.e2e_substatus

    mode_parts = []
    if do_perf: mode_parts.append("perf")
    if do_sanity: mode_parts.append("sanity")
    if do_e2e: mode_parts.append("e2e")
    mode = "_".join(mode_parts) if mode_parts else "noop"

    stamp = L.utc_stamp()
    out: dict = {
        "generated_at_utc": stamp,
        "module": "05_downstream_perf",
        "safety": {
            "application_intent": "ReadOnly",
            "ddl_dml": "none",
            "live_objects_created": [],
            "live_objects_mutated": [],
        },
        "server": L.SERVER,
        "checks": [],
    }
    print(f"=== Module 05 ({mode}) — read-only ===")

    conn = L.connect(L.GOLD_DB, timeout=args.timeout)
    checks: list[dict] = []

    if do_perf:
        print("-- Layer G perf baseline --")
        c = run_perf(conn, args.days)
        c["pass"] = True  # informational; no pass/fail
        checks.append(c)
        print(f"  window={args.days}d  "
              f"chain_median_elapsed={c['chain_median_elapsed_sec_sum']:.0f}s  "
              f"chain_median_remote_mb={c['chain_median_remote_scan_mb_sum']:.0f}")
        for name, s in c["per_target"].items():
            if s.get("executions", 0) == 0:
                print(f"    {name}: no executions in window")
            else:
                print(
                    f"    {name}: n={s['executions']} "
                    f"med={s['elapsed_sec']['median']:.0f}s "
                    f"p95={s['elapsed_sec']['p95']:.0f}s "
                    f"rem_med={s['remote_scan_mb']['median']:.0f}MB"
                )

    if do_sanity:
        include = set(args.include_target) if args.include_target else None
        measures_for = set(args.measures_for) if args.measures_for else None
        print("-- Layer F view-vs-table sanity --")
        print(f"    include={sorted(include) if include else 'ALL'}  "
              f"measures_for={sorted(measures_for) if measures_for else 'light-targets-only'}")
        c = run_sanity(conn, include_targets=include, with_measures_for=measures_for)
        checks.append(c)
        for name, s in c["per_target"].items():
            print(
                f"    {name}: pass={s['pass']} "
                f"table.n={s['table_side'].get('n')} "
                f"view.n={s['view_side'].get('n')} "
                f"diffs={len(s.get('diffs') or {})} "
                f"({s['elapsed_sec']}s)"
            )

    if do_e2e:
        e2e_targets = args.include_target or [
            "InventoryHealthSubStatusWeekly",
            "InventoryClassificationQtyWeekly",
        ]
        for name in e2e_targets:
            print(f"-- Layer D e2e {name} --")
            c = run_e2e_view_vs_table(conn, name, timeout=args.timeout)
            checks.append(c)
            print(
                f"    a={c.get('a_rows')} b={c.get('b_rows')} "
                f"a_not_b={c.get('a_not_in_b')} b_not_a={c.get('b_not_in_a')} "
                f"val_mis={c.get('value_mismatches')} "
                f"pass={c.get('pass')} ({c.get('elapsed_sec')}s)"
            )

    conn.close()

    overall_pass = all(bool(c.get("pass", True)) for c in checks)
    out["checks"] = checks
    out["overall_pass"] = overall_pass

    j, txt = write_report(out, mode)
    print()
    print(f"overall_pass={overall_pass}")
    print(f"Wrote {j}")
    print(f"Wrote {txt}")
    return 0 if overall_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
