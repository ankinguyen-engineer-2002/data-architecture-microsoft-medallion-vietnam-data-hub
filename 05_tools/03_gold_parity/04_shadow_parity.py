#!/usr/bin/env python3
"""Module 04 — C1 inline shadow parity (READ-ONLY) for Inventory Health Gold.

Proves candidate C1 (shared deduped inv_base) is business-parity-safe against
current per-view inv_base logic WITHOUT creating any live object.

Safety contract (hard):
  - ApplicationIntent=ReadOnly
  - SELECT / metadata only
  - No CREATE/ALTER/DROP/INSERT/UPDATE/DELETE/TRUNCATE
  - No mutation of production serving objects

C1 design under test (superset shared surface):
  shared_inv_base =
    ROW_NUMBER() OVER (
      PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
      ORDER BY FiscalMonthDate ASC
    ) = 1
    over ALL rows of InventorySnapshotWeekly
    carrying: OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName,
              ReplenishmentLeadTime, SnapshotType

Consumer filters (applied AFTER shared pick, matching live semantics):
  - SubStatus / ClassQty: no extra filter (today's inv_base is already unfiltered)
  - FactSnapshot: non-null keys + SnapshotType IN ('WEEKLY','WEEKLY_AND_LATEST')

Checks:
  T1  R3 extended — multi-row groups where carried cols differ; FMD ties
  T2  Shared surface counts (all / non-null / weekly-eligible)
  T3  A-vs-B two-way anti-join: FactSnapshot inv_base (NULL-before-RN)
      vs shared-then-NULL-filter (same carried columns)
  T4  A-vs-B two-way anti-join: SubStatus inv_base (OnHandQty only)
      vs shared surface projected to OnHandQty
  T5  SnapshotType of rn=1 non-null rows (explains FactSnapshot Δ vs weekly family)

Optional bound:
  --recent-weeks N   limit source to last N distinct SnapshotWeekEndingDate
                     values (fast smoke). Omit for full-history proof.

Usage:
  python3 05_tools/03_gold_parity/04_shadow_parity.py --recent-weeks 8
  python3 05_tools/03_gold_parity/04_shadow_parity.py --full
  python3 05_tools/03_gold_parity/04_shadow_parity.py --full --only-antijoin
  python3 05_tools/03_gold_parity/04_shadow_parity.py --full --skip-antijoin
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import lib_conn as L

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
PROC = L.PROC_DB
SRC = f"[{PROC}].[InventoryHistory_Enh].[InventorySnapshotWeekly]"

# Columns carried by FactSnapshot inv_base (live view).
CARRIED = [
    "ItemSku",
    "WarehouseCode",
    "SnapshotWeekEndingDate",
    "OnHandQty",
    "MakeBuyCode",
    "PrimaryVendorName",
    "SecondaryVendorName",
    "ReplenishmentLeadTime",
    "SnapshotType",
]
# Columns used by SubStatus/ClassQty inv_base.
SS_COLS = ["ItemSku", "WarehouseCode", "SnapshotWeekEndingDate", "OnHandQty"]

# Carried non-key columns whose within-group variation makes ORDER BY material.
VALUE_COLS = [
    "OnHandQty",
    "MakeBuyCode",
    "PrimaryVendorName",
    "SecondaryVendorName",
    "ReplenishmentLeadTime",
    "SnapshotType",
]


def b(col: str) -> str:
    return "[" + col.replace("]", "]]") + "]"


def source_cte(recent_weeks: int | None) -> str:
    """Bounded or full source CTE. Bound uses top-N distinct week endings."""
    if recent_weeks is None:
        return f"src AS (SELECT * FROM {SRC})"
    return f"""
src AS (
    SELECT s.*
    FROM {SRC} s
    INNER JOIN (
        SELECT DISTINCT TOP ({int(recent_weeks)}) SnapshotWeekEndingDate
        FROM {SRC}
        WHERE SnapshotWeekEndingDate IS NOT NULL
        ORDER BY SnapshotWeekEndingDate DESC
    ) w
      ON w.SnapshotWeekEndingDate = s.SnapshotWeekEndingDate
)"""


def nullsafe_distinct_expr(col: str) -> str:
    """Null-safe 'distinct value count' for a column within a group.

    COUNT(DISTINCT col) ignores NULLs; add 1 if any NULL present so a group
    with both NULL and non-NULL counts as multi-valued.
    """
    c = b(col)
    return (
        f"(COUNT(DISTINCT {c}) "
        f"+ CASE WHEN SUM(CASE WHEN {c} IS NULL THEN 1 ELSE 0 END) > 0 "
        f"AND COUNT(DISTINCT {c}) >= 1 THEN 1 "
        f"WHEN SUM(CASE WHEN {c} IS NULL THEN 1 ELSE 0 END) > 0 "
        f"AND COUNT(DISTINCT {c}) = 0 THEN 1 "
        f"ELSE 0 END)"
    )


def run_t1_r3_extended(conn, recent_weeks: int | None) -> dict:
    """Close R3 gap: within multi-row groups, do carried columns differ?

    Also re-confirm FiscalMonthDate ties (non-determinism).
    """
    src = source_cte(recent_weeks)
    sql = f"""
    WITH {src},
    g AS (
        SELECT
            ItemSku, WarehouseCode, SnapshotWeekEndingDate,
            COUNT(*) AS c,
            COUNT(DISTINCT FiscalMonthDate)
              + CASE WHEN SUM(CASE WHEN FiscalMonthDate IS NULL THEN 1 ELSE 0 END) > 0
                     AND COUNT(DISTINCT FiscalMonthDate) >= 1 THEN 1
                     WHEN SUM(CASE WHEN FiscalMonthDate IS NULL THEN 1 ELSE 0 END) > 0
                     AND COUNT(DISTINCT FiscalMonthDate) = 0 THEN 1
                     ELSE 0 END AS distinct_fmd_nullsafe,
            {", ".join(
                nullsafe_distinct_expr(c) + f" AS d_{c}" for c in VALUE_COLS
            )}
        FROM src
        WHERE ItemSku IS NOT NULL
          AND WarehouseCode IS NOT NULL
          AND SnapshotWeekEndingDate IS NOT NULL
        GROUP BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
    )
    SELECT
        COUNT(*) AS total_groups,
        SUM(CASE WHEN c > 1 THEN 1 ELSE 0 END) AS multi_row_groups,
        COALESCE(SUM(CASE WHEN c > 1 THEN c ELSE 0 END), 0) AS rows_in_multi_groups,
        SUM(CASE WHEN c > 1 AND c > distinct_fmd_nullsafe THEN 1 ELSE 0 END)
            AS groups_where_fiscalmonthdate_tied,
        {", ".join(
            f"SUM(CASE WHEN c > 1 AND d_{c} > 1 THEN 1 ELSE 0 END) "
            f"AS groups_where_{c}_differs"
            for c in VALUE_COLS
        )}
    FROM g
    """
    t0 = time.time()
    row = L.query(conn, sql)[0]
    elapsed = round(time.time() - t0, 1)
    varies = {c: int(row[f"groups_where_{c}_differs"] or 0) for c in VALUE_COLS}
    return {
        "check": "T1_R3_extended_carried_cols",
        "elapsed_sec": elapsed,
        "total_groups": row["total_groups"],
        "multi_row_groups": row["multi_row_groups"],
        "rows_in_multi_groups": row["rows_in_multi_groups"],
        "groups_where_fiscalmonthdate_tied": row["groups_where_fiscalmonthdate_tied"],
        "groups_where_col_differs": varies,
        "order_by_material_for": [c for c, n in varies.items() if n > 0],
        "tiebreak_deterministic": (row["groups_where_fiscalmonthdate_tied"] or 0) == 0,
        "pass": (row["groups_where_fiscalmonthdate_tied"] or 0) == 0,
        "note": (
            "ORDER BY FiscalMonthDate ASC is deterministic iff FMD never ties. "
            "If a carried col differs within group, ORDER BY is material for that "
            "col but still deterministic. C1 preserves the same ORDER BY as A."
        ),
    }


def run_t2_counts(conn, recent_weeks: int | None) -> dict:
    """Shared surface counts: all rn=1 / non-null / weekly-eligible."""
    src = source_cte(recent_weeks)
    sql = f"""
    WITH {src},
    ranked AS (
        SELECT
            ItemSku, WarehouseCode, SnapshotWeekEndingDate,
            OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName,
            ReplenishmentLeadTime, SnapshotType,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                ORDER BY FiscalMonthDate ASC
            ) AS rn
        FROM src
    ),
    pick AS (
        SELECT * FROM ranked WHERE rn = 1
    )
    SELECT
        COUNT(*) AS shared_rn1_groups,
        SUM(CASE WHEN ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
                      AND SnapshotWeekEndingDate IS NOT NULL
                 THEN 1 ELSE 0 END) AS shared_nonnull_groups,
        SUM(CASE WHEN ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
                      AND SnapshotWeekEndingDate IS NOT NULL
                      AND (SnapshotType = 'WEEKLY'
                           OR SnapshotType = 'WEEKLY_AND_LATEST')
                 THEN 1 ELSE 0 END) AS shared_fact_eligible_groups,
        SUM(CASE WHEN ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
                      AND SnapshotWeekEndingDate IS NOT NULL
                      AND NOT (SnapshotType = 'WEEKLY'
                               OR SnapshotType = 'WEEKLY_AND_LATEST'
                               OR SnapshotType IS NULL)
                 THEN 1 ELSE 0 END) AS shared_nonnull_nonweekly_groups,
        SUM(CASE WHEN ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
                      AND SnapshotWeekEndingDate IS NOT NULL
                      AND SnapshotType IS NULL
                 THEN 1 ELSE 0 END) AS shared_nonnull_nulltype_groups
    FROM pick
    """
    t0 = time.time()
    row = L.query(conn, sql)[0]
    elapsed = round(time.time() - t0, 1)

    expected = {
        "weekly_family_rows": 19_605_162,
        "fact_snapshot_table_rows": 19_501_346,
        "delta": 103_816,
    }
    return {
        "check": "T2_shared_surface_counts",
        "elapsed_sec": elapsed,
        "shared_rn1_groups": row["shared_rn1_groups"],
        "shared_nonnull_groups": row["shared_nonnull_groups"],
        "shared_fact_eligible_groups": row["shared_fact_eligible_groups"],
        "shared_nonnull_nonweekly_groups": row["shared_nonnull_nonweekly_groups"],
        "shared_nonnull_nulltype_groups": row["shared_nonnull_nulltype_groups"],
        "full_history_expected_reference": expected,
        "pass": True,
        "note": (
            "On --full: shared_rn1_groups should equal weekly family 19,605,162; "
            "shared_fact_eligible_groups should equal FactSnapshot 19,501,346 "
            "if SnapshotType filter alone explains the Δ after non-null filter."
        ),
    }


def run_t3_fact_antijoin(conn, recent_weeks: int | None) -> dict:
    """Two-way anti-join: FactSnapshot inv_base A vs C1 shared-then-filter B.

    A = NULL filter BEFORE ROW_NUMBER, rn=1 (current FactSnapshot inv_base)
    B = ROW_NUMBER on all, rn=1, THEN NULL filter (C1 consumer path)

    Full-history uses key anti-join + null-safe value mismatch (cheaper than
    9-col EXCEPT on 19.6M). Bounded path still uses full-tuple EXCEPT.
    """
    src = source_cte(recent_weeks)
    cols = ", ".join(b(c) for c in CARRIED)
    key_join = """
        a.ItemSku = b.ItemSku
        AND a.WarehouseCode = b.WarehouseCode
        AND a.SnapshotWeekEndingDate = b.SnapshotWeekEndingDate
    """
    val_mismatch = " OR ".join(
        f"(a.{b(c)} <> b.{b(c)} OR (a.{b(c)} IS NULL AND b.{b(c)} IS NOT NULL) "
        f"OR (a.{b(c)} IS NOT NULL AND b.{b(c)} IS NULL))"
        for c in [
            "OnHandQty", "MakeBuyCode", "PrimaryVendorName",
            "SecondaryVendorName", "ReplenishmentLeadTime", "SnapshotType",
        ]
    )

    a_cte = f"""
    a AS (
        SELECT {cols}
        FROM (
            SELECT
                ItemSku, WarehouseCode, SnapshotWeekEndingDate,
                OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName,
                ReplenishmentLeadTime, SnapshotType,
                ROW_NUMBER() OVER (
                    PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                    ORDER BY FiscalMonthDate ASC
                ) AS rn
            FROM src
            WHERE ItemSku IS NOT NULL
              AND WarehouseCode IS NOT NULL
              AND SnapshotWeekEndingDate IS NOT NULL
        ) x
        WHERE rn = 1
    )"""
    b_cte = f"""
    b AS (
        SELECT {cols}
        FROM (
            SELECT
                ItemSku, WarehouseCode, SnapshotWeekEndingDate,
                OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName,
                ReplenishmentLeadTime, SnapshotType,
                ROW_NUMBER() OVER (
                    PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                    ORDER BY FiscalMonthDate ASC
                ) AS rn
            FROM src
        ) x
        WHERE rn = 1
          AND ItemSku IS NOT NULL
          AND WarehouseCode IS NOT NULL
          AND SnapshotWeekEndingDate IS NOT NULL
    )"""

    if recent_weeks is None:
        compare_mode = "key_antijoin_plus_value_mismatch"
        sql = f"""
        WITH {src},
        {a_cte},
        {b_cte}
        SELECT
            (SELECT COUNT(*) FROM a) AS a_rows,
            (SELECT COUNT(*) FROM b) AS b_rows,
            (SELECT COUNT(*) FROM a
             WHERE NOT EXISTS (SELECT 1 FROM b WHERE {key_join})) AS a_not_in_b,
            (SELECT COUNT(*) FROM b
             WHERE NOT EXISTS (SELECT 1 FROM a WHERE {key_join})) AS b_not_in_a,
            (SELECT COUNT(*) FROM a
             INNER JOIN b ON {key_join}
             WHERE {val_mismatch}) AS value_mismatches
        """
    else:
        compare_mode = "full_tuple_except"
        sql = f"""
        WITH {src},
        {a_cte},
        {b_cte}
        SELECT
            (SELECT COUNT(*) FROM a) AS a_rows,
            (SELECT COUNT(*) FROM b) AS b_rows,
            (SELECT COUNT(*) FROM (SELECT {cols} FROM a EXCEPT SELECT {cols} FROM b) d)
                AS a_not_in_b,
            (SELECT COUNT(*) FROM (SELECT {cols} FROM b EXCEPT SELECT {cols} FROM a) d)
                AS b_not_in_a,
            CAST(0 AS BIGINT) AS value_mismatches
        """

    t0 = time.time()
    row = L.query(conn, sql)[0]
    elapsed = round(time.time() - t0, 1)
    a_not_b = int(row["a_not_in_b"] or 0)
    b_not_a = int(row["b_not_in_a"] or 0)
    a_rows = int(row["a_rows"] or 0)
    b_rows = int(row["b_rows"] or 0)
    val_mis = int(row["value_mismatches"] or 0)
    set_match = a_not_b == 0 and b_not_a == 0 and val_mis == 0
    return {
        "check": "T3_fact_invbase_A_vs_C1_shared_B",
        "elapsed_sec": elapsed,
        "compare_mode": compare_mode,
        "a_definition": "NULL-filter BEFORE ROW_NUMBER, rn=1 (live FactSnapshot inv_base)",
        "b_definition": "ROW_NUMBER on all, rn=1, THEN NULL-filter (C1 consumer path)",
        "compared_columns": CARRIED,
        "a_rows": a_rows,
        "b_rows": b_rows,
        "a_not_in_b": a_not_b,
        "b_not_in_a": b_not_a,
        "value_mismatches": val_mis,
        "rowcount_match": a_rows == b_rows,
        "set_match": set_match,
        "pass": a_rows == b_rows and set_match,
    }


def run_t4_substatus_antijoin(conn, recent_weeks: int | None) -> dict:
    """Two-way anti-join: SubStatus inv_base A vs shared projected to OnHandQty."""
    src = source_cte(recent_weeks)
    cols = ", ".join(b(c) for c in SS_COLS)
    key_join = """
        a.ItemSku = b.ItemSku
        AND a.WarehouseCode = b.WarehouseCode
        AND a.SnapshotWeekEndingDate = b.SnapshotWeekEndingDate
    """
    val_mismatch = (
        "(a.[OnHandQty] <> b.[OnHandQty] "
        "OR (a.[OnHandQty] IS NULL AND b.[OnHandQty] IS NOT NULL) "
        "OR (a.[OnHandQty] IS NOT NULL AND b.[OnHandQty] IS NULL))"
    )

    a_cte = f"""
    a AS (
        SELECT {cols}
        FROM (
            SELECT
                ItemSku, WarehouseCode, SnapshotWeekEndingDate, OnHandQty,
                ROW_NUMBER() OVER (
                    PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                    ORDER BY FiscalMonthDate ASC
                ) AS rn
            FROM src
        ) x
        WHERE rn = 1
    )"""
    b_cte = f"""
    b AS (
        SELECT {cols}
        FROM (
            SELECT
                ItemSku, WarehouseCode, SnapshotWeekEndingDate,
                OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName,
                ReplenishmentLeadTime, SnapshotType,
                ROW_NUMBER() OVER (
                    PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                    ORDER BY FiscalMonthDate ASC
                ) AS rn
            FROM src
        ) x
        WHERE rn = 1
    )"""

    if recent_weeks is None:
        compare_mode = "key_antijoin_plus_value_mismatch"
        sql = f"""
        WITH {src},
        {a_cte},
        {b_cte}
        SELECT
            (SELECT COUNT(*) FROM a) AS a_rows,
            (SELECT COUNT(*) FROM b) AS b_rows,
            (SELECT COUNT(*) FROM a
             WHERE NOT EXISTS (SELECT 1 FROM b WHERE {key_join})) AS a_not_in_b,
            (SELECT COUNT(*) FROM b
             WHERE NOT EXISTS (SELECT 1 FROM a WHERE {key_join})) AS b_not_in_a,
            (SELECT COUNT(*) FROM a
             INNER JOIN b ON {key_join}
             WHERE {val_mismatch}) AS value_mismatches
        """
    else:
        compare_mode = "full_tuple_except"
        sql = f"""
        WITH {src},
        {a_cte},
        {b_cte}
        SELECT
            (SELECT COUNT(*) FROM a) AS a_rows,
            (SELECT COUNT(*) FROM b) AS b_rows,
            (SELECT COUNT(*) FROM (SELECT {cols} FROM a EXCEPT SELECT {cols} FROM b) d)
                AS a_not_in_b,
            (SELECT COUNT(*) FROM (SELECT {cols} FROM b EXCEPT SELECT {cols} FROM a) d)
                AS b_not_in_a,
            CAST(0 AS BIGINT) AS value_mismatches
        """

    t0 = time.time()
    row = L.query(conn, sql)[0]
    elapsed = round(time.time() - t0, 1)
    a_not_b = int(row["a_not_in_b"] or 0)
    b_not_a = int(row["b_not_in_a"] or 0)
    a_rows = int(row["a_rows"] or 0)
    b_rows = int(row["b_rows"] or 0)
    val_mis = int(row["value_mismatches"] or 0)
    set_match = a_not_b == 0 and b_not_a == 0 and val_mis == 0
    return {
        "check": "T4_substatus_invbase_vs_shared",
        "elapsed_sec": elapsed,
        "compare_mode": compare_mode,
        "a_definition": "live SubStatus inv_base (RN all, rn=1, OnHandQty only)",
        "b_definition": "C1 shared surface projected to OnHandQty",
        "compared_columns": SS_COLS,
        "a_rows": a_rows,
        "b_rows": b_rows,
        "a_not_in_b": a_not_b,
        "b_not_in_a": b_not_a,
        "value_mismatches": val_mis,
        "rowcount_match": a_rows == b_rows,
        "set_match": set_match,
        "pass": a_rows == b_rows and set_match,
    }


def run_t5_snapshottype_dist(conn, recent_weeks: int | None) -> dict:
    """SnapshotType distribution among rn=1 non-null groups (explains fact Δ)."""
    src = source_cte(recent_weeks)
    sql = f"""
    WITH {src},
    ranked AS (
        SELECT
            ItemSku, WarehouseCode, SnapshotWeekEndingDate, SnapshotType,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                ORDER BY FiscalMonthDate ASC
            ) AS rn
        FROM src
        WHERE ItemSku IS NOT NULL
          AND WarehouseCode IS NOT NULL
          AND SnapshotWeekEndingDate IS NOT NULL
    )
    SELECT
        CAST(SnapshotType AS VARCHAR(50)) AS SnapshotType,
        COUNT(*) AS n
    FROM ranked
    WHERE rn = 1
    GROUP BY CAST(SnapshotType AS VARCHAR(50))
    ORDER BY n DESC
    """
    t0 = time.time()
    rows = L.query(conn, sql)
    elapsed = round(time.time() - t0, 1)
    dist = {(r["SnapshotType"] if r["SnapshotType"] is not None else "<NULL>"): r["n"]
            for r in rows}
    weekly = int(dist.get("WEEKLY", 0)) + int(dist.get("WEEKLY_AND_LATEST", 0))
    total = sum(int(v) for v in dist.values())
    return {
        "check": "T5_rn1_nonnull_SnapshotType_dist",
        "elapsed_sec": elapsed,
        "distribution": dist,
        "total_nonnull_rn1": total,
        "weekly_eligible": weekly,
        "excluded_by_snapshottype_filter": total - weekly,
        "pass": True,
        "note": (
            "FactSnapshot base applies SnapshotType IN ('WEEKLY','WEEKLY_AND_LATEST') "
            "AFTER inv_base pick. excluded_by_snapshottype_filter should equal the "
            "weekly-family vs FactSnapshot row delta on full history if no other filter."
        ),
    }


def assert_full_history_invariants(t2: dict, t5: dict) -> dict:
    """Absolute invariants only meaningful on unbounded full-history run."""
    exp_weekly = 19_605_162
    exp_fact = 19_501_346
    shared = int(t2["shared_rn1_groups"] or 0)
    fact_elig = int(t2["shared_fact_eligible_groups"] or 0)
    nonnull = int(t2["shared_nonnull_groups"] or 0)
    t5_weekly = int(t5["weekly_eligible"] or 0)
    return {
        "check": "T2_full_history_invariants",
        "shared_rn1_equals_weekly_family": shared == exp_weekly,
        "shared_rn1_groups": shared,
        "expected_weekly_family": exp_weekly,
        "shared_fact_eligible_equals_fact_table": fact_elig == exp_fact,
        "shared_fact_eligible_groups": fact_elig,
        "expected_fact_snapshot": exp_fact,
        "nonnull_minus_fact_eligible": nonnull - fact_elig,
        "t5_weekly_eligible": t5_weekly,
        "t2_t5_weekly_consistent": fact_elig == t5_weekly,
        "pass": (
            shared == exp_weekly
            and fact_elig == exp_fact
            and fact_elig == t5_weekly
        ),
        "note": (
            "If shared_fact_eligible != live FactSnapshot table rowcount, source may "
            "have moved since baseline capture, or an additional filter exists. "
            "Investigate before claiming C1 load-path parity."
        ),
    }


def write_report(out: dict, checks: list[dict], all_pass: bool) -> tuple[Path, Path]:
    stamp = out["generated_at_utc"]
    json_path = RUNS / f"{stamp}_shadow_parity_c1.json"
    txt_path = RUNS / f"{stamp}_shadow_parity_c1.txt"
    json_path.write_text(json.dumps(out, indent=2, default=L.json_default), encoding="utf-8")

    lines = [
        f"Module 04 C1 inline shadow parity — {out['mode']}",
        f"generated_at_utc={stamp}",
        f"overall_pass={all_pass}",
        f"verdict={out['c1_parity_verdict']}",
        f"live_ddl_dml=none",
        "",
    ]
    for c in checks:
        lines.append(f"[{c['check']}] pass={c.get('pass')} elapsed={c.get('elapsed_sec')}s")
        for k, v in c.items():
            if k in ("check", "pass", "elapsed_sec", "note", "a_definition",
                     "b_definition", "compared_columns",
                     "full_history_expected_reference"):
                continue
            lines.append(f"  {k}={v}")
        if c.get("note"):
            lines.append(f"  note={c['note']}")
        lines.append("")
    lines.append(out["interpretation"])
    txt_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, txt_path


def main() -> int:
    ap = argparse.ArgumentParser(
        description="C1 inline shadow parity (read-only, no live DDL/DML)."
    )
    g = ap.add_mutually_exclusive_group()
    g.add_argument(
        "--recent-weeks", type=int, default=None,
        help="Bound source to last N distinct SnapshotWeekEndingDate values.",
    )
    g.add_argument(
        "--full", action="store_true",
        help="Full-history proof (no week bound). Expensive.",
    )
    ap.add_argument(
        "--skip-antijoin", action="store_true",
        help="Skip T3/T4 two-way anti-joins (counts + R3 only).",
    )
    ap.add_argument(
        "--only-antijoin", action="store_true",
        help="Run only T3/T4 (resume after T1/T2/T5 already passed).",
    )
    ap.add_argument(
        "--timeout", type=int, default=1800,
        help="Connection timeout seconds (default 1800).",
    )
    args = ap.parse_args()

    if not args.full and args.recent_weeks is None:
        args.recent_weeks = 8
        print("NOTE: defaulting to --recent-weeks 8. Pass --full for full history.")

    recent = None if args.full else args.recent_weeks
    mode = "full_history" if recent is None else f"recent_weeks_{recent}"
    if args.only_antijoin:
        mode = mode + "_antijoin_only"

    RUNS.mkdir(exist_ok=True)
    stamp = L.utc_stamp()
    out: dict = {
        "generated_at_utc": stamp,
        "module": "04_shadow_parity",
        "candidate": "C1_shared_deduped_inv_base",
        "safety": {
            "application_intent": "ReadOnly",
            "ddl_dml": "none",
            "live_objects_created": [],
            "live_objects_mutated": [],
        },
        "mode": mode,
        "server": L.SERVER,
        "source": f"{PROC}.InventoryHistory_Enh.InventorySnapshotWeekly",
        "checks": [],
    }

    print(f"=== Module 04 C1 inline shadow parity ({mode}) ===")
    print("Safety: ApplicationIntent=ReadOnly; SELECT only; no live DDL/DML")
    print(f"Source: {out['source']}")
    print()

    conn = L.connect(PROC, timeout=args.timeout)
    checks: list[dict] = []

    if not args.only_antijoin:
        print("-- T1 R3 extended (carried-col materiality + FMD ties) --")
        t1 = run_t1_r3_extended(conn, recent)
        checks.append(t1)
        print(f"  multi_row_groups={t1['multi_row_groups']}  "
              f"fmd_tied={t1['groups_where_fiscalmonthdate_tied']}  "
              f"order_by_material_for={t1['order_by_material_for']}  "
              f"pass={t1['pass']}  ({t1['elapsed_sec']}s)")
        for c, n in t1["groups_where_col_differs"].items():
            print(f"    groups_where_{c}_differs={n}")

        print("-- T2 shared surface counts --")
        t2 = run_t2_counts(conn, recent)
        checks.append(t2)
        print(f"  shared_rn1={t2['shared_rn1_groups']:,}  "
              f"nonnull={t2['shared_nonnull_groups']:,}  "
              f"fact_eligible={t2['shared_fact_eligible_groups']:,}  "
              f"({t2['elapsed_sec']}s)")

        print("-- T5 rn=1 non-null SnapshotType distribution --")
        t5 = run_t5_snapshottype_dist(conn, recent)
        checks.append(t5)
        print(f"  dist={t5['distribution']}  "
              f"weekly_eligible={t5['weekly_eligible']:,}  "
              f"excluded={t5['excluded_by_snapshottype_filter']:,}  "
              f"({t5['elapsed_sec']}s)")

        if args.full:
            inv = assert_full_history_invariants(t2, t5)
            checks.append(inv)
            print("-- T2 full-history invariants --")
            print(f"  shared==weekly_family? {inv['shared_rn1_equals_weekly_family']}  "
                  f"fact_eligible==fact_table? {inv['shared_fact_eligible_equals_fact_table']}  "
                  f"pass={inv['pass']}")

    if not args.skip_antijoin:
        print("-- T3 FactSnapshot inv_base A vs C1 shared B (two-way anti-join) --")
        t3 = run_t3_fact_antijoin(conn, recent)
        checks.append(t3)
        print(f"  mode={t3['compare_mode']}  a_rows={t3['a_rows']:,}  b_rows={t3['b_rows']:,}  "
              f"a_not_b={t3['a_not_in_b']}  b_not_a={t3['b_not_in_a']}  "
              f"value_mismatches={t3['value_mismatches']}  "
              f"pass={t3['pass']}  ({t3['elapsed_sec']}s)")

        print("-- T4 SubStatus inv_base vs shared (two-way anti-join) --")
        t4 = run_t4_substatus_antijoin(conn, recent)
        checks.append(t4)
        print(f"  mode={t4['compare_mode']}  a_rows={t4['a_rows']:,}  b_rows={t4['b_rows']:,}  "
              f"a_not_b={t4['a_not_in_b']}  b_not_a={t4['b_not_in_a']}  "
              f"value_mismatches={t4['value_mismatches']}  "
              f"pass={t4['pass']}  ({t4['elapsed_sec']}s)")
    else:
        print("-- T3/T4 skipped (--skip-antijoin) --")

    conn.close()

    all_pass = all(c.get("pass", False) for c in checks)
    out["checks"] = checks
    out["overall_pass"] = all_pass
    out["c1_parity_verdict"] = (
        "C1_SHARED_INV_BASE_PARITY_PASS"
        if all_pass
        else "C1_SHARED_INV_BASE_PARITY_FAIL_OR_INCOMPLETE"
    )
    out["interpretation"] = (
        "C1 is parity-safe for inv_base if: (1) FMD tie-break is deterministic, "
        "(2) FactSnapshot A-vs-B anti-join is empty both ways on all carried cols, "
        "(3) SubStatus A-vs-B anti-join is empty both ways on OnHandQty, "
        "(4) on full history, shared counts reproduce weekly-family / fact-eligible "
        "row invariants. Performance gain is NOT proven here (no materialization)."
    )

    json_path, txt_path = write_report(out, checks, all_pass)
    print()
    print(f"overall_pass={all_pass}  verdict={out['c1_parity_verdict']}")
    print(f"Wrote {json_path}")
    print(f"Wrote {txt_path}")
    return 0 if all_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
