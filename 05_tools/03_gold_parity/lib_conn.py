#!/usr/bin/env python3
"""Shared read-only connection + helpers for Inventory Health Gold parity harness.

Mirrors the auth pattern used by 05_tools/01_dq/* (pyodbc + Entra token via az CLI).
Every helper here is read-only by construction. No DDL/DML is issued by this module.

Scope lock (see 01_docs/plans/2026-07-10-inventory-gold-business-parity-optimization-plan.md):
- Wave 0, audit + read-only evidence only.
- No mutation of live production objects.
"""

from __future__ import annotations

import datetime as dt
import struct
import subprocess
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

import pyodbc

ROOT = Path(__file__).resolve().parents[2]
SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a"
    ".datawarehouse.fabric.microsoft.com"
)

# Databases in the Inventory Health Gold serving chain.
GOLD_DB = "SupplyChain_Gold_Warehouse"
PROC_DB = "SupplyChain_Processing_Warehouse"
LAKE_DB = "Enterprise_Lakehouse"

SQL_COPT_SS_ACCESS_TOKEN = 1256


def az_token(resource: str = "https://database.windows.net/") -> str:
    return subprocess.check_output(
        [
            "az", "account", "get-access-token",
            "--resource", resource,
            "--query", "accessToken",
            "-o", "tsv",
        ],
        text=True,
    ).strip()


def connect(database: str = GOLD_DB, timeout: int = 300) -> pyodbc.Connection:
    """Open a read-only-intent connection. autocommit=True; we never issue DML."""
    token = az_token().encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token)}s", len(token), token)
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{SERVER},1433;"
        f"DATABASE={database};"
        "Encrypt=yes;TrustServerCertificate=no;"
        "ApplicationIntent=ReadOnly;",
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct},
        autocommit=True,
        timeout=timeout,
    )
    return conn


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def query(
    conn: pyodbc.Connection,
    sql: str,
    params: tuple = (),
) -> list[dict[str, Any]]:
    """Run one read-only query."""
    cur = conn.cursor()
    cur.execute(sql, params) if params else cur.execute(sql)
    if cur.description is None:
        return []
    return rows_as_dicts(cur)


def scalar(conn: pyodbc.Connection, sql: str, params: tuple = ()) -> Any:
    cur = conn.cursor()
    cur.execute(sql, params) if params else cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def json_default(o: Any) -> Any:
    if isinstance(o, Decimal):
        # Preserve exactness as string; float would lose precision for money grains.
        return str(o)
    if isinstance(o, (dt.date, dt.datetime)):
        return o.isoformat()
    if isinstance(o, bytes):
        return o.hex()
    return str(o)


def utc_stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


# --------------------------------------------------------------------------- #
# Inventory Health Gold target registry (repo source of truth: the 9-object
# dbo.Usp_Refresh_InventoryHealth_Gold chain + their _Wrk views).
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class GoldTarget:
    step: int
    wave: str
    db: str
    schema: str
    table: str            # physical final table
    view_schema: str
    view: str             # _Wrk business/source view
    business_key: tuple[str, ...]  # declared business grain (to be probed, not assumed)
    is_hotspot: bool = False

    @property
    def table_full(self) -> str:
        return f"{self.db}.{self.schema}.{self.table}"

    @property
    def view_full(self) -> str:
        return f"{self.db}.{self.view_schema}.{self.view}"


# Order + business keys derived from reading the live-equivalent repo SQL.
# business_key = the grain each view is expected to be unique at (Layer C probe target).
GOLD_TARGETS: list[GoldTarget] = [
    GoldTarget(1, "W01_shared_dim", GOLD_DB, "Shared_DW", "DimCalendar",
               "Shared_DW_Wrk", "v_DimCalendar", ("DateSK",)),
    GoldTarget(2, "W01_shared_dim", GOLD_DB, "Shared_DW", "DimProduct",
               "Shared_DW_Wrk", "v_DimProduct", ("ItemSKU",)),
    GoldTarget(3, "W01_shared_dim", GOLD_DB, "Shared_DW", "DimWarehouse",
               "Shared_DW_Wrk", "v_DimWarehouse", ("WarehouseCode",)),
    GoldTarget(4, "W10_inv_dim", GOLD_DB, "InventoryHealth_DW", "DimVendor",
               "InventoryHealth_DW_Wrk", "v_DimVendor", ("VendorNumber",)),
    GoldTarget(5, "W20_helper", GOLD_DB, "InventoryHealth_DW",
               "ProjectedInventoryHealthSubStatus",
               "InventoryHealth_DW_Wrk", "v_ProjectedInventoryHealthSubStatus",
               ("ItemSku", "WarehouseCode", "FactAsOfDate", "FutureWeekEndingDate"),
               is_hotspot=True),
    GoldTarget(6, "W20_helper", GOLD_DB, "InventoryHealth_DW",
               "InventoryHealthSubStatusWeekly",
               "InventoryHealth_DW_Wrk", "v_InventoryHealthSubStatusWeekly",
               ("ItemSku", "WarehouseCode", "SnapshotWeekEnding"),
               is_hotspot=True),
    GoldTarget(7, "W21_dependent_helper", GOLD_DB, "InventoryHealth_DW",
               "InventoryClassificationQtyWeekly",
               "InventoryHealth_DW_Wrk", "v_InventoryClassificationQtyWeekly",
               ("Item", "WH", "SnapshotWeekEnding"),
               is_hotspot=True),
    GoldTarget(8, "W30_fact", GOLD_DB, "InventoryHealth_DW",
               "FactInventoryHealthFutureWeekEnding",
               "InventoryHealth_DW_Wrk", "v_FactInventoryHealthFutureWeekEnding",
               ("ItemSku", "WarehouseCode", "FutureWeekEnding", "SnapshotDate"),
               is_hotspot=True),
    GoldTarget(9, "W30_fact", GOLD_DB, "InventoryHealth_DW",
               "FactInventoryHealthSnapshot",
               "InventoryHealth_DW_Wrk", "v_FactInventoryHealthSnapshot",
               ("ItemSku", "WarehouseCode", "SnapshotWeekEndingDate"),
               is_hotspot=True),
]


def target_by_name(name: str) -> GoldTarget | None:
    for t in GOLD_TARGETS:
        if t.table.lower() == name.lower() or t.view.lower() == name.lower():
            return t
    return None
