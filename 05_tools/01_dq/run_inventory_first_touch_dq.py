#!/usr/bin/env python3
"""
Run SELECT-only Inventory Health first-touch Bronze-to-Silver DQ checks.

Scope:
- No CREATE/ALTER/INSERT/DELETE/DROP.
- Uses live Fabric Warehouse SQL endpoint with an Entra token from az CLI.
- Checks every first-touch Silver target with raw/seed ancestry, regardless of wave.

Rule groups per target:
- DQ_Bronze_*: source key null/blank and duplicate grain checks on raw/seed inputs.
- DQ_B2S_*: canonical raw-derived transform view row-count and metric parity vs physical Silver.
- DQ_Silver_Grain_*: physical Silver key null/blank and duplicate grain checks.

Note:
The B2S rule intentionally uses the live *_Wrk.v_* view as the canonical raw-derived
transform expression. This is still SELECT-only and is suitable for live parity evidence.
For a stricter "independent transform" contract, inline each *_Wrk view body into the
DQ view later; do not compare full rows including LoadDT because LoadDT is volatile.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Iterable

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Processing_Warehouse"


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def qobj(*parts: str) -> str:
    return ".".join(quote_name(part) for part in parts)


def token_struct(resource: str) -> bytes:
    token = subprocess.check_output(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            resource,
            "--query",
            "accessToken",
            "-o",
            "tsv",
        ],
        text=True,
    ).strip()
    encoded = token.encode("utf-16-le")
    return struct.pack("<I", len(encoded)) + encoded


def connect() -> pyodbc.Connection:
    conn_str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server={SERVER};Database={DATABASE};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(
        conn_str,
        attrs_before={1256: token_struct("https://database.windows.net/")},
    )


@dataclass(frozen=True)
class Source:
    db: str
    schema: str
    table: str
    grain: tuple[str, ...]
    duplicate_check: bool = True
    where: str | None = None

    @property
    def display(self) -> str:
        return f"{self.db}.{self.schema}.{self.table}"

    @property
    def sql_name(self) -> str:
        return qobj(self.db, self.schema, self.table)


@dataclass(frozen=True)
class Target:
    schema: str
    table: str
    wrk_schema: str
    wrk_view: str
    silver_grain: tuple[str, ...]
    sources: tuple[Source, ...]
    measures: tuple[str, ...] = ()
    note: str = ""

    @property
    def display(self) -> str:
        return f"{self.schema}.{self.table}"

    @property
    def physical_sql_name(self) -> str:
        return qobj(self.schema, self.table)

    @property
    def wrk_sql_name(self) -> str:
        return qobj(self.wrk_schema, self.wrk_view)


EL = "Enterprise_Lakehouse"
SCW = "SupplyChain_Processing_Warehouse"


SOURCES = {
    "warehouse": Source(EL, "CustomerOrders_AFI", "WarehouseMaster", ("Warehouse",)),
    "customer_account": Source(EL, "Customers", "AccountMaster", ("cmaCustomerNumber",)),
    "customer_shipping": Source(
        EL,
        "Customers",
        "ShippingLocations",
        ("cslCustomerNumber", "cslShiptoNumber", "cslMapicsSequenceNumber"),
    ),
    "customer_group": Source(
        EL,
        "Wholesale_ProductSourcing_AFI",
        "CustomerGrouping",
        ("CustomerNumber", "CustomerGroup"),
    ),
    "forecast_cycle": Source(
        SCW,
        "ProcessingSeed",
        "ForecastCycle",
        ("code_cycle", "dt_cycle_month_last", "dt_forecast_snapshot"),
    ),
    "forecast_horizon": Source(SCW, "ProcessingSeed", "ForecastHorizon", ("HorizonCode",)),
    "itmext": Source(EL, "ItemMaster_AFI", "ITMEXT", ("ITNBR",)),
    "aitmcls": Source(EL, "ItemMaster_AFI", "AITMCLS", ("ITMCL",)),
    "dim_item": Source(EL, "MasterData_DW", "DimItemMaster", ("ItemSKU",)),
    "item_env": Source(EL, "MasterData_ProductKnowledge", "Item_ENV", ("ienItemNumber", "ienEnvironmentCode")),
    "non_pk_items": Source(EL, "Wholesale_ProductSourcing", "NonPkItems", ("npkItemNumber",)),
    "order_type": Source(EL, "Wholesale_Codis_AFI", "AAORDTYP", ("OTCODE",)),
    "vendor": Source(EL, "Purchasing_AFI", "VendorMaster", ("VendorNumber",)),
    "dim_date": Source(EL, "MasterData_DW", "DimDate", ("DateKey",)),
    "demand_inventory": Source(
        EL,
        "SupplyChain_Enh",
        "DemandInventorySnapshotDaily",
        ("dinSnapshot", "dinItem", "dinWarehouse", "dinFiscalMonth"),
    ),
    "atp": Source(
        EL,
        "SupplyChain_Enh",
        "ATPWeekEnding",
        ("WeekEnding", "RunDate", "InsertedDate", "ItemSKU", "Warehouse", "AFIFinanceDivision", "ATPWeek", "InsertedVersion"),
    ),
    "po_snapshot": Source(
        EL,
        "SupplyChain_Enh",
        "PurchaseOrderSnapshot",
        ("posSnapshot", "posItNbr", "posWhse", "posVndnr", "posDueDt"),
    ),
    "momast": Source(EL, "Manufacturing_ProductionPlanning_AFI", "MOMAST", ("ORDNO",)),
    "tfrdtl": Source(EL, "Manufacturing_Inventory_AFI", "TFRDTL", ("DTFRNO", "DITNBR")),
    "tfrhdr": Source(EL, "Manufacturing_Inventory_AFI", "TFRHDR", ("HTFRNO",)),
    "demand_forecast": Source(
        EL,
        "SupplyChain_Enh",
        "DemandForecastSnapshotDaily",
        ("dfcSnapshot", "dfcItem", "dfcWarehouse", "dfcFiscalMonth", "DfcCustomerGroups", "dfcFCSTTypeCode", "dfcMgmtCode"),
    ),
    "supply_plan": Source(
        EL,
        "SupplyChain_Enh",
        "SupplyPlanDetailSnapshotDaily",
        ("dtea", "spdItem", "spdWarehouse", "spdWeekEnding"),
    ),
    "item_balance": Source(EL, "Inventory_Enh_History", "ItemBalance", ("ItemNumber", "Warehouse", "DateWeekEnding")),
    "invoice_detail": Source(
        EL,
        "SalesHistory_AFI_Enh",
        "InvoiceDetail",
        (
            "InvoiceNumber",
            "ExtendedInvoiceNumber",
            "OrderNumber",
            "ItemSequence",
            "CustomerNumber",
            "ShiptoNumber",
            "ItemSKU",
            "Warehouse",
            "InvoiceDate",
            "OrderDate",
            "RequestDate",
            "CurrentRequestDate",
            "CurrentPromiseDate",
            "OriginalRequestDate",
            "OriginalPromiseDate",
            "PromisedDelivery",
            "DeliveryDate",
            "ActualDelivery",
            "OrderType",
            "OrderType3",
            "CreditCode",
            "ItemClass",
            "OrderItemStatus",
        ),
        duplicate_check=False,
    ),
    "invoice_header": Source(EL, "SalesHistory_AFI_Enh", "InvoiceHeader", ("InvoiceNumber", "InvoiceDate", "OrderDate", "OrderNumber")),
    "logility": Source(
        EL,
        "SupplyChain_Enh",
        "DemandFulfillmentCommonContainer_Logility",
        ("WeekEnding", "Item", "Whse"),
    ),
    "itembl": Source(EL, "ItemMaster_AFI", "ITEMBL", ("ITNBR", "HOUSE")),
    "cur_fcst": Source(
        EL,
        "SupplyChain_Enh",
        "CurFcStSnapshotWeekly",
        ("SnapshotDate", "ItemSku", "Warehouse", "FiscalMonthLastDate"),
    ),
    "itmrva": Source(EL, "ItemMaster_AFI", "ITMRVA", ("STID", "ITNBR", "ITRV")),
}


TARGETS: tuple[Target, ...] = (
    Target("ReferenceMaster_Enh", "Calendar", "ReferenceMaster_Enh_Wrk", "v_Calendar", ("SKDate",), (SOURCES["dim_date"],)),
    Target("ReferenceMaster_Enh", "CustomerAccount", "ReferenceMaster_Enh_Wrk", "v_CustomerAccount", ("cmaCustomerNumber",), (SOURCES["customer_account"],)),
    Target("ReferenceMaster_Enh", "CustomerAccountGroup", "ReferenceMaster_Enh_Wrk", "v_CustomerAccountGroup", ("Customer", "CustomerGroupCode"), (SOURCES["customer_group"],)),
    Target("ReferenceMaster_Enh", "CustomerGrouping", "ReferenceMaster_Enh_Wrk", "v_CustomerGrouping", ("Customer", "CustomerGroupCode"), (SOURCES["customer_group"],)),
    Target("ReferenceMaster_Enh", "CustomerShippingLocation", "ReferenceMaster_Enh_Wrk", "v_CustomerShippingLocation", ("cslCustomerNumber", "cslShiptoNumber", "cslMapicsSequenceNumber"), (SOURCES["customer_shipping"],)),
    Target("ReferenceMaster_Enh", "ForecastCycle", "ReferenceMaster_Enh_Wrk", "v_ForecastCycle", ("CycleName", "CycleMonthLastDate", "ForecastSnapshot"), (SOURCES["forecast_cycle"],)),
    Target("ReferenceMaster_Enh", "ForecastHorizon", "ReferenceMaster_Enh_Wrk", "v_ForecastHorizon", ("HorizonCode",), (SOURCES["forecast_horizon"],)),
    Target("ReferenceMaster_Enh", "ItemMaster", "ReferenceMaster_Enh_Wrk", "v_ItemMaster", ("ItemSKU",), (SOURCES["itmext"], SOURCES["aitmcls"], SOURCES["dim_item"], SOURCES["item_env"], SOURCES["non_pk_items"])),
    Target("ReferenceMaster_Enh", "OrderType", "ReferenceMaster_Enh_Wrk", "v_OrderType", ("OTCODE",), (SOURCES["order_type"],)),
    Target("ReferenceMaster_Enh", "Vendor", "ReferenceMaster_Enh_Wrk", "v_Vendor", ("VendorNumber",), (SOURCES["vendor"],)),
    Target("ReferenceMaster_Enh", "Warehouse", "ReferenceMaster_Enh_Wrk", "v_Warehouse", ("WarehouseCode",), (SOURCES["warehouse"],)),
    Target("InventoryHistory_Enh", "InventorySnapshotWeekly", "InventoryHistory_Enh_Wrk", "v_InventorySnapshotWeekly", ("ItemSku", "WarehouseCode", "SnapshotWeekEndingDate", "FiscalMonth"), (SOURCES["demand_inventory"],), ("OnHandQty", "SafetyStockTarget", "OrderQty")),
    Target("InventoryHistory_Enh", "AtpWeekEnding", "InventoryHistory_Enh_Wrk", "v_AtpWeekEnding", ("ItemSku", "WarehouseCode", "SnapshotDate", "ATPWeek", "WeekEndingDate", "InsertedVersion"), (SOURCES["atp"],), ("AtpQty", "APNQ")),
    Target("InventoryHistory_Enh", "PurchaseOrderSnapshotHistorical", "InventoryHistory_Enh_Wrk", "v_PurchaseOrderSnapshotHistorical", ("SnapshotDate", "ItemSku", "WarehouseCode", "VendorNumber", "DueDate"), (SOURCES["po_snapshot"],), ("OrderedQty", "POOnOrderQty", "POInTransitQty")),
    Target("InventoryHistory_Enh", "ManufacturingOrderSnapshotDaily", "InventoryHistory_Enh_Wrk", "v_ManufacturingOrderSnapshotDaily", ("SnapshotDate", "MoNumber"), (SOURCES["momast"],), ("RemainingMOQty", "OrderQty")),
    Target("InventoryHistory_Enh", "HoldingTransferSnapshotDaily", "InventoryHistory_Enh_Wrk", "v_HoldingTransferSnapshotDaily", ("SnapshotDate", "TransferNumber", "TransferLine"), (SOURCES["tfrdtl"], SOURCES["tfrhdr"]), ("TransferQty", "ShippedQty")),
    Target("InventoryHistory_Enh", "ForecastSnapshotWeekly", "InventoryHistory_Enh_Wrk", "v_ForecastSnapshotWeekly", ("ItemSku", "WarehouseCode", "SnapshotWeekEndingDate", "FiscalMonth"), (SOURCES["demand_forecast"],), ("ForecastQty", "PromoLiftQty"), "Raw is first cleaned through Staging.DemandForecastSnapshotDaily."),
    Target("InventoryHistory_Enh", "SupplyPlanDetail", "InventoryHistory_Enh_Wrk", "v_SupplyPlanDetail", ("ItemSku", "WarehouseCode", "SnapshotDate", "WeekEnding"), (SOURCES["supply_plan"],), ("FirmDemandQty", "NetFcstQty", "TotalReceiptQty")),
    Target("InventoryHistory_Enh", "ItemBalanceHistorical_WithInTransit", "InventoryHistory_Enh_Wrk", "v_ItemBalanceHistorical_WithInTransit", ("ItemSku", "WarehouseCode", "WeekEndingDate"), (SOURCES["item_balance"],), ("OnHandQty", "InTransitQty", "TotalAvailQty")),
    Target("SalesHistory_Enh", "InvoiceDetailLineLevel", "SalesHistory_Enh_Wrk", "v_InvoiceDetailLineLevel", ("InvoiceID", "InvoiceExtended", "OrderID", "ItemSequenceNum", "ItemSKU", "WarehouseCode"), (SOURCES["invoice_detail"], SOURCES["invoice_header"]), ("QtyShipped", "QtyOrdered", "AmtNetSales")),
    Target("InventoryHistory_Enh", "AFIStatusSnapshotWeekly", "InventoryHistory_Enh_Wrk", "v_AFIStatusSnapshotWeekly", ("ItemSku", "WarehouseCode", "WeekEndingDate"), (SOURCES["logility"],), (), "Mixed raw + Silver upstream."),
    Target("InventoryHistory_Enh", "AwdHelper", "InventoryHistory_Enh_Wrk", "v_AwdHelper", ("ItemSku", "WarehouseCode", "AsOfDate"), (SOURCES["itembl"], SOURCES["cur_fcst"]), ("AwdQty", "ThreeMoTotalDemandQty", "Hist13WShippedQty"), "Mixed raw + Silver upstream."),
    Target("InventoryHistory_Enh", "Cogs52WWeekly", "InventoryHistory_Enh_Wrk", "v_Cogs52WWeekly", ("ItemSku", "WarehouseCode", "WeekEndingDate"), (SOURCES["itmrva"],), ("PeriodCogs", "COGS52W", "ShippedQty52W"), "Mixed raw + Silver upstream."),
)


def blank_condition(columns: Iterable[str]) -> str:
    checks = []
    for column in columns:
        c = quote_name(column)
        checks.append(f"{c} IS NULL OR NULLIF(TRIM(CAST({c} AS VARCHAR(8000))), '') IS NULL")
    return " OR ".join(f"({check})" for check in checks)


def group_duplicate_sql(table_sql: str, columns: tuple[str, ...], where: str | None = None) -> str:
    select_cols = ", ".join(quote_name(column) for column in columns)
    where_clause = f"WHERE {where}" if where else ""
    return f"""
SELECT
    COUNT_BIG(*) AS duplicate_groups,
    COALESCE(SUM(row_count - 1), 0) AS duplicate_extra_rows,
    COALESCE(MAX(row_count), 0) AS max_rows_per_key
FROM (
    SELECT {select_cols}, COUNT_BIG(*) AS row_count
    FROM {table_sql}
    {where_clause}
    GROUP BY {select_cols}
    HAVING COUNT_BIG(*) > 1
) d
"""


def single_value(cur: pyodbc.Cursor, sql: str):
    row = cur.execute(sql).fetchone()
    return row[0] if row else None


def fetch_one_dict(cur: pyodbc.Cursor, sql: str) -> dict:
    row = cur.execute(sql).fetchone()
    if not row:
        return {}
    return {desc[0]: row[idx] for idx, desc in enumerate(cur.description)}


def run_bronze(cur: pyodbc.Cursor, target: Target) -> dict:
    source_results = []
    total_blank = 0
    total_duplicate_groups = 0
    total_duplicate_extra = 0
    failures = []

    for source in target.sources:
        table_sql = source.sql_name
        where_clause = f"WHERE {source.where}" if source.where else ""
        row_count = single_value(cur, f"SELECT COUNT_BIG(*) FROM {table_sql} {where_clause}")
        blank_rows = single_value(
            cur,
            f"SELECT COUNT_BIG(*) FROM {table_sql} {where_clause + ' AND' if source.where else 'WHERE'} {blank_condition(source.grain)}",
        )
        if source.duplicate_check:
            dup = fetch_one_dict(cur, group_duplicate_sql(table_sql, source.grain, source.where))
        else:
            dup = {
                "duplicate_groups": 0,
                "duplicate_extra_rows": 0,
                "max_rows_per_key": 0,
            }

        blank_rows = int(blank_rows or 0)
        duplicate_groups = int(dup.get("duplicate_groups") or 0)
        duplicate_extra = int(dup.get("duplicate_extra_rows") or 0)
        source_result = {
            "source": source.display,
            "grain": list(source.grain),
            "row_count": int(row_count or 0),
            "blank_or_null_key_rows": blank_rows,
            "duplicate_groups": duplicate_groups,
            "duplicate_extra_rows": duplicate_extra,
            "duplicate_check": source.duplicate_check,
        }
        source_results.append(source_result)
        total_blank += blank_rows
        total_duplicate_groups += duplicate_groups
        total_duplicate_extra += duplicate_extra
        if blank_rows or duplicate_groups:
            failures.append(source.display)

    return {
        "rule_name": f"DQ_Bronze_Grain_{target.table}",
        "rule_type": "DQ_Bronze",
        "target": target.display,
        "result": "FAIL" if failures else "PASS",
        "blank_or_null_key_rows": total_blank,
        "duplicate_groups": total_duplicate_groups,
        "duplicate_extra_rows": total_duplicate_extra,
        "sources": source_results,
    }


def metric_sum_sql(table_sql: str, measures: tuple[str, ...]) -> str:
    if not measures:
        return "SELECT CAST(0 AS DECIMAL(38,4)) AS metric_sum"
    terms = [
        f"COALESCE(SUM(CAST({quote_name(measure)} AS DECIMAL(38,4))), 0)"
        for measure in measures
    ]
    return "SELECT " + " + ".join(terms) + f" AS metric_sum FROM {table_sql}"


def run_b2s(cur: pyodbc.Cursor, target: Target) -> dict:
    expected_rows = single_value(cur, f"SELECT COUNT_BIG(*) FROM {target.wrk_sql_name}")
    actual_rows = single_value(cur, f"SELECT COUNT_BIG(*) FROM {target.physical_sql_name}")
    expected_metric = single_value(cur, metric_sum_sql(target.wrk_sql_name, target.measures))
    actual_metric = single_value(cur, metric_sum_sql(target.physical_sql_name, target.measures))
    expected_metric = float(expected_metric or 0)
    actual_metric = float(actual_metric or 0)
    metric_delta = abs(expected_metric - actual_metric)
    rows_match = int(expected_rows or 0) == int(actual_rows or 0)
    metrics_match = metric_delta < 0.0001
    return {
        "rule_name": f"DQ_B2S_{target.table}_WrkExpectedParity",
        "rule_type": "DQ_B2S",
        "target": target.display,
        "result": "PASS" if rows_match and metrics_match else "FAIL",
        "expected_rows": int(expected_rows or 0),
        "actual_rows": int(actual_rows or 0),
        "expected_metric_sum": expected_metric,
        "actual_metric_sum": actual_metric,
        "metric_delta_abs": metric_delta,
        "measures": list(target.measures),
        "note": target.note,
    }


def run_silver_grain(cur: pyodbc.Cursor, target: Target) -> dict:
    table_sql = target.physical_sql_name
    blank_rows = single_value(
        cur,
        f"SELECT COUNT_BIG(*) FROM {table_sql} WHERE {blank_condition(target.silver_grain)}",
    )
    dup = fetch_one_dict(cur, group_duplicate_sql(table_sql, target.silver_grain))
    blank_rows = int(blank_rows or 0)
    duplicate_groups = int(dup.get("duplicate_groups") or 0)
    duplicate_extra = int(dup.get("duplicate_extra_rows") or 0)
    return {
        "rule_name": f"DQ_Silver_Grain_{target.table}",
        "rule_type": "DQ_Silver_Grain",
        "target": target.display,
        "result": "FAIL" if blank_rows or duplicate_groups else "PASS",
        "grain": list(target.silver_grain),
        "blank_or_null_key_rows": blank_rows,
        "duplicate_groups": duplicate_groups,
        "duplicate_extra_rows": duplicate_extra,
    }


def safe_run(rule_fn, target: Target) -> dict:
    start = time.time()
    conn = None
    try:
        conn = connect()
        cur = conn.cursor()
        result = rule_fn(cur, target)
        result["elapsed_seconds"] = round(time.time() - start, 3)
        return result
    except Exception as exc:  # Keep the batch resumable and visible.
        return {
            "rule_name": f"{rule_fn.__name__}_{target.table}",
            "rule_type": rule_fn.__name__.replace("run_", ""),
            "target": target.display,
            "result": "ERROR",
            "error": str(exc),
            "elapsed_seconds": round(time.time() - start, 3),
        }
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


def print_summary(results: list[dict]) -> None:
    print("rule_type\tresult\tcount")
    grouped = {}
    for row in results:
        key = (row["rule_type"], row["result"])
        grouped[key] = grouped.get(key, 0) + 1
    for (rule_type, result), count in sorted(grouped.items()):
        print(f"{rule_type}\t{result}\t{count}")

    print("\nfailed_or_error_rules")
    for row in results:
        if row["result"] != "PASS":
            metrics = []
            for key in (
                "blank_or_null_key_rows",
                "duplicate_groups",
                "duplicate_extra_rows",
                "expected_rows",
                "actual_rows",
                "metric_delta_abs",
                "error",
            ):
                if key in row:
                    metrics.append(f"{key}={row[key]}")
            print(f"{row['result']}\t{row['rule_type']}\t{row['target']}\t{row['rule_name']}\t" + "; ".join(metrics))

    print("\nall_rules")
    for row in results:
        print(f"{row['result']}\t{row['rule_type']}\t{row['target']}\t{row['rule_name']}\t{row.get('elapsed_seconds')}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", help="Optional target table name filter, e.g. InventorySnapshotWeekly")
    parser.add_argument("--json-out", help="Optional JSON output path")
    parser.add_argument("--skip-b2s", action="store_true", help="Skip WrkExpectedParity checks")
    parser.add_argument(
        "--rules",
        default="bronze,b2s,silver",
        help="Comma-separated rule groups to run: bronze,b2s,silver",
    )
    args = parser.parse_args()

    targets = [target for target in TARGETS if not args.target or args.target.lower() in target.display.lower()]
    if not targets:
        print("No target matched.", file=sys.stderr)
        return 2

    requested_rules = {part.strip().lower() for part in args.rules.split(",") if part.strip()}
    valid_rules = {"bronze", "b2s", "silver"}
    invalid_rules = requested_rules - valid_rules
    if invalid_rules:
        print(f"Invalid --rules value(s): {sorted(invalid_rules)}", file=sys.stderr)
        return 2

    results: list[dict] = []
    for target in targets:
        print(f"running {target.display}", file=sys.stderr, flush=True)
        if "bronze" in requested_rules:
            results.append(safe_run(run_bronze, target))
        if "b2s" in requested_rules and not args.skip_b2s:
            results.append(safe_run(run_b2s, target))
        if "silver" in requested_rules:
            results.append(safe_run(run_silver_grain, target))

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "scope": "inventory_health_brz_to_first_touch_silver",
        "target_count": len(targets),
        "rule_count": len(results),
        "results": results,
    }
    if args.json_out:
        os.makedirs(os.path.dirname(args.json_out), exist_ok=True)
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, default=str)

    print_summary(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
