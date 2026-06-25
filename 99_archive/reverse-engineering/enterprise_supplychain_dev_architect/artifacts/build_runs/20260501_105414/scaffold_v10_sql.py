#!/usr/bin/env python3
"""Create the initial v10 SQL scaffold in the new Supply Chain Warehouses.

This script is additive and idempotent:
- Creates schemas/tables/views only when they do not already exist.
- Seeds metadata rows only when the target key is missing.
- Does not drop, truncate, overwrite, or load business data.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import struct
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
PROCESSING_DB = "SupplyChain_Processing_Warehouse"
GOLD_DB = "SupplyChain_Gold_Warehouse"
SOURCE_ROOT = Path("Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155")


PROCESSING_SCHEMAS = [
    "Meta",
    "Staging",
    "ReferenceMaster",
    "SalesHistory",
    "ForecastHistory",
    "OpenOrderHistory",
]
GOLD_SCHEMAS = ["ForecastAccuracy"]


EDW_EXIT_STATUS = {
    "brz_saleshistory_afi__invoicedetail": "ExitCandidate",
    "brz_saleshistory_afi__invoiceheader": "NotReady",
    "brz_supplychain_enh_1__demandforecastsnapshotdaily": "NotReady",
    "ref_product": "ExitCandidate",
}

STAGING_SOURCE_TABLE = {
    "brz_saleshistory_afi__invoicedetail": "brz_saleshistory_afi__invoicedetail_edw",
    "brz_saleshistory_afi__invoiceheader": "brz_saleshistory_afi__invoiceheader_edw",
    "brz_supplychain_enh_1__demandforecastsnapshotdaily": "brz_supplychain_enh_1__demandforecastsnapshotdaily_edw",
    "ref_product": "ref_product_edw",
}

LEGACY_DATAFLOW_BRIDGE = {
    "brz_saleshistory_afi__invoicedetail": {
        "dataflow": "df_brz_SalesHistory_AFI_InvoiceDetail",
        "lakehouse_table": "SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2",
    },
    "brz_saleshistory_afi__invoiceheader": {
        "dataflow": "df_brz_SalesHistory_AFI_InvoiceHeader",
        "lakehouse_table": "SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2",
    },
    "brz_supplychain_enh_1__demandforecastsnapshotdaily": {
        "dataflow": "df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1",
        "lakehouse_table": "SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2",
    },
    "ref_product": {
        "dataflow": "df_ref_product",
        "lakehouse_table": "SupplyChain_Lakehouse.dbo.ref_product_ver2",
    },
}

PHYSICAL_MAP = {
    "brz_saleshistory_afi__invoicedetail": ("Staging", "InvoiceDetailEdw"),
    "brz_saleshistory_afi__invoiceheader": ("Staging", "InvoiceHeaderEdw"),
    "brz_supplychain_enh_1__demandforecastsnapshotdaily": ("Staging", "DemandForecastSnapshotDailyEdw"),
    "ref_product": ("Staging", "ProductEdw"),
    "ref_calendar": ("ReferenceMaster", "Calendar"),
    "ref_customer_account": ("ReferenceMaster", "CustomerAccount"),
    "ref_customer_account_group": ("ReferenceMaster", "CustomerAccountGroup"),
    "ref_customer_grouping": ("ReferenceMaster", "CustomerGrouping"),
    "ref_customer_shipping_location": ("ReferenceMaster", "CustomerShippingLocation"),
    "ref_forecast_cycle": ("ReferenceMaster", "ForecastCycle"),
    "ref_forecast_horizon": ("ReferenceMaster", "ForecastHorizon"),
    "ref_item_master": ("ReferenceMaster", "ItemMaster"),
    "ref_order_type": ("ReferenceMaster", "OrderType"),
    "ref_warehouse": ("ReferenceMaster", "Warehouse"),
    "slv_actual_demand_monthly": ("SalesHistory", "ActualDemandMonthly"),
    "slv_actual_demand_weekly": ("SalesHistory", "ActualDemandWeekly"),
    "slv_invoice_detail_line_level": ("SalesHistory", "InvoiceDetailLineLevel"),
    "slv_invoice_weekly": ("SalesHistory", "InvoiceWeekly"),
    "slv_forecast_demand_monthly": ("ForecastHistory", "ForecastDemandMonthly"),
    "slv_naive_forecast_monthly": ("ForecastHistory", "NaiveForecastMonthly"),
    "slv_open_order_line_level": ("OpenOrderHistory", "OpenOrderLineLevel"),
    "slv_open_order_monthly": ("OpenOrderHistory", "OpenOrderMonthly"),
    "gld_fact_flat_forecast_actual": ("ForecastAccuracy", "FactForecastActual"),
    "gld_fact_forecast_kpi": ("ForecastAccuracy", "FactForecastKpi"),
}

EMPTY_TABLE_MAP = {
    ("bronze", "brz_saleshistory_afi__invoicedetail_edw"): (PROCESSING_DB, "Staging", "InvoiceDetailEdw"),
    ("bronze", "brz_saleshistory_afi__invoiceheader_edw"): (PROCESSING_DB, "Staging", "InvoiceHeaderEdw"),
    ("bronze", "brz_supplychain_enh_1__demandforecastsnapshotdaily_edw"): (
        PROCESSING_DB,
        "Staging",
        "DemandForecastSnapshotDailyEdw",
    ),
    ("bronze", "ref_product_edw"): (PROCESSING_DB, "Staging", "ProductEdw"),
    ("silver", "slv_actual_demand_monthly"): (PROCESSING_DB, "SalesHistory", "ActualDemandMonthly"),
    ("silver", "slv_actual_demand_weekly"): (PROCESSING_DB, "SalesHistory", "ActualDemandWeekly"),
    ("silver", "slv_invoice_detail_line_level"): (PROCESSING_DB, "SalesHistory", "InvoiceDetailLineLevel"),
    ("silver", "slv_invoice_weekly"): (PROCESSING_DB, "SalesHistory", "InvoiceWeekly"),
    ("silver", "slv_forecast_demand_monthly"): (PROCESSING_DB, "ForecastHistory", "ForecastDemandMonthly"),
    ("silver", "slv_naive_forecast_monthly"): (PROCESSING_DB, "ForecastHistory", "NaiveForecastMonthly"),
    ("silver", "slv_open_order_line_level"): (PROCESSING_DB, "OpenOrderHistory", "OpenOrderLineLevel"),
    ("silver", "slv_open_order_monthly"): (PROCESSING_DB, "OpenOrderHistory", "OpenOrderMonthly"),
    ("gold", "gld_fact_flat_forecast_actual"): (GOLD_DB, "ForecastAccuracy", "FactForecastActual"),
    ("gold", "gld_fact_forecast_kpi"): (GOLD_DB, "ForecastAccuracy", "FactForecastKpi"),
}


def quote_name(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def q(schema: str, table: str) -> str:
    return f"{quote_name(schema)}.{quote_name(table)}"


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")


def get_access_token() -> bytes:
    raw = subprocess.run(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--output",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    token = json.loads(raw.stdout)["accessToken"].encode("UTF-16-LE")
    return struct.pack(f"<I{len(token)}s", len(token), token)


def connect(database: str, attempts: int = 18) -> pyodbc.Connection:
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            token_struct = get_access_token()
            return pyodbc.connect(
                "DRIVER={ODBC Driver 18 for SQL Server};"
                f"SERVER={SERVER};"
                f"DATABASE={database};"
                "Encrypt=yes;"
                "TrustServerCertificate=no;",
                attrs_before={1256: token_struct},
                timeout=30,
                autocommit=True,
            )
        except Exception as exc:  # noqa: BLE001 - retry provisioning lag.
            last_error = exc
            time.sleep(10)
    raise RuntimeError(f"Could not connect to {database}: {last_error}")


def execute(cur: pyodbc.Cursor, sql: str, params: tuple[Any, ...] = ()) -> None:
    cur.execute(sql, params)


def scalar(cur: pyodbc.Cursor, sql: str, params: tuple[Any, ...] = ()) -> Any:
    cur.execute(sql, params)
    return cur.fetchone()[0]


def create_schema(cur: pyodbc.Cursor, schema: str) -> None:
    execute(
        cur,
        f"""
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '{schema}')
            EXEC('CREATE SCHEMA {quote_name(schema)}');
        """,
    )


def create_table_if_missing(cur: pyodbc.Cursor, schema: str, table: str, columns: str) -> bool:
    exists = scalar(
        cur,
        """
        SELECT COUNT(*)
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = ? AND t.name = ?;
        """,
        (schema, table),
    )
    if exists:
        return False
    execute(cur, f"CREATE TABLE {q(schema, table)} ({columns});")
    return True


def create_view_if_missing(cur: pyodbc.Cursor, schema: str, view: str, select_sql: str) -> bool:
    exists = scalar(
        cur,
        """
        SELECT COUNT(*)
        FROM sys.views v
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE s.name = ? AND v.name = ?;
        """,
        (schema, view),
    )
    if exists:
        return False
    execute(cur, f"CREATE VIEW {q(schema, view)} AS\n{select_sql}")
    return True


def create_meta_tables(cur: pyodbc.Cursor) -> list[str]:
    created = []
    definitions = {
        "AssetRegistryV10": """
            asset_id VARCHAR(128) NOT NULL,
            legacy_target_schema VARCHAR(128) NULL,
            legacy_target_table VARCHAR(256) NULL,
            legacy_layer VARCHAR(40) NULL,
            legacy_view_name VARCHAR(512) NULL,
            legacy_sp_name VARCHAR(256) NULL,
            canonical_layer VARCHAR(80) NULL,
            physical_workspace VARCHAR(256) NULL,
            physical_item VARCHAR(256) NULL,
            physical_schema VARCHAR(128) NULL,
            physical_object VARCHAR(256) NULL,
            access_mode VARCHAR(80) NULL,
            domain_group VARCHAR(128) NULL,
            project VARCHAR(128) NULL,
            frequency VARCHAR(50) NULL,
            cron_expression VARCHAR(128) NULL,
            scheduled_hour INT NULL,
            next_run_time DATETIME2(6) NULL,
            load_type VARCHAR(80) NULL,
            primary_key VARCHAR(1000) NULL,
            watermark_column VARCHAR(256) NULL,
            depends_on VARCHAR(4000) NULL,
            source_objects VARCHAR(4000) NULL,
            source_feed_type VARCHAR(80) NULL,
            edw_exit_status VARCHAR(80) NULL,
            is_enterprise_reusable BIT NULL,
            staging_reason VARCHAR(1000) NULL,
            source_contract_status VARCHAR(80) NULL,
            approval_status VARCHAR(80) NULL,
            owner_name VARCHAR(256) NULL,
            is_active BIT NULL,
            last_load_date DATETIME2(6) NULL,
            last_watermark_value VARCHAR(1000) NULL,
            rows_loaded BIGINT NULL,
            date_key VARCHAR(128) NULL,
            date_range_days INT NULL,
            created_at_utc DATETIME2(6) NULL,
            updated_at_utc DATETIME2(6) NULL
        """,
        "SourceFeed": """
            source_feed_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            source_name VARCHAR(512) NULL,
            source_workspace VARCHAR(256) NULL,
            source_item VARCHAR(256) NULL,
            source_schema VARCHAR(256) NULL,
            source_object VARCHAR(256) NULL,
            feed_type VARCHAR(80) NULL,
            is_temporary BIT NULL,
            exit_status VARCHAR(80) NULL,
            notes VARCHAR(2000) NULL,
            is_active BIT NULL,
            created_at_utc DATETIME2(6) NULL
        """,
        "AssetAccessPolicy": """
            policy_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            access_mode VARCHAR(80) NULL,
            requires_staging BIT NULL,
            requires_contract_validation BIT NULL,
            requires_reconciliation BIT NULL,
            requires_owner_approval BIT NULL,
            notes VARCHAR(2000) NULL,
            is_active BIT NULL
        """,
        "ObjectClassification": """
            asset_id VARCHAR(128) NOT NULL,
            legacy_layer VARCHAR(40) NULL,
            canonical_layer VARCHAR(80) NULL,
            classification VARCHAR(256) NULL,
            bob_alignment_status VARCHAR(80) NULL,
            notes VARCHAR(2000) NULL
        """,
        "SourceContract": """
            contract_id INT NULL,
            target_table VARCHAR(256) NULL,
            source_object VARCHAR(512) NULL,
            column_name VARCHAR(256) NULL,
            expected_data_type VARCHAR(128) NULL,
            is_nullable BIT NULL,
            is_active BIT NULL,
            created_date DATETIME2(6) NULL,
            last_validated DATETIME2(6) NULL,
            validation_status VARCHAR(80) NULL
        """,
        "SourceContractRun": """
            contract_run_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            run_id VARCHAR(128) NULL,
            validation_status VARCHAR(80) NULL,
            checked_at_utc DATETIME2(6) NULL,
            error_message VARCHAR(4000) NULL
        """,
        "DQRule": """
            source_row_number INT NULL,
            rule_id INT NULL,
            rule_name VARCHAR(512) NULL,
            target_schema VARCHAR(128) NULL,
            target_table VARCHAR(256) NULL,
            check_type VARCHAR(80) NULL,
            column_name VARCHAR(256) NULL,
            severity VARCHAR(80) NULL,
            threshold VARCHAR(128) NULL,
            params VARCHAR(4000) NULL,
            is_active BIT NULL,
            layer VARCHAR(40) NULL
        """,
        "DQGateRun": """
            dq_gate_run_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            run_id VARCHAR(128) NULL,
            gate_name VARCHAR(128) NULL,
            status VARCHAR(80) NULL,
            checked_at_utc DATETIME2(6) NULL,
            failed_rule_count INT NULL,
            error_message VARCHAR(4000) NULL
        """,
        "ReconciliationRule": """
            rule_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            source_object VARCHAR(512) NULL,
            target_object VARCHAR(512) NULL,
            reconciliation_type VARCHAR(80) NULL,
            tolerance_value DECIMAL(18,4) NULL,
            severity VARCHAR(80) NULL,
            is_active BIT NULL
        """,
        "ReconciliationResult": """
            result_id VARCHAR(128) NOT NULL,
            rule_id VARCHAR(128) NULL,
            run_id VARCHAR(128) NULL,
            status VARCHAR(80) NULL,
            source_value DECIMAL(38,6) NULL,
            target_value DECIMAL(38,6) NULL,
            variance_value DECIMAL(38,6) NULL,
            checked_at_utc DATETIME2(6) NULL,
            error_message VARCHAR(4000) NULL
        """,
        "LineageEdge": """
            edge_id VARCHAR(128) NOT NULL,
            source_asset VARCHAR(512) NULL,
            target_asset VARCHAR(512) NULL,
            edge_type VARCHAR(80) NULL,
            transform_type VARCHAR(80) NULL,
            is_synthetic BIT NULL,
            created_at_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
        "RunLog": """
            run_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            object_name VARCHAR(512) NULL,
            layer_name VARCHAR(80) NULL,
            status VARCHAR(80) NULL,
            start_time_utc DATETIME2(6) NULL,
            end_time_utc DATETIME2(6) NULL,
            start_time_cst DATETIME2(6) NULL,
            end_time_cst DATETIME2(6) NULL,
            rows_loaded BIGINT NULL,
            error_message VARCHAR(4000) NULL,
            load_type VARCHAR(80) NULL
        """,
        "PipelineRunLog": """
            pipeline_run_id VARCHAR(128) NOT NULL,
            pipeline_name VARCHAR(256) NULL,
            project VARCHAR(128) NULL,
            status VARCHAR(80) NULL,
            start_time_utc DATETIME2(6) NULL,
            end_time_utc DATETIME2(6) NULL,
            trigger_type VARCHAR(80) NULL,
            error_message VARCHAR(4000) NULL
        """,
        "SilverDagWaveRuntime": """
            runtime_id VARCHAR(128) NOT NULL,
            project VARCHAR(128) NULL,
            asset_id VARCHAR(128) NULL,
            physical_schema VARCHAR(128) NULL,
            physical_object VARCHAR(256) NULL,
            wave_number INT NULL,
            dependency_count INT NULL,
            is_active BIT NULL,
            computed_at_utc DATETIME2(6) NULL
        """,
        "ApprovalLog": """
            approval_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            approver_name VARCHAR(256) NULL,
            approval_status VARCHAR(80) NULL,
            approval_scope VARCHAR(256) NULL,
            approved_at_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
        "DeploymentChecklist": """
            checklist_id VARCHAR(128) NOT NULL,
            phase_name VARCHAR(256) NULL,
            check_name VARCHAR(512) NULL,
            status VARCHAR(80) NULL,
            owner_name VARCHAR(256) NULL,
            checked_at_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
        "SecurityPolicy": """
            policy_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            security_classification VARCHAR(128) NULL,
            workspace_role VARCHAR(128) NULL,
            sql_grant_pattern VARCHAR(512) NULL,
            semantic_rls_policy VARCHAR(512) NULL,
            is_active BIT NULL,
            notes VARCHAR(2000) NULL
        """,
        "SemanticModelContract": """
            contract_id VARCHAR(128) NOT NULL,
            gold_asset_id VARCHAR(128) NULL,
            semantic_model_name VARCHAR(256) NULL,
            source_mode VARCHAR(80) NULL,
            direct_lake_required BIT NULL,
            fallback_allowed BIT NULL,
            validation_status VARCHAR(80) NULL,
            last_validated_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
        "PerformanceBaseline": """
            baseline_id VARCHAR(128) NOT NULL,
            asset_id VARCHAR(128) NULL,
            metric_name VARCHAR(128) NULL,
            metric_value DECIMAL(38,6) NULL,
            captured_at_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
        "PipelineCostLog": """
            cost_log_id VARCHAR(128) NOT NULL,
            pipeline_run_id VARCHAR(128) NULL,
            item_name VARCHAR(256) NULL,
            capacity_id VARCHAR(128) NULL,
            duration_seconds INT NULL,
            estimated_cu_seconds DECIMAL(38,6) NULL,
            captured_at_utc DATETIME2(6) NULL,
            notes VARCHAR(2000) NULL
        """,
    }
    for table, columns in definitions.items():
        if create_table_if_missing(cur, "Meta", table, columns):
            created.append(f"Meta.{table}")
    return created


def normalize_datetime(value: str) -> str | None:
    return value if value else None


def nullable_int(value: str) -> int | None:
    if value in ("", None):
        return None
    return int(float(value))


def nullable_bit(value: str) -> int | None:
    if value in ("", None):
        return None
    return 1 if str(value).lower() in {"1", "true", "yes"} else 0


def json_sources(value: str) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return [str(item) for item in parsed]
    except json.JSONDecodeError:
        return []
    return []


def infer_domain_group(row: dict[str, str]) -> str:
    table = row["target_table"]
    layer = row["layer"]
    if table in STAGING_SOURCE_TABLE:
        return "LegacyDataflowBridge"
    if layer == "BRZ":
        return "LogicalBronze"
    if layer == "REF":
        return "ReferenceMaster"
    if table in {"slv_forecast_demand_monthly", "slv_naive_forecast_monthly"}:
        return "ForecastHistory"
    if table in {"slv_open_order_line_level", "slv_open_order_monthly"}:
        return "OpenOrderHistory"
    if layer == "SLV":
        return "SalesHistory"
    if layer == "GLD":
        return "ForecastAccuracy"
    return "SupplyChain"


def infer_asset(row: dict[str, str]) -> dict[str, Any]:
    table = row["target_table"]
    layer = row["layer"]
    schema = row["target_schema"]
    physical_schema, physical_object = PHYSICAL_MAP.get(table, (schema, table))

    canonical_layer = "LogicalBronze"
    access_mode = "DirectShortcut"
    physical_item = "Enterprise_Lakehouse"
    physical_workspace = "Enterprise SupplyChain-Dev"
    approval_status = "PendingValidation"
    source_feed_type = "EnterpriseLakehouseShortcut"
    edw_exit_status = None
    staging_reason = None
    is_enterprise_reusable = 0

    if table in STAGING_SOURCE_TABLE:
        canonical_layer = "Staging"
        access_mode = "EDWSupplement"
        physical_item = PROCESSING_DB
        source_feed_type = "LegacyDataflowBridge"
        edw_exit_status = EDW_EXIT_STATUS.get(table)
        staging_reason = "Temporary EDW/Dataflow supplement retained until Enterprise_Lakehouse coverage, grain, SLA, performance, dual-read validation, and Bob/Rakesh approval pass."
        approval_status = "NeedsExitApproval"
    elif layer == "REF":
        canonical_layer = "ReferenceMaster"
        access_mode = "DirectShortcut"
        physical_item = PROCESSING_DB
        source_feed_type = "EnterpriseLakehouseShortcut"
        approval_status = "NeedsOwnerDecision"
        is_enterprise_reusable = 1
    elif layer == "SLV":
        canonical_layer = "DomainSilver"
        access_mode = "WarehouseTransform"
        physical_item = PROCESSING_DB
        source_feed_type = "WarehouseTransform"
        approval_status = "DomainOwned"
    elif layer == "GLD":
        canonical_layer = "Gold"
        access_mode = "GoldPublish"
        physical_workspace = "Enterprise SupplyChain-Dev"
        physical_item = GOLD_DB
        source_feed_type = "GoldPublish"
        approval_status = "PendingSemanticValidation"

    return {
        "asset_id": f"{schema}.{table}",
        "legacy_target_schema": schema,
        "legacy_target_table": table,
        "legacy_layer": layer,
        "legacy_view_name": row["view_name"],
        "legacy_sp_name": row["sp_name"],
        "canonical_layer": canonical_layer,
        "physical_workspace": physical_workspace,
        "physical_item": physical_item,
        "physical_schema": physical_schema,
        "physical_object": physical_object,
        "access_mode": access_mode,
        "domain_group": infer_domain_group(row),
        "project": row["project"],
        "frequency": row["frequency"],
        "cron_expression": row["cron_expression"],
        "scheduled_hour": nullable_int(row["scheduled_hour"]),
        "next_run_time": normalize_datetime(row["next_run_time"]),
        "load_type": row["load_type"],
        "primary_key": row["primary_key"],
        "watermark_column": row["watermark_column"],
        "depends_on": row["depends_on"],
        "source_objects": row["source_objects"],
        "source_feed_type": source_feed_type,
        "edw_exit_status": edw_exit_status,
        "is_enterprise_reusable": is_enterprise_reusable,
        "staging_reason": staging_reason,
        "source_contract_status": "PendingValidation",
        "approval_status": approval_status,
        "owner_name": None,
        "is_active": nullable_bit(row["is_active"]),
        "last_load_date": normalize_datetime(row["last_load_date"]),
        "last_watermark_value": row["last_watermark_value"],
        "rows_loaded": nullable_int(row["rows_loaded"]),
        "date_key": row["date_key"],
        "date_range_days": nullable_int(row["date_range_days"]),
        "created_at_utc": now_utc(),
        "updated_at_utc": now_utc(),
    }


def insert_if_missing(cur: pyodbc.Cursor, table: str, key_col: str, key: Any, row: dict[str, Any]) -> bool:
    if scalar(cur, f"SELECT COUNT(*) FROM {table} WHERE {quote_name(key_col)} = ?;", (key,)):
        return False
    cols = list(row)
    placeholders = ",".join("?" for _ in cols)
    col_sql = ",".join(quote_name(col) for col in cols)
    execute(cur, f"INSERT INTO {table} ({col_sql}) VALUES ({placeholders});", tuple(row[col] for col in cols))
    return True


def seed_registry(cur: pyodbc.Cursor) -> dict[str, int]:
    path = SOURCE_ROOT / "sql" / "06_sp_registry.csv"
    inserted = 0
    classifications = 0
    policies = 0
    source_feeds = 0
    lineage_edges = 0
    with path.open(newline="", encoding="utf-8-sig") as f:
        for raw in csv.DictReader(f):
            asset = infer_asset(raw)
            if insert_if_missing(cur, "Meta.AssetRegistryV10", "asset_id", asset["asset_id"], asset):
                inserted += 1

            classification = {
                "asset_id": asset["asset_id"],
                "legacy_layer": asset["legacy_layer"],
                "canonical_layer": asset["canonical_layer"],
                "classification": f"{asset['canonical_layer']} / {asset['access_mode']}",
                "bob_alignment_status": "AlignedWithHybridMedallion",
                "notes": "Seeded from v9 clone and v10 object classification.",
            }
            if insert_if_missing(cur, "Meta.ObjectClassification", "asset_id", asset["asset_id"], classification):
                classifications += 1

            policy = {
                "policy_id": f"policy::{asset['asset_id']}",
                "asset_id": asset["asset_id"],
                "access_mode": asset["access_mode"],
                "requires_staging": 1 if asset["access_mode"] in {"EDWSupplement", "StageRequired"} else 0,
                "requires_contract_validation": 1 if asset["canonical_layer"] in {"LogicalBronze", "Staging", "ReferenceMaster"} else 0,
                "requires_reconciliation": 1 if asset["canonical_layer"] in {"Staging", "DomainSilver", "Gold"} else 0,
                "requires_owner_approval": 1 if asset["approval_status"] in {"NeedsOwnerDecision", "NeedsExitApproval"} else 0,
                "notes": "Initial v10 access policy scaffold.",
                "is_active": asset["is_active"],
            }
            if insert_if_missing(cur, "Meta.AssetAccessPolicy", "policy_id", policy["policy_id"], policy):
                policies += 1

            sources = json_sources(raw["source_objects"])
            for idx, source in enumerate(sources, start=1):
                feed_type = asset["source_feed_type"]
                source_name = source
                notes = "Source from v9 registry."
                if raw["target_table"] in LEGACY_DATAFLOW_BRIDGE:
                    bridge = LEGACY_DATAFLOW_BRIDGE[raw["target_table"]]
                    feed_type = "LegacyDataflowBridge"
                    source_name = bridge["lakehouse_table"]
                    notes = f"Temporary feed loaded by {bridge['dataflow']}; keep until Enterprise_Lakehouse is complete."
                feed = {
                    "source_feed_id": f"feed::{asset['asset_id']}::{idx}",
                    "asset_id": asset["asset_id"],
                    "source_name": source_name,
                    "source_workspace": "Enterprise SupplyChain-Dev",
                    "source_item": "SupplyChain_Lakehouse" if feed_type == "LegacyDataflowBridge" else "Enterprise_Lakehouse",
                    "source_schema": parse_source_part(source_name, 1),
                    "source_object": parse_source_part(source_name, 2),
                    "feed_type": feed_type,
                    "is_temporary": 1 if feed_type == "LegacyDataflowBridge" else 0,
                    "exit_status": asset["edw_exit_status"],
                    "notes": notes,
                    "is_active": 1,
                    "created_at_utc": now_utc(),
                }
                if insert_if_missing(cur, "Meta.SourceFeed", "source_feed_id", feed["source_feed_id"], feed):
                    source_feeds += 1

                edge = {
                    "edge_id": f"edge::source::{asset['asset_id']}::{idx}",
                    "source_asset": source_name,
                    "target_asset": asset["asset_id"],
                    "edge_type": "LegacyDataflowBridge" if feed_type == "LegacyDataflowBridge" else "SourceRead",
                    "transform_type": asset["access_mode"],
                    "is_synthetic": 1 if feed_type == "LegacyDataflowBridge" else 0,
                    "created_at_utc": now_utc(),
                    "notes": notes,
                }
                if insert_if_missing(cur, "Meta.LineageEdge", "edge_id", edge["edge_id"], edge):
                    lineage_edges += 1

            for idx, dependency in enumerate(json_sources(raw["depends_on"]), start=1):
                edge = {
                    "edge_id": f"edge::dependency::{asset['asset_id']}::{idx}",
                    "source_asset": dependency,
                    "target_asset": asset["asset_id"],
                    "edge_type": "Dependency",
                    "transform_type": asset["access_mode"],
                    "is_synthetic": 0,
                    "created_at_utc": now_utc(),
                    "notes": "Dependency edge seeded from v9 depends_on.",
                }
                if insert_if_missing(cur, "Meta.LineageEdge", "edge_id", edge["edge_id"], edge):
                    lineage_edges += 1

    return {
        "asset_registry_inserted": inserted,
        "classifications_inserted": classifications,
        "policies_inserted": policies,
        "source_feeds_inserted": source_feeds,
        "lineage_edges_inserted": lineage_edges,
    }


def parse_source_part(source: str, index: int) -> str | None:
    parts = source.split(".")
    if len(parts) >= 3:
        return parts[index]
    return None


def seed_source_contracts(cur: pyodbc.Cursor) -> int:
    path = SOURCE_ROOT / "sql" / "21_schema_contracts.csv"
    inserted = 0
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            key = int(row["contract_id"])
            if scalar(cur, "SELECT COUNT(*) FROM Meta.SourceContract WHERE contract_id = ?;", (key,)):
                continue
            execute(
                cur,
                """
                INSERT INTO Meta.SourceContract
                (contract_id, target_table, source_object, column_name, expected_data_type,
                 is_nullable, is_active, created_date, last_validated, validation_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                (
                    key,
                    row["target_table"],
                    row["source_object"],
                    row["column_name"],
                    row["expected_data_type"],
                    nullable_bit(row["is_nullable"]),
                    nullable_bit(row["is_active"]),
                    normalize_datetime(row["created_date"]),
                    normalize_datetime(row["last_validated"]),
                    row["validation_status"],
                ),
            )
            inserted += 1
    return inserted


def seed_dq_rules(cur: pyodbc.Cursor) -> int:
    path = SOURCE_ROOT / "sql" / "meta_tables" / "dq_rules.csv"
    inserted = 0
    with path.open(newline="", encoding="utf-8-sig") as f:
        for source_row_number, row in enumerate(csv.DictReader(f), start=1):
            key = int(row["rule_id"])
            if scalar(
                cur,
                """
                SELECT COUNT(*)
                FROM Meta.DQRule
                WHERE source_row_number = ?;
                """,
                (source_row_number,),
            ):
                continue
            if scalar(
                cur,
                """
                SELECT COUNT(*)
                FROM Meta.DQRule
                WHERE source_row_number IS NULL
                  AND rule_id = ?
                  AND rule_name = ?
                  AND target_schema = ?
                  AND target_table = ?
                  AND check_type = ?
                  AND column_name = ?
                  AND layer = ?;
                """,
                (
                    key,
                    row["rule_name"],
                    row["target_schema"],
                    row["target_table"],
                    row["check_type"],
                    row["column_name"],
                    row["layer"],
                ),
            ):
                execute(
                    cur,
                    """
                    UPDATE Meta.DQRule
                    SET source_row_number = ?
                    WHERE source_row_number IS NULL
                      AND rule_id = ?
                      AND rule_name = ?
                      AND target_schema = ?
                      AND target_table = ?
                      AND check_type = ?
                      AND column_name = ?
                      AND layer = ?;
                    """,
                    (source_row_number, *(
                        key,
                        row["rule_name"],
                        row["target_schema"],
                        row["target_table"],
                        row["check_type"],
                        row["column_name"],
                        row["layer"],
                    )),
                )
                continue
            execute(
                cur,
                """
                INSERT INTO Meta.DQRule
                (source_row_number, rule_id, rule_name, target_schema, target_table, check_type, column_name,
                 severity, threshold, params, is_active, layer)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                (
                    source_row_number,
                    key,
                    row["rule_name"],
                    row["target_schema"],
                    row["target_table"],
                    row["check_type"],
                    row["column_name"],
                    row["severity"],
                    row["threshold"],
                    row["params"],
                    nullable_bit(row["is_active"]),
                    row["layer"],
                ),
            )
            inserted += 1
    return inserted


def seed_semantic_contracts(cur: pyodbc.Cursor) -> int:
    rows = [
        {
            "contract_id": "semantic::ForecastAccuracy::FactForecastActual",
            "gold_asset_id": "gold.gld_fact_flat_forecast_actual",
            "semantic_model_name": "SupplyChain_Gold",
            "source_mode": "DirectLake",
            "direct_lake_required": 1,
            "fallback_allowed": 0,
            "validation_status": "Pending",
            "last_validated_utc": None,
            "notes": "Physical Gold table contract; validate Direct Lake behavior before report cutover.",
        },
        {
            "contract_id": "semantic::ForecastAccuracy::FactForecastKpi",
            "gold_asset_id": "gold.gld_fact_forecast_kpi",
            "semantic_model_name": "SupplyChain_Gold",
            "source_mode": "DirectLake",
            "direct_lake_required": 1,
            "fallback_allowed": 0,
            "validation_status": "Pending",
            "last_validated_utc": None,
            "notes": "Physical Gold table contract; validate Direct Lake behavior before report cutover.",
        },
    ]
    inserted = 0
    for row in rows:
        if insert_if_missing(cur, "Meta.SemanticModelContract", "contract_id", row["contract_id"], row):
            inserted += 1
    return inserted


def sql_type(col: dict[str, str]) -> str:
    data_type = col["data_type"].lower()
    if data_type in {"varchar", "char"}:
        length = col["character_maximum_length"] or "8000"
        if length == "-1":
            length = "8000"
        return f"VARCHAR({length})"
    if data_type in {"decimal", "numeric"}:
        precision = col["numeric_precision"] or "18"
        scale = col["numeric_scale"] or "0"
        return f"DECIMAL({precision},{scale})"
    if data_type == "datetime2":
        scale = col["datetime_precision"] or "6"
        return f"DATETIME2({scale})"
    if data_type in {"int", "bigint", "smallint", "tinyint", "bit", "date", "float", "real"}:
        return data_type.upper()
    raise ValueError(f"Unsupported data type from v9 clone: {data_type} for {col['table_schema']}.{col['table_name']}.{col['column_name']}")


def create_empty_physical_tables(processing_cur: pyodbc.Cursor, gold_cur: pyodbc.Cursor) -> dict[str, int]:
    columns_by_table: dict[tuple[str, str], list[dict[str, str]]] = {}
    path = SOURCE_ROOT / "sql" / "04_columns.csv"
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            key = (row["table_schema"], row["table_name"])
            if key in EMPTY_TABLE_MAP:
                columns_by_table.setdefault(key, []).append(row)

    created = 0
    skipped = 0
    for key, target in EMPTY_TABLE_MAP.items():
        target_db, target_schema, target_table = target
        cur = gold_cur if target_db == GOLD_DB else processing_cur
        source_cols = sorted(columns_by_table.get(key, []), key=lambda col: int(col["ordinal_position"]))
        if not source_cols:
            raise RuntimeError(f"No column metadata found for {key}")
        col_sql = ",\n".join(
            f"{quote_name(col['column_name'])} {sql_type(col)} {'NULL' if col['is_nullable'] == 'YES' else 'NOT NULL'}"
            for col in source_cols
        )
        if create_table_if_missing(cur, target_schema, target_table, col_sql):
            created += 1
        else:
            skipped += 1
    return {"empty_tables_created": created, "empty_tables_skipped_existing": skipped}


def create_views(cur: pyodbc.Cursor) -> list[str]:
    created = []
    registry_select = """
SELECT
    legacy_sp_name AS sp_name,
    legacy_view_name AS view_name,
    legacy_target_schema AS target_schema,
    legacy_target_table AS target_table,
    legacy_layer AS layer,
    load_type,
    frequency,
    scheduled_hour,
    CAST(NULL AS INT) AS execution_order,
    CAST(NULL AS VARCHAR(128)) AS parallel_group,
    depends_on,
    source_objects,
    watermark_column,
    primary_key,
    is_active,
    last_load_date,
    last_watermark_value,
    next_run_time,
    rows_loaded,
    project,
    date_key,
    date_range_days,
    cron_expression,
    canonical_layer,
    access_mode,
    physical_item,
    physical_schema,
    physical_object,
    approval_status,
    edw_exit_status
FROM Meta.AssetRegistryV10
"""
    if create_view_if_missing(cur, "Meta", "vw_RegistryCompat", registry_select):
        created.append("Meta.vw_RegistryCompat")

    access_select = """
SELECT
    asset_id,
    canonical_layer,
    access_mode,
    physical_item,
    physical_schema,
    physical_object,
    source_contract_status,
    approval_status,
    edw_exit_status,
    CASE
        WHEN access_mode = 'EDWSupplement' THEN 'Use Staging until exit validation and Bob/Rakesh approval pass'
        WHEN access_mode = 'DirectShortcut' THEN 'Read Enterprise_Lakehouse shortcut directly after source contract validation'
        WHEN access_mode = 'WarehouseTransform' THEN 'Run Warehouse-native Domain Silver transform'
        WHEN access_mode = 'GoldPublish' THEN 'Publish physical Gold table for Direct Lake serving'
        ELSE 'Review access policy'
    END AS access_decision
FROM Meta.AssetRegistryV10
WHERE is_active = 1
"""
    if create_view_if_missing(cur, "Meta", "vw_AccessDecision", access_select):
        created.append("Meta.vw_AccessDecision")

    dictionary_select = """
SELECT
    'EDW-Fabric' AS [ServerName],
    physical_item AS [DatabaseName],
    physical_schema AS [SchemaName],
    physical_object AS [TableName],
    'Table' AS [ObjectType],
    primary_key AS [PrimaryKey],
    CAST(NULL AS VARCHAR(500)) AS [AlternateKey],
    'Delta' AS [StorageType],
    CAST(NULL AS VARCHAR(750)) AS [RowSToreClusteredKey],
    CAST(NULL AS VARCHAR(500)) AS [AdditionalIndexes],
    CAST(NULL AS VARCHAR(500)) AS [DistributionKey],
    CAST(NULL AS VARCHAR(25)) AS [IndexType],
    project AS [SourceSystem],
    CAST(NULL AS VARCHAR(100)) AS [SourceServer],
    CAST(NULL AS VARCHAR(200)) AS [SourceDatabase],
    source_objects AS [SourceObject],
    CAST(NULL AS VARCHAR(100)) AS [SourceObjectAlias],
    source_feed_type AS [SourcePlatform],
    legacy_view_name AS [ReplicatedSource],
    'Fabric Pipeline' AS [ETLTool],
    legacy_sp_name AS [PackageName],
    CAST(NULL AS VARCHAR(400)) AS [TFSPath],
    CAST(NULL AS VARCHAR(100)) AS [JobName],
    CAST(NULL AS VARCHAR(50)) AS [JobServer],
    CASE frequency
        WHEN 'daily' THEN 24
        WHEN 'hourly' THEN 1
        WHEN 'weekly' THEN 168
        WHEN 'monthly' THEN 720
        ELSE 24
    END AS [RefreshRate],
    frequency AS [RefreshDescription],
    load_type AS [UpdateMethod],
    CAST(NULL AS VARCHAR(8000)) AS [ExtractQuery],
    CAST(NULL AS VARCHAR(8000)) AS [UpdateQuery],
    staging_reason AS [AdditionaNotes],
    CAST(NULL AS DECIMAL(12,0)) AS [InvalidCount],
    CAST(rows_loaded AS DECIMAL(12,0)) AS [RowCount],
    CAST(NULL AS DATETIME2(6)) AS [CreateDate],
    last_load_date AS [Modified],
    owner_name AS [CreatedBy],
    owner_name AS [ModifiedBy],
    last_load_date AS [LastAudit],
    CAST(NULL AS VARCHAR(500)) AS [ErrorMsg],
    CAST(NULL AS DATETIME2(6)) AS [CreatedDate],
    CAST(NULL AS DATETIME2(6)) AS [Created],
    CAST(NULL AS VARCHAR(15)) AS [SourceObjectType],
    CAST(NULL AS VARCHAR(200)) AS [PartitionKey],
    CAST(NULL AS INT) AS [ColumnStatsCount],
    CAST(NULL AS INT) AS [ColumnCount],
    CAST(NULL AS DATETIME2(6)) AS [ColumnStatsLastUpdated],
    CAST(NULL AS DECIMAL(12,0)) AS [DeletedRows],
    physical_workspace AS [DataLake],
    physical_item AS [DataLakeFolder],
    CAST(NULL AS VARCHAR(500)) AS [DataLakeFolderArchive],
    CAST(NULL AS INT) AS [ReplicatedSourceExpiryHours],
    CAST(NULL AS INT) AS [ReplicatedSourceArchiveExpiryHours],
    CASE WHEN access_mode IN ('EDWSupplement', 'StageRequired') THEN physical_schema ELSE NULL END AS [StageDataLakeFolder],
    last_load_date AS [LastBatchStartDate],
    CAST(NULL AS VARCHAR(500)) AS [LibraryList],
    date_key AS [DateKey],
    date_range_days AS [DateRangeDays],
    asset_id AS [OperationKey],
    CAST(NULL AS VARCHAR(8000)) AS [PII],
    CAST(NULL AS BIT) AS [ValidKeyValues],
    CAST(NULL AS VARCHAR(8000)) AS [SelectColumn],
    CAST(NULL AS VARCHAR(30)) AS [DataBricksClusterVersion],
    CAST(NULL AS VARCHAR(30)) AS [DataBricksNodeType],
    CAST(NULL AS VARCHAR(10)) AS [DataBricksClusterRange],
    canonical_layer AS [v9_Layer],
    CAST(NULL AS INT) AS [v9_ExecutionOrder],
    depends_on AS [v9_DependsOn],
    watermark_column AS [v9_WatermarkColumn],
    last_watermark_value AS [v9_LastWatermarkValue],
    is_active AS [v9_IsActive]
FROM Meta.AssetRegistryV10
"""
    if create_view_if_missing(cur, "Meta", "vw_TableDictionary", dictionary_select):
        created.append("Meta.vw_TableDictionary")
    return created


def verify(processing_cur: pyodbc.Cursor, gold_cur: pyodbc.Cursor) -> dict[str, Any]:
    counts = {}
    for table in [
        "AssetRegistryV10",
        "SourceFeed",
        "SourceContract",
        "DQRule",
        "LineageEdge",
        "SemanticModelContract",
    ]:
        counts[f"Meta.{table}"] = scalar(processing_cur, f"SELECT COUNT(*) FROM Meta.{table};")
    counts["Meta.vw_TableDictionary_columns"] = scalar(
        processing_cur,
        """
        SELECT COUNT(*)
        FROM sys.columns c
        JOIN sys.views v ON v.object_id = c.object_id
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE s.name = 'Meta' AND v.name = 'vw_TableDictionary';
        """,
    )
    counts["processing_empty_tables"] = scalar(
        processing_cur,
        """
        SELECT COUNT(*)
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name IN ('Staging','SalesHistory','ForecastHistory','OpenOrderHistory');
        """,
    )
    counts["gold_empty_tables"] = scalar(
        gold_cur,
        """
        SELECT COUNT(*)
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'ForecastAccuracy';
        """,
    )
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    output: dict[str, Any] = {"started_at_utc": now_utc()}
    processing = connect(PROCESSING_DB)
    gold = connect(GOLD_DB)
    pc = processing.cursor()
    gc = gold.cursor()

    for schema in PROCESSING_SCHEMAS:
        create_schema(pc, schema)
    for schema in GOLD_SCHEMAS:
        create_schema(gc, schema)

    output["created_meta_tables"] = create_meta_tables(pc)
    output["seed_registry"] = seed_registry(pc)
    output["source_contracts_inserted"] = seed_source_contracts(pc)
    output["dq_rules_inserted"] = seed_dq_rules(pc)
    output["semantic_contracts_inserted"] = seed_semantic_contracts(pc)
    output["empty_tables"] = create_empty_physical_tables(pc, gc)
    output["created_views"] = create_views(pc)
    output["verification_counts"] = verify(pc, gc)
    output["finished_at_utc"] = now_utc()

    Path(args.out).write_text(json.dumps(output, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(output["verification_counts"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
