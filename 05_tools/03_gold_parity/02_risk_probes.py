#!/usr/bin/env python3
"""Module 02 — Risk probes (READ-ONLY) for Inventory Health Gold parity.

Proves/refutes the parity risks identified from reading the live view SQL.
These decide whether the shared-surface optimization candidates are even safe
to consider. Nothing here mutates any object.

Probes:
  R1  Helper-join multiplicity: for every table LEFT JOINed into
      v_FactInventoryHealthSnapshot at (ItemSku, WarehouseCode, <date>),
      count duplicate keys. Any dup > 0 means the CURRENT fact (A) is already
      fanning out rows on that join -> must be understood before B.
        - SafetyStockHelper      (ItemSku, WarehouseCode, AsOfDate)
        - Cogs52WWeekly          (ItemSku, WarehouseCode, WeekEndingDate)
        - LastInvoiceWeekly      (ItemSku, WarehouseCode, WeekEndingDate)
        - AFIStatusSnapshotWeekly(ItemSku, WarehouseCode, WeekEndingDate)
        - AwdHelper              (ItemSku, WarehouseCode, AsOfDate)
        - InventoryHealthSubStatusWeekly (ItemSku, WarehouseCode, SnapshotWeekEnding)
        - InventoryClassificationQtyWeekly (Item, WH, SnapshotWeekEnding)

  R2  DimProduct uniqueness at ItemSKU (join is Item-only, no WH) -> dup means
      OnHand Value / UsedStorageCube / Revenue at risk get multiplied.

  R3  inv_base tie-break stability: within
      (ItemSku, WarehouseCode, SnapshotWeekEndingDate), how many groups have
      >1 physical row, and among those, does OnHandQty actually differ across
      the tie (i.e. does ORDER BY FiscalMonthDate ASC change the answer)?
      Also whether FiscalMonthDate itself ties (non-deterministic pick).

Output: 05_tools/03_gold_parity/runs/<stamp>_risk_probes.json + console table.

Usage:
    python3 05_tools/03_gold_parity/02_risk_probes.py
"""

from __future__ import annotations

import json
from pathlib import Path

import lib_conn as L

PROC = "SupplyChain_Processing_Warehouse"
GOLD = "SupplyChain_Gold_Warehouse"

# ---- R1: helper join grains as used by v_FactInventoryHealthSnapshot ---- #
# (table, db, schema, key_cols)  key_cols are the ON columns of the LEFT JOIN.
R1_HELPERS = [
    (PROC, "InventoryHistory_Enh", "SafetyStockHelper", ["ItemSku", "WarehouseCode", "AsOfDate"]),
    (PROC, "InventoryHistory_Enh", "Cogs52WWeekly", ["ItemSku", "WarehouseCode", "WeekEndingDate"]),
    (PROC, "InventoryHistory_Enh", "LastInvoiceWeekly", ["ItemSku", "WarehouseCode", "WeekEndingDate"]),
    (PROC, "InventoryHistory_Enh", "AFIStatusSnapshotWeekly", ["ItemSku", "WarehouseCode", "WeekEndingDate"]),
    (PROC, "InventoryHistory_Enh", "AwdHelper", ["ItemSku", "WarehouseCode", "AsOfDate"]),
    (GOLD, "InventoryHealth_DW", "InventoryHealthSubStatusWeekly", ["ItemSku", "WarehouseCode", "SnapshotWeekEnding"]),
    (GOLD, "InventoryHealth_DW", "InventoryClassificationQtyWeekly", ["Item", "WH", "SnapshotWeekEnding"]),
]


def probe_dup(conn, db, schema, table, keys) -> dict:
    key_list = ", ".join(f"[{k}]" for k in keys)
    sql = f"""
        SELECT COUNT(*) AS dup_key_groups,
               COALESCE(SUM(rowcount_in_group), 0) AS rows_in_dup_groups,
               COALESCE(MAX(rowcount_in_group), 0) AS max_rows_per_key
        FROM (
            SELECT {key_list}, COUNT(*) AS rowcount_in_group
            FROM [{db}].[{schema}].[{table}]
            GROUP BY {key_list}
            HAVING COUNT(*) > 1
        ) d
    """
    total_sql = f"SELECT COUNT(*) FROM [{db}].[{schema}].[{table}]"
    try:
        total = L.scalar(conn, total_sql)
        r = L.query(conn, sql)[0]
        return {
            "table": f"{db}.{schema}.{table}",
            "keys": keys,
            "total_rows": total,
            "dup_key_groups": r["dup_key_groups"],
            "rows_in_dup_groups": r["rows_in_dup_groups"],
            "max_rows_per_key": r["max_rows_per_key"],
            "multiplicity_ok": (r["dup_key_groups"] == 0),
        }
    except Exception as e:
        return {"table": f"{db}.{schema}.{table}", "keys": keys, "error": str(e)}


def probe_r2_dimproduct(conn) -> dict:
    # DimProduct joined ON ItemSKU only.
    sql = f"""
        SELECT COUNT(*) AS dup_key_groups, COALESCE(MAX(c), 0) AS max_rows_per_item
        FROM (
            SELECT [ItemSKU], COUNT(*) AS c
            FROM [{GOLD}].[Shared_DW].[DimProduct]
            GROUP BY [ItemSKU]
            HAVING COUNT(*) > 1
        ) d
    """
    total = L.scalar(conn, f"SELECT COUNT(*) FROM [{GOLD}].[Shared_DW].[DimProduct]")
    r = L.query(conn, sql)[0]
    return {
        "table": f"{GOLD}.Shared_DW.DimProduct",
        "key": "ItemSKU",
        "total_rows": total,
        "dup_key_groups": r["dup_key_groups"],
        "max_rows_per_item": r["max_rows_per_item"],
        "multiplicity_ok": (r["dup_key_groups"] == 0),
    }


def probe_r3_tiebreak(conn) -> dict:
    """inv_base dedupe = ROW_NUMBER PARTITION BY (Item,WH,SnapshotWeekEndingDate)
    ORDER BY FiscalMonthDate ASC. Test whether the tie-break is material."""
    tbl = f"[{PROC}].[InventoryHistory_Enh].[InventorySnapshotWeekly]"
    # groups with >1 physical row at the dedupe grain
    grp_sql = f"""
        SELECT COUNT(*) AS multi_row_groups,
               COALESCE(SUM(c), 0) AS rows_in_multi_groups
        FROM (
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, COUNT(*) AS c
            FROM {tbl}
            WHERE ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
              AND SnapshotWeekEndingDate IS NOT NULL
            GROUP BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
            HAVING COUNT(*) > 1
        ) d
    """
    total = L.scalar(conn, f"SELECT COUNT(*) FROM {tbl}")
    grp = L.query(conn, grp_sql)[0]

    # Among multi-row groups, does OnHandQty differ (material tie-break)?
    onhand_sql = f"""
        SELECT COUNT(*) AS groups_with_distinct_onhand
        FROM (
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate,
                   COUNT(DISTINCT OnHandQty) AS distinct_onhand
            FROM {tbl}
            WHERE ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
              AND SnapshotWeekEndingDate IS NOT NULL
            GROUP BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
            HAVING COUNT(*) > 1 AND COUNT(DISTINCT OnHandQty) > 1
        ) d
    """
    # Among multi-row groups, does FiscalMonthDate tie (non-deterministic pick)?
    fmd_sql = f"""
        SELECT COUNT(*) AS groups_with_tied_fiscalmonthdate
        FROM (
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate,
                   COUNT(*) AS c, COUNT(DISTINCT FiscalMonthDate) AS distinct_fmd
            FROM {tbl}
            WHERE ItemSku IS NOT NULL AND WarehouseCode IS NOT NULL
              AND SnapshotWeekEndingDate IS NOT NULL
            GROUP BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
            HAVING COUNT(*) > 1 AND COUNT(*) > COUNT(DISTINCT FiscalMonthDate)
        ) d
    """
    onhand = L.query(conn, onhand_sql)[0]
    fmd = L.query(conn, fmd_sql)[0]
    return {
        "table": f"{PROC}.InventoryHistory_Enh.InventorySnapshotWeekly",
        "dedupe_grain": ["ItemSku", "WarehouseCode", "SnapshotWeekEndingDate"],
        "tiebreak_order": "FiscalMonthDate ASC",
        "total_rows": total,
        "multi_row_groups": grp["multi_row_groups"],
        "rows_in_multi_groups": grp["rows_in_multi_groups"],
        "groups_where_onhand_differs": onhand["groups_with_distinct_onhand"],
        "groups_where_fiscalmonthdate_tied": fmd["groups_with_tied_fiscalmonthdate"],
        "tiebreak_is_material": onhand["groups_with_distinct_onhand"] > 0,
        "tiebreak_is_nondeterministic": fmd["groups_with_tied_fiscalmonthdate"] > 0,
    }


def main() -> int:
    here = Path(__file__).resolve().parent
    runs = here / "runs"
    runs.mkdir(exist_ok=True)

    out = {"generated_at_utc": L.utc_stamp(), "server": L.SERVER,
           "R1_helper_multiplicity": [], "R2_dimproduct": None, "R3_tiebreak": None}

    lines = []

    # R1 needs both DBs; open per-DB connections.
    conn_gold = L.connect(GOLD)
    conn_proc = L.connect(PROC)

    lines.append("=== R1: helper-join multiplicity (LEFT JOINs in v_FactInventoryHealthSnapshot) ===")
    lines.append(f"{'TABLE':<62} {'TOTAL':>12} {'DUP_GRP':>9} {'MAXROWS':>8}  OK")
    for db, schema, table, keys in R1_HELPERS:
        conn = conn_gold if db == GOLD else conn_proc
        r = probe_dup(conn, db, schema, table, keys)
        out["R1_helper_multiplicity"].append(r)
        if "error" in r:
            lines.append(f"{db+'.'+schema+'.'+table:<62} ERROR: {r['error'][:60]}")
            continue
        ok = "OK" if r["multiplicity_ok"] else "FANOUT"
        lines.append(f"{r['table']:<62} {str(r['total_rows']):>12} "
                     f"{str(r['dup_key_groups']):>9} {str(r['max_rows_per_key']):>8}  {ok}")

    lines.append("")
    lines.append("=== R2: DimProduct uniqueness at ItemSKU (fact joins Item-only) ===")
    r2 = probe_r2_dimproduct(conn_gold)
    out["R2_dimproduct"] = r2
    lines.append(f"total={r2['total_rows']}  dup_item_groups={r2['dup_key_groups']}  "
                 f"max_rows_per_item={r2['max_rows_per_item']}  "
                 f"{'OK' if r2['multiplicity_ok'] else 'FANOUT'}")

    lines.append("")
    lines.append("=== R3: inv_base tie-break materiality (ORDER BY FiscalMonthDate ASC) ===")
    r3 = probe_r3_tiebreak(conn_proc)
    out["R3_tiebreak"] = r3
    lines.append(f"total_rows={r3['total_rows']}")
    lines.append(f"multi_row_groups={r3['multi_row_groups']}  "
                 f"rows_in_multi_groups={r3['rows_in_multi_groups']}")
    lines.append(f"groups_where_onhand_differs={r3['groups_where_onhand_differs']}  "
                 f"(tiebreak_material={r3['tiebreak_is_material']})")
    lines.append(f"groups_where_fiscalmonthdate_tied={r3['groups_where_fiscalmonthdate_tied']}  "
                 f"(nondeterministic={r3['tiebreak_is_nondeterministic']})")

    conn_gold.close()
    conn_proc.close()

    report = "\n".join(lines)
    print(report)

    out_path = runs / f"{out['generated_at_utc']}_risk_probes.json"
    out_path.write_text(json.dumps(out, indent=2, default=L.json_default), encoding="utf-8")
    txt_path = runs / f"{out['generated_at_utc']}_risk_probes.txt"
    txt_path.write_text(report + "\n", encoding="utf-8")
    print(f"\nWrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
