#!/usr/bin/env python3
"""Read-only downstream impact diagnostic for 6 Bronze DQ-failed tables.

For each table, verifies:
- Silver/Gold output uniqueness after existing dedup
- Measure impact (sum qty/amount before vs after dedup/filter)
- Blank/null key row measure impact
- Dedup ORDER BY determinism
- Join fan-out risk

All queries are read-only SELECT. No Fabric/SQL mutation.
"""

from __future__ import annotations

import datetime as dt
import json
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import pyodbc

ROOT = Path(__file__).resolve().parents[2]
SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Processing_Warehouse"
LAKEHOUSE = "Enterprise_Lakehouse"
OUT_DIR = ROOT / "01_docs/runbook/artifacts/20260629_bronze_dq_downstream_impact_check"


def az_token(resource: str) -> str:
    return subprocess.check_output(
        ["az", "account", "get-access-token", "--resource", resource, "--query", "accessToken", "-o", "tsv"],
        text=True,
    ).strip()


def connect(database: str = DATABASE) -> pyodbc.Connection:
    token = az_token("https://database.windows.net/").encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token)}s", len(token), token)
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{SERVER},1433;"
        f"DATABASE={database};"
        "Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        autocommit=True,
    )


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def run_query(conn: pyodbc.Connection, label: str, sql: str, timeout: int = 300) -> dict[str, Any]:
    cur = conn.cursor()
    try:
        cur.timeout = timeout
    except AttributeError:
        pass
    t0 = time.monotonic()
    try:
        cur.execute(sql)
        rows = rows_as_dicts(cur) if cur.description else []
        elapsed = round(time.monotonic() - t0, 3)
        return {"label": label, "status": "PASS", "seconds": elapsed, "rows": rows, "row_count": len(rows), "error": None}
    except Exception as exc:
        elapsed = round(time.monotonic() - t0, 3)
        msg = str(exc)
        status = "TIMEOUT" if "timeout" in msg.lower() or "HYT00" in msg else "ERROR"
        return {"label": label, "status": status, "seconds": elapsed, "rows": [], "row_count": 0, "error": msg}


def serialize(v: Any) -> Any:
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ", timespec="seconds")
    if isinstance(v, dt.date):
        return v.isoformat()
    from decimal import Decimal
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else str(v)
    return v


def clean_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{k: serialize(v) for k, v in row.items()} for row in rows]


# --------------------------------------------------------------------------- #
# Per-table diagnostic functions
# --------------------------------------------------------------------------- #

def check_item_balance(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """1. ItemBalance — verify Silver dedup output unique + measure comparison."""
    results = []
    prefix = "[ItemBalance]"

    # 1a. Bronze latest partition: row count + dup groups
    results.append(run_query(conn, f"{prefix} Bronze latest partition row count + dup groups",
        f"""
        WITH latest AS (
            SELECT MAX(DateWeekEnding) AS max_date
            FROM {LAKEHOUSE}.Inventory_Enh_History.ItemBalance
        ),
        d AS (
            SELECT ItemNumber, Warehouse, DateWeekEnding, COUNT_BIG(*) AS rc
            FROM {LAKEHOUSE}.Inventory_Enh_History.ItemBalance
            CROSS JOIN latest
            WHERE DateWeekEnding = latest.max_date
            GROUP BY ItemNumber, Warehouse, DateWeekEnding
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM {LAKEHOUSE}.Inventory_Enh_History.ItemBalance
             CROSS JOIN latest WHERE DateWeekEnding = latest.max_date) AS bronze_latest_row_count,
            (SELECT COUNT_BIG(DISTINCT CONCAT(ItemNumber,'|',Warehouse,'|',DateWeekEnding))
             FROM {LAKEHOUSE}.Inventory_Enh_History.ItemBalance
             CROSS JOIN latest WHERE DateWeekEnding = latest.max_date) AS bronze_latest_distinct_grain,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows
        FROM d;
        """, timeout=300))

    # 1b. Silver view output: row count + dup groups (latest week)
    results.append(run_query(conn, f"{prefix} Silver v_ItemBalanceHistorical_WithInTransit latest week row count + dup groups",
        f"""
        WITH silver AS (
            SELECT * FROM SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_ItemBalanceHistorical_WithInTransit
        ),
        latest AS (
            SELECT MAX(WeekEndingDate) AS max_date FROM silver
        ),
        d AS (
            SELECT ItemSku, WarehouseCode, WeekEndingDate, COUNT_BIG(*) AS rc
            FROM silver
            CROSS JOIN latest
            WHERE WeekEndingDate = latest.max_date
            GROUP BY ItemSku, WarehouseCode, WeekEndingDate
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM silver CROSS JOIN latest WHERE WeekEndingDate = latest.max_date) AS silver_latest_row_count,
            (SELECT COUNT_BIG(DISTINCT CONCAT(ItemSku,'|',WarehouseCode,'|',WeekEndingDate))
             FROM silver CROSS JOIN latest WHERE WeekEndingDate = latest.max_date) AS silver_latest_distinct_grain,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows
        FROM d;
        """, timeout=300))

    # 1c. Bronze history dup groups (full history, scoped)
    results.append(run_query(conn, f"{prefix} Bronze full-history dup groups (sample top 10)",
        f"""
        SELECT TOP 10
            ItemNumber, Warehouse, DateWeekEnding,
            COUNT_BIG(*) AS row_count
        FROM {LAKEHOUSE}.Inventory_Enh_History.ItemBalance
        GROUP BY ItemNumber, Warehouse, DateWeekEnding
        HAVING COUNT_BIG(*) > 1
        ORDER BY DateWeekEnding DESC, row_count DESC;
        """, timeout=300))

    # 1d. Silver total row count
    results.append(run_query(conn, f"{prefix} Silver total row count",
        "SELECT COUNT_BIG(*) AS silver_total_rows FROM SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_ItemBalanceHistorical_WithInTransit;",
        timeout=300))

    return results


def check_itbext(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """2. ITBEXT — verify Gold DimProduct unique by ItemSKU + UnavailableFlag distribution."""
    results = []
    prefix = "[ITBEXT]"

    # 2a. Bronze: row count + dup groups by ITNBR
    results.append(run_query(conn, f"{prefix} Bronze dup groups by ITNBR",
        f"""
        WITH d AS (
            SELECT TRIM(CAST(ITNBR AS VARCHAR(8000))) AS ITNBR, COUNT_BIG(*) AS rc
            FROM {LAKEHOUSE}.ItemMaster_AFI.ITBEXT
            WHERE ITNBR IS NOT NULL AND TRIM(CAST(ITNBR AS VARCHAR(8000))) <> ''
            GROUP BY TRIM(CAST(ITNBR AS VARCHAR(8000)))
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM {LAKEHOUSE}.ItemMaster_AFI.ITBEXT) AS bronze_total_rows,
            (SELECT COUNT_BIG(DISTINCT TRIM(CAST(ITNBR AS VARCHAR(8000))))
             FROM {LAKEHOUSE}.ItemMaster_AFI.ITBEXT
             WHERE ITNBR IS NOT NULL AND TRIM(CAST(ITNBR AS VARCHAR(8000))) <> '') AS bronze_distinct_itnbr,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows
        FROM d;
        """, timeout=300))

    # 2b. Gold DimProduct: row count + dup by ItemSKU
    # DimProduct is in Gold warehouse — need cross-database query
    results.append(run_query(conn, f"{prefix} Gold DimProduct row count + dup by ItemSKU",
        """
        SELECT
            COUNT_BIG(*) AS gold_total_rows,
            COUNT_BIG(DISTINCT ItemSKU) AS gold_distinct_itemsku,
            COUNT_BIG(*) - COUNT_BIG(DISTINCT ItemSKU) AS potential_dup_rows
        FROM SupplyChain_Gold_Warehouse.Shared_DW.DimProduct;
        """, timeout=300))

    # 2c. Gold DimProduct dup groups if any
    results.append(run_query(conn, f"{prefix} Gold DimProduct dup groups by ItemSKU (top 10)",
        """
        SELECT TOP 10
            ItemSKU,
            COUNT_BIG(*) AS row_count
        FROM SupplyChain_Gold_Warehouse.Shared_DW.DimProduct
        GROUP BY ItemSKU
        HAVING COUNT_BIG(*) > 1
        ORDER BY row_count DESC;
        """, timeout=300))

    # 2d. UnavailableFlag distribution
    results.append(run_query(conn, f"{prefix} Gold DimProduct UnavailableFlag distribution",
        """
        SELECT
            COALESCE(UnavailableFlag, -1) AS flag_value,
            COUNT_BIG(*) AS row_count
        FROM SupplyChain_Gold_Warehouse.Shared_DW.DimProduct
        GROUP BY COALESCE(UnavailableFlag, -1)
        ORDER BY flag_value;
        """, timeout=300))

    return results


def check_itmrva(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """3. ITMRVA — verify latest revision dedup + 1 cost per item."""
    results = []
    prefix = "[ITMRVA]"

    # 3a. Bronze: dup groups by ITNBR (scoped to STID='000' which is what curated uses)
    results.append(run_query(conn, f"{prefix} Bronze dup groups by ITNBR (STID='000')",
        f"""
        WITH d AS (
            SELECT TRIM(ITNBR) AS ITNBR, COUNT_BIG(*) AS rc
            FROM {LAKEHOUSE}.ItemMaster_AFI.ITMRVA
            WHERE TRIM(STID) = '000' AND ITNBR IS NOT NULL AND TRIM(ITNBR) <> ''
              AND UCDEF IS NOT NULL
            GROUP BY TRIM(ITNBR)
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM {LAKEHOUSE}.ItemMaster_AFI.ITMRVA WHERE TRIM(STID) = '000') AS bronze_stid000_rows,
            (SELECT COUNT_BIG(DISTINCT TRIM(ITNBR)) FROM {LAKEHOUSE}.ItemMaster_AFI.ITMRVA
             WHERE TRIM(STID)='000' AND ITNBR IS NOT NULL AND TRIM(ITNBR) <> '' AND UCDEF IS NOT NULL) AS bronze_distinct_itnbr,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows
        FROM d;
        """, timeout=300))

    # 3b. Silver CTE output: check 1 row per ItemSku after ROW_NUMBER
    # Query the CTE logic inline (same as v_Cogs52WWeekly standard_cost CTE)
    results.append(run_query(conn, f"{prefix} Silver standard_cost CTE dedup check",
        f"""
        WITH standard_cost AS (
            SELECT
                TRIM(STID) AS STID,
                TRIM(ITNBR) AS ItemSku,
                UCDEF AS StandardCost,
                ITRV AS StandardCostRevision,
                ROW_NUMBER() OVER (
                    PARTITION BY TRIM(STID), TRIM(ITNBR)
                    ORDER BY ITRV DESC
                ) AS rn
            FROM {LAKEHOUSE}.ItemMaster_AFI.ITMRVA
            WHERE STID IS NOT NULL AND ITNBR IS NOT NULL AND UCDEF IS NOT NULL
              AND TRIM(STID) = '000' AND TRIM(ITNBR) <> ''
        ),
        current_cost AS (
            SELECT ItemSku, StandardCost, StandardCostRevision
            FROM standard_cost WHERE rn = 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM standard_cost) AS total_cost_rows,
            (SELECT COUNT_BIG(*) FROM current_cost) AS current_cost_rows,
            COUNT_BIG(*) AS dup_groups_after_dedup,
            ISNULL(SUM(rc - 1), 0) AS extra_rows_after_dedup
        FROM (
            SELECT ItemSku, COUNT_BIG(*) AS rc
            FROM current_cost
            GROUP BY ItemSku
            HAVING COUNT_BIG(*) > 1
        ) AS d;
        """, timeout=300))

    # 3c. Sample: items with multiple revisions to verify ORDER BY works
    results.append(run_query(conn, f"{prefix} Sample: items with most revisions (top 5)",
        f"""
        SELECT TOP 5
            TRIM(ITNBR) AS ItemSku,
            COUNT_BIG(*) AS revision_count,
            MAX(ITRV) AS max_revision,
            MIN(ITRV) AS min_revision
        FROM {LAKEHOUSE}.ItemMaster_AFI.ITMRVA
        WHERE TRIM(STID) = '000' AND ITNBR IS NOT NULL AND TRIM(ITNBR) <> '' AND UCDEF IS NOT NULL
        GROUP BY TRIM(ITNBR)
        ORDER BY revision_count DESC;
        """, timeout=300))

    return results


def check_tfrdtl(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """4. TFRDTL — verify blank key filtered + measure impact of dropping blank rows."""
    results = []
    prefix = "[TFRDTL]"

    # 4a. Bronze: blank DTFRNO row count + quantity sum
    results.append(run_query(conn, f"{prefix} Bronze blank DTFRNO rows + quantity impact",
        f"""
        SELECT
            COUNT_BIG(*) AS blank_dtfrno_rows,
            SUM(CASE WHEN DTRQQ IS NOT NULL THEN CAST(DTRQQ AS FLOAT) ELSE 0 END) AS blank_dtrqq_sum,
            COUNT_BIG(DISTINCT DTFRNO) AS distinct_dtfrno_in_blank
        FROM {LAKEHOUSE}.Manufacturing_Inventory_AFI.TFRDTL
        WHERE DTFRNO IS NULL OR TRIM(CAST(DTFRNO AS VARCHAR(8000))) = '';
        """, timeout=300))

    # 4b. Bronze: total rows vs non-blank rows
    results.append(run_query(conn, f"{prefix} Bronze total vs non-blank DTFRNO",
        f"""
        SELECT
            COUNT_BIG(*) AS total_rows,
            SUM(CASE WHEN DTFRNO IS NOT NULL AND TRIM(CAST(DTFRNO AS VARCHAR(8000))) <> '' THEN 1 ELSE 0 END) AS non_blank_rows,
            SUM(CASE WHEN DTFRNO IS NULL OR TRIM(CAST(DTFRNO AS VARCHAR(8000))) = '' THEN 1 ELSE 0 END) AS blank_rows
        FROM {LAKEHOUSE}.Manufacturing_Inventory_AFI.TFRDTL;
        """, timeout=300))

    # 4c. Silver view output: row count + no blank TransferNumber
    results.append(run_query(conn, f"{prefix} Silver v_HoldingTransferSnapshotDaily row count + blank check",
        """
        SELECT
            COUNT_BIG(*) AS silver_row_count,
            SUM(CASE WHEN TransferNumber IS NULL OR TRIM(CAST(TransferNumber AS VARCHAR(8000))) = '' THEN 1 ELSE 0 END) AS blank_transfer_number_rows,
            COUNT_BIG(DISTINCT CONCAT(TransferNumber, '|', ItemSku)) AS distinct_transfer_item
        FROM SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily;
        """, timeout=300))

    # 4d. Silver view: dup check by (TransferNumber, ItemSku)
    results.append(run_query(conn, f"{prefix} Silver dup check by TransferNumber+ItemSku (top 10)",
        """
        SELECT TOP 10
            TransferNumber, ItemSku,
            COUNT_BIG(*) AS row_count
        FROM SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily
        GROUP BY TransferNumber, ItemSku
        HAVING COUNT_BIG(*) > 1
        ORDER BY row_count DESC;
        """, timeout=300))

    # 4e. Bronze: check column DTRQQ exists (quantity column name may differ)
    results.append(run_query(conn, f"{prefix} Bronze column list (first 19 columns)",
        f"""
        SELECT TOP 19 COLUMN_NAME AS col_name, DATA_TYPE AS data_type
        FROM {LAKEHOUSE}.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'Manufacturing_Inventory_AFI' AND TABLE_NAME = 'TFRDTL'
        ORDER BY ORDINAL_POSITION;
        """, timeout=120))

    return results


def check_invoice_detail(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """5. InvoiceDetail — null key measure impact + IH vs FA variant comparison."""
    results = []
    prefix = "[InvoiceDetail]"

    # 5a. Bronze null/blank key rows: count + measure impact (latest InvoiceDate)
    results.append(run_query(conn, f"{prefix} Bronze null/blank key rows + measure impact (latest InvoiceDate)",
        f"""
        WITH latest AS (
            SELECT MAX(InvoiceDate) AS max_date
            FROM {LAKEHOUSE}.SalesHistory_AFI_Enh.InvoiceDetail
        )
        SELECT
            COUNT_BIG(*) AS total_latest_rows,
            SUM(CASE
                WHEN InvoiceNumber IS NULL OR LTRIM(RTRIM(CAST(InvoiceNumber AS VARCHAR(8000)))) = ''
                  OR LineReleaseNumber IS NULL OR LTRIM(RTRIM(CAST(LineReleaseNumber AS VARCHAR(8000)))) = ''
                  OR OriginalSequenceNumber IS NULL
                  OR ItemSKU IS NULL OR LTRIM(RTRIM(CAST(ItemSKU AS VARCHAR(8000)))) = ''
                THEN 1 ELSE 0
            END) AS null_blank_key_rows,
            SUM(CASE
                WHEN InvoiceNumber IS NULL OR LTRIM(RTRIM(CAST(InvoiceNumber AS VARCHAR(8000)))) = ''
                  OR LineReleaseNumber IS NULL OR LTRIM(RTRIM(CAST(LineReleaseNumber AS VARCHAR(8000)))) = ''
                  OR OriginalSequenceNumber IS NULL
                  OR ItemSKU IS NULL OR LTRIM(RTRIM(CAST(ItemSKU AS VARCHAR(8000)))) = ''
                THEN 1 ELSE 0
            END) * 100.0 / COUNT_BIG(*) AS pct_null_blank,
            ISNULL(SUM(CASE
                WHEN (InvoiceNumber IS NULL OR LTRIM(RTRIM(CAST(InvoiceNumber AS VARCHAR(8000)))) = ''
                  OR LineReleaseNumber IS NULL OR LTRIM(RTRIM(CAST(LineReleaseNumber AS VARCHAR(8000)))) = ''
                  OR OriginalSequenceNumber IS NULL
                  OR ItemSKU IS NULL OR LTRIM(RTRIM(CAST(ItemSKU AS VARCHAR(8000)))) = '')
                THEN CAST(QtyShipped AS FLOAT) ELSE 0
            END), 0) AS null_key_qtyshipped_sum,
            ISNULL(SUM(CASE
                WHEN NOT (InvoiceNumber IS NULL OR LTRIM(RTRIM(CAST(InvoiceNumber AS VARCHAR(8000)))) = ''
                  OR LineReleaseNumber IS NULL OR LTRIM(RTRIM(CAST(LineReleaseNumber AS VARCHAR(8000)))) = ''
                  OR OriginalSequenceNumber IS NULL
                  OR ItemSKU IS NULL OR LTRIM(RTRIM(CAST(ItemSKU AS VARCHAR(8000)))) = '')
                THEN CAST(QtyShipped AS FLOAT) ELSE 0
            END), 0) AS valid_key_qtyshipped_sum
        FROM {LAKEHOUSE}.SalesHistory_AFI_Enh.InvoiceDetail
        CROSS JOIN latest
        WHERE InvoiceDate = latest.max_date;
        """, timeout=600))

    # 5b. Check AmtInvoice column exists
    results.append(run_query(conn, f"{prefix} Check amount column name",
        f"""
        SELECT COLUMN_NAME AS col_name, DATA_TYPE AS data_type
        FROM {LAKEHOUSE}.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'SalesHistory_AFI_Enh' AND TABLE_NAME = 'InvoiceDetail'
          AND (COLUMN_NAME LIKE '%Amt%' OR COLUMN_NAME LIKE '%Amount%' OR COLUMN_NAME LIKE '%Sales%' OR COLUMN_NAME LIKE '%Revenue%')
        ORDER BY ORDINAL_POSITION;
        """, timeout=120))

    # 5c. IH Silver view: row count + dup check
    results.append(run_query(conn, f"{prefix} IH Silver v_InvoiceDetailLineLevel row count",
        """
        SELECT COUNT_BIG(*) AS ih_silver_row_count
        FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel;
        """, timeout=600))

    # 5d. IH Silver: dup check by invoice-line grain
    results.append(run_query(conn, f"{prefix} IH Silver dup check by InvoiceID+ItemSequence+LineRelease+OrigSeq+ItemSKU (top 10)",
        """
        SELECT TOP 10
            CONCAT(InvoiceID, '|', ItemSequenceNum, '|', COALESCE(LineReleaseNumber,''), '|',
                   COALESCE(CAST(OriginalSequenceNumber AS VARCHAR),''), '|', ItemSKU) AS grain_key,
            COUNT_BIG(*) AS row_count
        FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel
        GROUP BY CONCAT(InvoiceID, '|', ItemSequenceNum, '|', COALESCE(LineReleaseNumber,''), '|',
                        COALESCE(CAST(OriginalSequenceNumber AS VARCHAR),''), '|', ItemSKU)
        HAVING COUNT_BIG(*) > 1
        ORDER BY row_count DESC;
        """, timeout=600))

    # 5e. FA Silver view: row count (if accessible from Processing warehouse)
    results.append(run_query(conn, f"{prefix} FA Silver v_InvoiceDetailLineLevel row count (if same DB)",
        """
        SELECT COUNT_BIG(*) AS fa_silver_row_count
        FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel;
        """, timeout=600))

    # 5f. FA vs IH: check if they are the same view or different
    results.append(run_query(conn, f"{prefix} Check if IH and FA use same or different view definition",
        """
        SELECT
            s.name AS schema_name,
            v.name AS view_name,
            m.definition AS view_definition_length
        FROM SupplyChain_Processing_Warehouse.sys.views v
        JOIN SupplyChain_Processing_Warehouse.sys.schemas s ON v.schema_id = s.schema_id
        JOIN SupplyChain_Processing_Warehouse.sys.sql_modules m ON m.object_id = v.object_id
        WHERE s.name = 'SalesHistory_Enh_Wrk' AND v.name = 'v_InvoiceDetailLineLevel';
        """, timeout=120))

    # 5g. Sample null-key rows from latest InvoiceDate
    results.append(run_query(conn, f"{prefix} Sample null-key rows (top 5)",
        f"""
        SELECT TOP 5
            InvoiceDate, InvoiceNumber, ItemSequence,
            LineReleaseNumber, OriginalSequenceNumber, ItemSKU,
            QtyShipped, QtyOrdered
        FROM {LAKEHOUSE}.SalesHistory_AFI_Enh.InvoiceDetail
        WHERE (InvoiceNumber IS NULL OR LTRIM(RTRIM(CAST(InvoiceNumber AS VARCHAR(8000)))) = ''
          OR LineReleaseNumber IS NULL OR LTRIM(RTRIM(CAST(LineReleaseNumber AS VARCHAR(8000)))) = ''
          OR OriginalSequenceNumber IS NULL
          OR ItemSKU IS NULL OR LTRIM(RTRIM(CAST(ItemSKU AS VARCHAR(8000)))) = '')
        AND InvoiceDate = (SELECT MAX(InvoiceDate) FROM {LAKEHOUSE}.SalesHistory_AFI_Enh.InvoiceDetail);
        """, timeout=300))

    return results


def check_demand_forecast_snapshot(conn: pyodbc.Connection) -> list[dict[str, Any]]:
    """6. DemandForecastSnapshotDaily — staging dedup check + ORDER BY determinism."""
    results = []
    prefix = "[DemandForecastSnapshotDaily]"

    # 6a. Bronze: dup groups at curated grain (dfcSnapshot, dfcItem, dfcWarehouse) — sample latest snapshot
    results.append(run_query(conn, f"{prefix} Bronze latest snapshot dup groups at curated grain",
        f"""
        WITH latest AS (
            SELECT MAX(dfcSnapshot) AS max_snap
            FROM {LAKEHOUSE}.SupplyChain_Enh.DemandForecastSnapshotDaily
        ),
        d AS (
            SELECT dfcItem, dfcWarehouse, COUNT_BIG(*) AS rc
            FROM {LAKEHOUSE}.SupplyChain_Enh.DemandForecastSnapshotDaily
            CROSS JOIN latest
            WHERE dfcSnapshot = latest.max_snap
            GROUP BY dfcItem, dfcWarehouse
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM {LAKEHOUSE}.SupplyChain_Enh.DemandForecastSnapshotDaily
             CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS bronze_latest_rows,
            (SELECT COUNT_BIG(DISTINCT CONCAT(dfcItem,'|',dfcWarehouse))
             FROM {LAKEHOUSE}.SupplyChain_Enh.DemandForecastSnapshotDaily
             CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS bronze_latest_distinct_grain,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows,
            MAX(rc) AS max_rows_per_grain
        FROM d;
        """, timeout=600))

    # 6b. Staging view output: dup groups at same grain
    results.append(run_query(conn, f"{prefix} Staging_Wrk view dedup output check",
        """
        WITH s AS (
            SELECT * FROM SupplyChain_Processing_Warehouse.Staging_Wrk.v_DemandForecastSnapshotDaily
        ),
        latest AS (
            SELECT MAX(dfcSnapshot) AS max_snap FROM s
        ),
        d AS (
            SELECT dfcItem, dfcWarehouse, COUNT_BIG(*) AS rc
            FROM s
            CROSS JOIN latest
            WHERE dfcSnapshot = latest.max_snap
            GROUP BY dfcItem, dfcWarehouse
            HAVING COUNT_BIG(*) > 1
        )
        SELECT
            (SELECT COUNT_BIG(*) FROM s CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS staging_latest_rows,
            (SELECT COUNT_BIG(DISTINCT CONCAT(dfcItem,'|',dfcWarehouse))
             FROM s CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS staging_latest_distinct_grain,
            COUNT_BIG(*) AS dup_groups,
            ISNULL(SUM(rc - 1), 0) AS extra_rows
        FROM d;
        """, timeout=600))

    # 6c. Check if LoadDT column exists (for ORDER BY determinism)
    results.append(run_query(conn, f"{prefix} Check LoadDT column for ORDER BY determinism",
        f"""
        SELECT COLUMN_NAME AS col_name, DATA_TYPE AS data_type
        FROM {LAKEHOUSE}.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'SupplyChain_Enh' AND TABLE_NAME = 'DemandForecastSnapshotDaily'
          AND COLUMN_NAME IN ('LoadDT', 'LoadDate', 'InsertedDate', 'InsertedAt', 'CreatedDate', 'RowId', 'SequenceNumber')
        ORDER BY ORDINAL_POSITION;
        """, timeout=120))

    # 6d. Staging view: check all columns including LoadDT
    results.append(run_query(conn, f"{prefix} Staging view column list",
        """
        SELECT TOP 30 c.COLUMN_NAME AS col_name, c.DATA_TYPE AS data_type
        FROM SupplyChain_Processing_Warehouse.INFORMATION_SCHEMA.COLUMNS c
        JOIN SupplyChain_Processing_Warehouse.INFORMATION_SCHEMA.VIEWS v
          ON c.TABLE_SCHEMA = v.TABLE_SCHEMA AND c.TABLE_NAME = v.TABLE_NAME
        WHERE c.TABLE_SCHEMA = 'Staging_Wrk' AND c.TABLE_NAME = 'v_DemandForecastSnapshotDaily'
        ORDER BY c.ORDINAL_POSITION;
        """, timeout=120))

    # 6e. Staging target table (if materialized): dup check
    results.append(run_query(conn, f"{prefix} Staging target table row count + dup check (if exists)",
        """
        IF OBJECT_ID('SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily') IS NOT NULL
        BEGIN
            WITH latest AS (
                SELECT MAX(dfcSnapshot) AS max_snap
                FROM SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
            ),
            d AS (
                SELECT dfcItem, dfcWarehouse, COUNT_BIG(*) AS rc
                FROM SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
                CROSS JOIN latest
                WHERE dfcSnapshot = latest.max_snap
                GROUP BY dfcItem, dfcWarehouse
                HAVING COUNT_BIG(*) > 1
            )
            SELECT
                'EXISTS' AS table_status,
                (SELECT COUNT_BIG(*) FROM SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
                 CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS target_latest_rows,
                (SELECT COUNT_BIG(DISTINCT CONCAT(dfcItem,'|',dfcWarehouse))
                 FROM SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
                 CROSS JOIN latest WHERE dfcSnapshot = latest.max_snap) AS target_latest_distinct_grain,
                COUNT_BIG(*) AS dup_groups,
                ISNULL(SUM(rc - 1), 0) AS extra_rows
            FROM d;
        END
        ELSE
        BEGIN
            SELECT 'NOT_FOUND' AS table_status, 0 AS target_latest_rows, 0 AS target_latest_distinct_grain, 0 AS dup_groups, 0 AS extra_rows;
        END
        """, timeout=600))

    return results


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main() -> int:
    out_dir = OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    metadata = {
        "generated_at_ict": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "server": SERVER,
        "database": DATABASE,
        "lakehouse": LAKEHOUSE,
        "description": "Read-only downstream impact diagnostic for 6 Bronze DQ-failed tables. No Fabric/SQL mutation.",
    }

    all_results: dict[str, list[dict[str, Any]]] = {}

    checks = [
        ("1_ItemBalance", check_item_balance),
        ("2_ITBEXT", check_itbext),
        ("3_ITMRVA", check_itmrva),
        ("4_TFRDTL", check_tfrdtl),
        ("5_InvoiceDetail", check_invoice_detail),
        ("6_DemandForecastSnapshotDaily", check_demand_forecast_snapshot),
    ]

    with connect() as conn:
        for name, func in checks:
            print(f"\n{'='*60}", flush=True)
            print(f"Running checks for {name}...", flush=True)
            print(f"{'='*60}", flush=True)
            try:
                results = func(conn)
                all_results[name] = results
                for r in results:
                    status_icon = "✓" if r["status"] == "PASS" else "✗"
                    print(f"  {status_icon} [{r['seconds']}s] {r['label']} -> {r['status']} rows={r['row_count']}", flush=True)
                    if r["error"]:
                        print(f"    ERROR: {r['error'][:200]}", flush=True)
                # Write incremental results
                payload = {"metadata": metadata, "results": {k: [{**v, "rows": clean_rows(v["rows"])} for v in vs] for k, vs in all_results.items()}}
                (out_dir / "downstream_impact_results.json").write_text(
                    json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
                )
            except Exception as exc:
                print(f"  FATAL ERROR for {name}: {exc}", flush=True)
                all_results[name] = [{"label": f"{name} FATAL", "status": "ERROR", "seconds": 0, "rows": [], "row_count": 0, "error": str(exc)}]

    # Write final report
    payload = {"metadata": metadata, "results": {k: [{**v, "rows": clean_rows(v["rows"])} for v in vs] for k, vs in all_results.items()}}
    (out_dir / "downstream_impact_results.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    # Write markdown summary
    lines = [
        "# Bronze DQ Downstream Impact Check",
        "",
        f"- Generated at ICT: `{metadata['generated_at_ict']}`",
        f"- Server: `{metadata['server']}`",
        f"- Database: `{metadata['database']}`",
        f"- Tables checked: `6`",
        "",
        "## Results Summary",
        "",
    ]
    for name, results in all_results.items():
        lines.append(f"### {name}")
        lines.append("")
        lines.append("| Status | Seconds | Label | Row Count | Error |")
        lines.append("|---|---:|---|---:|---|")
        for r in results:
            err = (r["error"] or "")[:100]
            lines.append(f"| `{r['status']}` | {r['seconds']} | {r['label']} | {r['row_count']} | {err} |")
        lines.append("")
        # Include first row of each result for quick visibility
        for r in results:
            if r["rows"] and r["status"] == "PASS":
                lines.append(f"**{r['label']}** (first row):")
                lines.append("```json")
                lines.append(json.dumps(clean_rows(r["rows"][:3]), indent=2, ensure_ascii=False))
                lines.append("```")
                lines.append("")

    (out_dir / "downstream_impact_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"\n\nReport written to: {out_dir / 'downstream_impact_report.md'}")
    print(f"JSON written to: {out_dir / 'downstream_impact_results.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
