#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import struct
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import pyodbc


ROOT = Path("/Users/MAC/Documents/20260413_Fabric_Refactor_Architect")
ARTIFACT_ROOT = ROOT / "01_docs/runbook/artifacts/20260622_phase1a_baseline"
PHASE1D_DIR = ARTIFACT_ROOT / "phase1d"
PHASE1E_DIR = ARTIFACT_ROOT / "phase1e"
PHASE1G_DIR = ARTIFACT_ROOT / "phase1g"

SERVER = (
    "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a."
    "datawarehouse.fabric.microsoft.com"
)
ETL_DB = "ETL_Framework"
PROCESSING_DB = "SupplyChain_Processing_Warehouse"
GOLD_DB = "SupplyChain_Gold_Warehouse"


@dataclass(frozen=True)
class SqlTarget:
    database: str
    schema: str
    object_name: str

    @property
    def asset_id(self) -> str:
        return f"{self.schema}.{self.object_name}"


def get_token_struct() -> bytes:
    token = subprocess.check_output(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--query",
            "accessToken",
            "-o",
            "tsv",
        ],
        text=True,
    ).strip()
    encoded = token.encode("utf-16-le")
    return struct.pack("<I", len(encoded)) + encoded


def connect(database: str) -> pyodbc.Connection:
    return pyodbc.connect(
        (
            "Driver={ODBC Driver 18 for SQL Server};"
            f"Server={SERVER};Database={database};"
            "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;"
        ),
        attrs_before={1256: get_token_struct()},
        autocommit=True,
    )


def rows_as_dicts(cur: pyodbc.Cursor) -> list[dict[str, object]]:
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def fetch_columns(conn: pyodbc.Connection, targets: list[SqlTarget]) -> dict[SqlTarget, list[dict[str, object]]]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT
            TABLE_SCHEMA,
            TABLE_NAME,
            COLUMN_NAME,
            DATA_TYPE,
            COALESCE(CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, DATETIME_PRECISION) AS LENGTH_OR_PRECISION,
            NUMERIC_SCALE,
            ORDINAL_POSITION
        FROM INFORMATION_SCHEMA.COLUMNS
        ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION
        """
    )
    all_rows = rows_as_dicts(cur)
    cur.close()

    grouped: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for row in all_rows:
        grouped[(str(row["TABLE_SCHEMA"]), str(row["TABLE_NAME"]))].append(row)

    results: dict[SqlTarget, list[dict[str, object]]] = {}
    for target in targets:
        results[target] = grouped.get((target.schema, target.object_name), [])
    return results


def quote_ident(name: str) -> str:
    return f"[{name}]"


def sql_type(col: dict[str, object]) -> str:
    dtype = str(col["DATA_TYPE"]).lower()
    length = col["LENGTH_OR_PRECISION"]
    scale = col["NUMERIC_SCALE"]

    if dtype in {"varchar", "nvarchar", "char", "nchar", "binary", "varbinary"}:
        if length in (-1, None):
            return f"{dtype}(max)"
        return f"{dtype}({int(length)})"
    if dtype in {"decimal", "numeric"}:
        precision = int(length or 18)
        numeric_scale = int(scale or 0)
        return f"{dtype}({precision},{numeric_scale})"
    if dtype in {"datetime2", "datetimeoffset", "time"} and length is not None:
        return f"{dtype}({int(length)})"
    return dtype


def load_manifest() -> list[dict[str, str]]:
    with (PHASE1D_DIR / "phase1d_manifest_v1.csv").open() as f:
        return list(csv.DictReader(f))


def load_dependency_validation() -> list[dict[str, str]]:
    with (PHASE1D_DIR / "phase1d_dependency_validation.csv").open() as f:
        return list(csv.DictReader(f))


def current_gold_targets() -> list[SqlTarget]:
    return [
        SqlTarget(GOLD_DB, "Shared_DW", "DimCalendar"),
        SqlTarget(GOLD_DB, "Shared_DW", "DimProduct"),
        SqlTarget(GOLD_DB, "Shared_DW", "DimWarehouse"),
        SqlTarget(GOLD_DB, "ForecastAccuracy_DW", "DimCustomerGrouping"),
        SqlTarget(GOLD_DB, "ForecastAccuracy_DW", "DimForecastHorizon"),
        SqlTarget(GOLD_DB, "ForecastAccuracy_DW", "FactForecastActual"),
        SqlTarget(GOLD_DB, "ForecastAccuracy_DW", "FactForecastKpi"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "DimVendor"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "InventoryClassificationQtyWeekly"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "InventoryHealthSubStatusWeekly"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "FactInventoryHealthSnapshot"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "FactInventoryHealthFutureWeekEnding"),
        SqlTarget(GOLD_DB, "InventoryHealth_DW", "ProjectedInventoryHealthSubStatus"),
    ]


def boolish(value: object) -> bool:
    return str(value).strip().lower() == "true"


def incremental_exec_command(database: str, schema: str, table: str) -> str:
    return (
        "EXEC DW_Developer.usp_IncrementalTableLoad "
        f"'{database}', '{schema}', '{table}', 'NULL'"
    )


def canonical_enterprise_etl_exec_command(row: dict[str, str]) -> str:
    asset_id = row["asset_id"]
    if asset_id in {
        "Staging.DemandForecastSnapshotDaily",
        "Staging_Wrk.DemandForecastSnapshotDaily",
    }:
        return incremental_exec_command(row["database_name"], row["schema_name"], row["object_name"])
    if asset_id in {
        "InventoryHistory_Enh.HoldingTransferSnapshotDaily",
        "InventoryHistory_Enh.ManufacturingOrderSnapshotDaily",
    }:
        return incremental_exec_command(row["database_name"], row["schema_name"], row["object_name"])
    return row["enterprise_etl_exec_command"]


def parse_dependencies(value: str) -> list[str]:
    raw = (value or "").strip()
    if not raw:
        return []
    if raw.startswith("[") and raw.endswith("]"):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = []
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
    return [part.strip().strip('"').strip("'") for part in raw.split(",") if part.strip()]


def canonicalize_dependency_refs(value: str) -> str:
    replacements = {
        "SalesHistory_Enh.v_InvoiceDetailLineLevel": "SalesHistory_Enh.InvoiceDetailLineLevel",
        "InventoryHistory_Enh.v_InventorySnapshotWeekly": "InventoryHistory_Enh.InventorySnapshotWeekly",
        "Staging_Wrk.DemandForecastSnapshotDaily": "Staging.DemandForecastSnapshotDaily",
    }
    updated = value or ""
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    return updated


def normalize_dependencies(manifest_rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    gold_replacements = {
        "InventoryHealth_DW.CogsRollingHelper": None,
        "InventoryHealth_DW.FactInventoryRiskForward": None,
    }

    extra_manifest_rows = {
        "InventoryHistory_Enh.PurchaseOrderSnapshotHistorical": {
            "run_sequence": "",
            "layer": "DomainSilver",
            "project": "inventory_health",
            "wave_number": "1",
            "database_name": PROCESSING_DB,
            "schema_name": "InventoryHistory_Enh",
            "object_name": "PurchaseOrderSnapshotHistorical",
            "asset_id": "InventoryHistory_Enh.PurchaseOrderSnapshotHistorical",
            "depends_on": "",
            "source_objects": '["SupplyChain_Lakehouse.dbo.purchaseordersnapshot"]',
            "enterprise_etl_exec_command": (
                "EXEC DW_Developer.usp_RefreshCuratedTableFromView "
                "'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'PurchaseOrderSnapshotHistorical'"
            ),
            "is_manual_run_enabled": "True",
            "load_type": "overwrite",
            "wave_found": "False",
        },
        "InventoryHealth_DW.InventoryClassificationQtyWeekly": {
            "run_sequence": "",
            "layer": "Gold",
            "project": "inventory_health",
            "wave_number": "",
            "database_name": GOLD_DB,
            "schema_name": "InventoryHealth_DW",
            "object_name": "InventoryClassificationQtyWeekly",
            "asset_id": "InventoryHealth_DW.InventoryClassificationQtyWeekly",
            "depends_on": "",
            "source_objects": "",
            "enterprise_etl_exec_command": (
                "EXEC DW_Developer.usp_RefreshCuratedTableFromView "
                "'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryClassificationQtyWeekly'"
            ),
            "is_manual_run_enabled": "True",
            "load_type": "overwrite",
            "wave_found": "False",
        },
        "InventoryHealth_DW.InventoryHealthSubStatusWeekly": {
            "run_sequence": "",
            "layer": "Gold",
            "project": "inventory_health",
            "wave_number": "",
            "database_name": GOLD_DB,
            "schema_name": "InventoryHealth_DW",
            "object_name": "InventoryHealthSubStatusWeekly",
            "asset_id": "InventoryHealth_DW.InventoryHealthSubStatusWeekly",
            "depends_on": "",
            "source_objects": "",
            "enterprise_etl_exec_command": (
                "EXEC DW_Developer.usp_RefreshCuratedTableFromView "
                "'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryHealthSubStatusWeekly'"
            ),
            "is_manual_run_enabled": "True",
            "load_type": "overwrite",
            "wave_found": "False",
        },
        "InventoryHealth_DW.FactInventoryHealthFutureWeekEnding": {
            "run_sequence": "",
            "layer": "Gold",
            "project": "inventory_health",
            "wave_number": "",
            "database_name": GOLD_DB,
            "schema_name": "InventoryHealth_DW",
            "object_name": "FactInventoryHealthFutureWeekEnding",
            "asset_id": "InventoryHealth_DW.FactInventoryHealthFutureWeekEnding",
            "depends_on": "Shared_DW.DimProduct,Shared_DW.DimCalendar",
            "source_objects": "",
            "enterprise_etl_exec_command": (
                "EXEC DW_Developer.usp_RefreshCuratedTableFromView "
                "'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'FactInventoryHealthFutureWeekEnding'"
            ),
            "is_manual_run_enabled": "True",
            "load_type": "overwrite",
            "wave_found": "False",
        },
        "InventoryHealth_DW.ProjectedInventoryHealthSubStatus": {
            "run_sequence": "",
            "layer": "Gold",
            "project": "inventory_health",
            "wave_number": "",
            "database_name": GOLD_DB,
            "schema_name": "InventoryHealth_DW",
            "object_name": "ProjectedInventoryHealthSubStatus",
            "asset_id": "InventoryHealth_DW.ProjectedInventoryHealthSubStatus",
            "depends_on": "InventoryHealth_DW.FactInventoryHealthFutureWeekEnding",
            "source_objects": "",
            "enterprise_etl_exec_command": (
                "EXEC DW_Developer.usp_RefreshCuratedTableFromView "
                "'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'ProjectedInventoryHealthSubStatus'"
            ),
            "is_manual_run_enabled": "True",
            "load_type": "overwrite",
            "wave_found": "False",
        },
    }

    drift_notes: list[dict[str, str]] = []
    output: list[dict[str, str]] = []
    for row in manifest_rows:
        asset_id = row["asset_id"]
        if asset_id in gold_replacements:
            drift_notes.append(
                {
                    "asset_id": asset_id,
                    "classification": "removed_from_live_gold_contract",
                    "reason": "not present in live Gold warehouse; stale active registry branch",
                }
            )
            continue

        new_row = dict(row)
        if asset_id == "Staging_Wrk.DemandForecastSnapshotDaily":
            new_row["schema_name"] = "Staging"
            new_row["asset_id"] = "Staging.DemandForecastSnapshotDaily"
            drift_notes.append(
                {
                    "asset_id": asset_id,
                    "classification": "enterprise_etl_naming_canonicalized",
                    "reason": "final target moved from Staging_Wrk to Staging; _Wrk source view remains Staging_Wrk.v_DemandForecastSnapshotDaily",
                }
            )
        new_row["enterprise_etl_exec_command"] = canonical_enterprise_etl_exec_command(new_row)
        new_row["depends_on"] = canonicalize_dependency_refs(new_row.get("depends_on", ""))
        new_row["source_objects"] = canonicalize_dependency_refs(new_row.get("source_objects", ""))
        if new_row["asset_id"] == "Staging.DemandForecastSnapshotDaily":
            new_row["source_objects"] = '["Staging_Wrk.v_DemandForecastSnapshotDaily"]'
        if asset_id == "InventoryHistory_Enh.HoldingTransferSnapshotDaily":
            new_row["depends_on"] = ""
            new_row["source_objects"] = '["InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily"]'
            drift_notes.append(
                {
                    "asset_id": asset_id,
                    "classification": "dependency_alias_drift",
                    "reason": "legacy depends_on InventoryHistory_Enh.HoldingTransfer is now inlined in source view",
                }
            )
        elif asset_id == "InventoryHistory_Enh.ManufacturingOrderSnapshotDaily":
            new_row["depends_on"] = ""
            new_row["source_objects"] = '["InventoryHistory_Enh_Wrk.v_ManufacturingOrderSnapshotDaily"]'
            drift_notes.append(
                {
                    "asset_id": asset_id,
                    "classification": "dependency_alias_drift",
                    "reason": "legacy depends_on InventoryHistory_Enh.ManufacturingOrder is now inlined in source view",
                }
            )
        elif asset_id == "InventoryHealth_DW.FactInventoryHealthSnapshot":
            new_row["depends_on"] = ",".join(
                [
                    "InventoryHistory_Enh.InventorySnapshotWeekly",
                    "InventoryHistory_Enh.PurchaseOrderSnapshotHistorical",
                    "InventoryHistory_Enh.ManufacturingOrderSnapshotDaily",
                    "InventoryHistory_Enh.HoldingTransferSnapshotDaily",
                    "InventoryHistory_Enh.AwdHelper",
                    "InventoryHistory_Enh.LastInvoiceWeekly",
                    "InventoryHistory_Enh.SafetyStockHelper",
                    "InventoryHealth_DW.InventoryClassificationQtyWeekly",
                    "InventoryHealth_DW.InventoryHealthSubStatusWeekly",
                    "Shared_DW.DimProduct",
                ]
            )
            new_row["source_objects"] = json.dumps(
                [
                    "Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL",
                    "Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA",
                    "InventoryHistory_Enh.InventorySnapshotWeekly",
                    "InventoryHistory_Enh.PurchaseOrderSnapshotHistorical",
                    "InventoryHistory_Enh.ManufacturingOrderSnapshotDaily",
                    "InventoryHistory_Enh.HoldingTransferSnapshotDaily",
                    "InventoryHistory_Enh.AwdHelper",
                    "InventoryHistory_Enh.LastInvoiceWeekly",
                    "InventoryHistory_Enh.SafetyStockHelper",
                    "InventoryHealth_DW.InventoryClassificationQtyWeekly",
                    "InventoryHealth_DW.InventoryHealthSubStatusWeekly",
                    "Shared_DW.DimProduct",
                ]
            )
            drift_notes.extend(
                [
                    {
                        "asset_id": asset_id,
                        "classification": "dependency_alias_drift",
                        "reason": "PurchaseOrderSnapshotDaily replaced by live PurchaseOrderSnapshotHistorical",
                    },
                    {
                        "asset_id": asset_id,
                        "classification": "dependency_alias_drift",
                        "reason": "LastInvoiceHelper replaced by live LastInvoiceWeekly",
                    },
                    {
                        "asset_id": asset_id,
                        "classification": "dependency_alias_drift",
                        "reason": "MovementFlagHelper removed from current live gold SQL",
                    },
                ]
            )

        output.append(new_row)

    existing_asset_ids = {row["asset_id"] for row in output}
    for asset_id, row in extra_manifest_rows.items():
        if asset_id not in existing_asset_ids:
            output.append(row)
            drift_notes.append(
                {
                    "asset_id": asset_id,
                    "classification": "added_from_live_gold_contract",
                    "reason": "present in live Gold warehouse but absent from manifest v1 registry extract",
                }
            )

    def sort_key(row: dict[str, str]) -> tuple[int, int, str, str, str]:
        layer_order = {"LogicalBronze": 0, "ReferenceMaster": 1, "Staging": 2, "DomainSilver": 3, "Gold": 4}
        wave_text = row["wave_number"].strip()
        wave = int(wave_text) if wave_text else 999
        return (
            layer_order.get(row["layer"], 9),
            wave,
            row["project"],
            row["schema_name"],
            row["object_name"],
        )

    output.sort(key=sort_key)
    final_asset_ids = {row["asset_id"] for row in output}

    ordered_output: list[dict[str, str]] = []
    remaining = output[:]
    emitted = set()
    while remaining:
        next_idx = None
        for idx, row in enumerate(remaining):
            deps = [dep for dep in parse_dependencies(row["depends_on"]) if dep in final_asset_ids]
            if all(dep in emitted for dep in deps):
                next_idx = idx
                break
        if next_idx is None:
            next_idx = 0
        row = remaining.pop(next_idx)
        ordered_output.append(row)
        emitted.add(row["asset_id"])

    for idx, row in enumerate(ordered_output, start=1):
        row["run_sequence"] = str(idx)

    return ordered_output, drift_notes


def fetch_live_targets(manifest_rows: list[dict[str, str]]) -> tuple[list[SqlTarget], list[SqlTarget]]:
    processing_targets: list[SqlTarget] = []
    gold_targets: list[SqlTarget] = []
    for row in manifest_rows:
        target = SqlTarget(row["database_name"], row["schema_name"], row["object_name"])
        if row["database_name"] == PROCESSING_DB:
            processing_targets.append(target)
        elif row["database_name"] == GOLD_DB:
            gold_targets.append(target)
    return processing_targets, gold_targets


def build_wrapper_sql(
    database: str,
    targets: list[SqlTarget],
    table_columns: dict[SqlTarget, list[dict[str, object]]],
    base_view_columns: dict[SqlTarget, list[dict[str, object]]],
) -> str:
    lines = [
        f"-- Phase 1E wrapper surface for {database}",
        "-- Generated from live table/view metadata to preserve current business SQL",
        "",
    ]

    by_schema: dict[str, list[SqlTarget]] = defaultdict(list)
    for target in targets:
        by_schema[target.schema].append(target)

    for schema in sorted(by_schema):
        wrapper_schema = f"{schema}_Wrk"
        lines.append(f"IF SCHEMA_ID('{wrapper_schema}') IS NULL EXEC('CREATE SCHEMA {quote_ident(wrapper_schema)}');")
        lines.append("GO")
        lines.append("")
        for target in sorted(by_schema[schema], key=lambda t: t.object_name):
            table_cols = table_columns[target]
            view_target = SqlTarget(target.database, target.schema, f"v_{target.object_name}")
            view_cols = base_view_columns.get(view_target, [])
            view_col_names = {str(col["COLUMN_NAME"]) for col in view_cols}

            select_lines = []
            for col in table_cols:
                col_name = str(col["COLUMN_NAME"])
                if col_name in view_col_names:
                    select_lines.append(f"    {quote_ident(col_name)} = src.{quote_ident(col_name)}")
                elif col_name == "LoadDT":
                    select_lines.append(
                        f"    {quote_ident(col_name)} = CAST(SYSUTCDATETIME() AS {sql_type(col)})"
                    )
                else:
                    select_lines.append(
                        f"    {quote_ident(col_name)} = CAST(NULL AS {sql_type(col)})"
                    )

            lines.append(
                f"CREATE OR ALTER VIEW {quote_ident(wrapper_schema)}.{quote_ident('v_' + target.object_name)} AS"
            )
            lines.append("SELECT")
            lines.append(",\n".join(select_lines))
            lines.append(f"FROM {quote_ident(target.schema)}.{quote_ident('v_' + target.object_name)} AS src;")
            lines.append("GO")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def build_manual_run_artifacts(
    manifest_rows: list[dict[str, str]],
    manifest_version: str,
) -> dict[str, str]:
    grouped: dict[str, list[dict[str, str]]] = {}

    def add_block(filename: str, title: str, rows: list[dict[str, str]]) -> None:
        lines = [
            f"-- {title}",
            f"-- Manifest version: {manifest_version}",
            f"-- Object count: {len(rows)}",
            "",
        ]
        for row in rows:
            exec_command = row["enterprise_etl_exec_command"]
            object_ref = (
                f"{row['run_sequence']}. {row['database_name']}.{row['schema_name']}.{row['object_name']}"
            )
            if exec_command.startswith("REGISTER_ONLY::"):
                lines.append(f"-- REGISTER_ONLY {object_ref}")
                lines.append(f"--   {exec_command}")
                lines.append("")
                continue
            if not boolish(row["is_manual_run_enabled"]):
                lines.append(f"-- APPROVAL REQUIRED {object_ref}")
                lines.append("--   exact command intentionally omitted from runnable pack")
                lines.append("--   approval required before heavy incremental catch-up")
                lines.append("")
                continue
            lines.append(f"-- {object_ref}")
            lines.append(exec_command)
            lines.append("GO")
            lines.append("")
        grouped[filename] = "\n".join(lines).rstrip() + "\n"

    bronze_reference_rows = [
        row for row in manifest_rows if row["layer"] in {"LogicalBronze", "ReferenceMaster", "Staging"}
    ]
    add_block(
        "phase1g_manual_refresh_bronze_reference.sql",
        "Bronze / Reference",
        bronze_reference_rows,
    )

    silver_waves = sorted(
        {
            int(row["wave_number"])
            for row in manifest_rows
            if row["layer"] == "DomainSilver" and row["wave_number"].strip()
        }
    )
    for wave in silver_waves:
        rows = [
            row
            for row in manifest_rows
            if row["layer"] == "DomainSilver" and row["wave_number"].strip() == str(wave)
        ]
        add_block(
            f"phase1g_manual_refresh_silver_wave_{wave}.sql",
            f"Silver Wave {wave}",
            rows,
        )

    gold_rows = [row for row in manifest_rows if row["layer"] == "Gold"]
    add_block("phase1g_manual_refresh_gold.sql", "Gold", gold_rows)

    all_lines = [
        f"-- Phase 1G manual refresh pack",
        f"-- Manifest version: {manifest_version}",
        "",
    ]
    ordered_files = ["phase1g_manual_refresh_bronze_reference.sql"]
    ordered_files.extend([f"phase1g_manual_refresh_silver_wave_{wave}.sql" for wave in silver_waves])
    ordered_files.append("phase1g_manual_refresh_gold.sql")
    for idx, filename in enumerate(ordered_files):
        if idx:
            all_lines.append("")
        all_lines.extend(grouped[filename].rstrip().splitlines())
    grouped["phase1g_manual_refresh_all.sql"] = "\n".join(all_lines).rstrip() + "\n"
    return grouped


def validate_manifest_order(manifest_rows: list[dict[str, str]]) -> list[str]:
    order = {row["asset_id"]: idx for idx, row in enumerate(manifest_rows)}
    issues: list[str] = []
    for row in manifest_rows:
        current_idx = order[row["asset_id"]]
        for dependency in parse_dependencies(row["depends_on"]):
            dep_idx = order.get(dependency)
            if dep_idx is None:
                issues.append(
                    f"{row['asset_id']} depends_on {dependency} but dependency is not present in manifest"
                )
                continue
            if dep_idx >= current_idx:
                issues.append(
                    f"{row['asset_id']} appears before dependency {dependency}"
                )
    return issues


def write_phase1g_artifacts(manifest_rows: list[dict[str, str]]) -> None:
    PHASE1G_DIR.mkdir(parents=True, exist_ok=True)
    manifest_version = "phase1_manual_refresh_manifest_v2"
    artifacts = build_manual_run_artifacts(manifest_rows, manifest_version)
    for filename, content in artifacts.items():
        (PHASE1G_DIR / filename).write_text(content)

    issues = validate_manifest_order(manifest_rows)
    if issues:
        validation_lines = [
            "# Phase 1G Dependency Order Validation",
            "",
            "Status: FAIL",
            "",
        ]
        validation_lines.extend(f"- {issue}" for issue in issues)
    else:
        validation_lines = [
            "# Phase 1G Dependency Order Validation",
            "",
            "Status: PASS",
            "",
            "- All manifest dependencies appear earlier than their dependents.",
        ]
    (PHASE1G_DIR / "phase1g_dependency_order_validation.md").write_text(
        "\n".join(validation_lines).rstrip() + "\n"
    )

    summary = {
        "manifest_version": manifest_version,
        "row_count": len(manifest_rows),
        "manual_enabled_count": sum(1 for row in manifest_rows if boolish(row["is_manual_run_enabled"])),
        "register_only_count": sum(
            1 for row in manifest_rows if row["enterprise_etl_exec_command"].startswith("REGISTER_ONLY::")
        ),
        "approval_required_count": sum(
            1
            for row in manifest_rows
            if (not boolish(row["is_manual_run_enabled"]))
            and not row["enterprise_etl_exec_command"].startswith("REGISTER_ONLY::")
        ),
        "dependency_issue_count": len(issues),
    }
    (PHASE1G_DIR / "phase1g_summary.json").write_text(json.dumps(summary, indent=2) + "\n")


def build_metadata_sql(manifest_rows: list[dict[str, str]]) -> str:
    lines = [
        "-- Phase 1E metadata backfill for local Enterprise ETL TableDictionary",
        "-- Only additive/update statements; no deletes",
        "",
    ]

    def update_row(
        database: str,
        schema: str,
        table: str,
        assignments: dict[str, object],
    ) -> None:
        set_clauses = []
        for key, value in assignments.items():
            if value is None:
                set_clauses.append(f"{quote_ident(key)} = NULL")
            elif isinstance(value, int):
                set_clauses.append(f"{quote_ident(key)} = {value}")
            else:
                escaped = str(value).replace("'", "''")
                set_clauses.append(f"{quote_ident(key)} = '{escaped}'")
        lines.append(
            f"UPDATE DW_Developer.TableDictionary\nSET    {', '.join(set_clauses)}\n"
            f"WHERE  DatabaseName = '{database}' AND SchemaName = '{schema}' AND TableName = '{table}';"
        )
        lines.append("GO")
        lines.append("")

    def insert_if_missing(
        database: str,
        schema: str,
        table: str,
        update_method: str,
        update_query: str,
    ) -> None:
        lines.append(
            "IF NOT EXISTS (\n"
            "    SELECT 1 FROM DW_Developer.TableDictionary\n"
            f"    WHERE DatabaseName = '{database}' AND SchemaName = '{schema}' AND TableName = '{table}'\n"
            ")\nBEGIN\n"
            "    INSERT INTO DW_Developer.TableDictionary\n"
            "    (ServerName, DatabaseName, SchemaName, TableName, ObjectType, StorageType, UpdateMethod, UpdateQuery)\n"
            f"    VALUES ('EDW-Fabric', '{database}', '{schema}', '{table}', 'Table', 'Delta', '{update_method}', '{update_query}');\n"
            "END\n"
            "GO\n"
        )

    # Current registry rows: set canonical UpdateQuery / UpdateMethod from manifest.
    for row in manifest_rows:
        update_method = row["load_type"]
        update_query = row["enterprise_etl_exec_command"]
        if "usp_RefreshCuratedTableFromView" in update_query:
            update_query = "[DW_Developer].[usp_RefreshCuratedTableFromView]"
        elif "usp_IncrementalTableLoad" in update_query:
            update_query = "[DW_Developer].[usp_IncrementalTableLoad]"
        elif "usp_UpdateCuratedTableFromView_DateRange" in update_query:
            update_query = "[DW_Developer].[usp_UpdateCuratedTableFromView_DateRange]"

        update_row(
            row["database_name"],
            row["schema_name"],
            row["object_name"],
            {"UpdateMethod": update_method, "UpdateQuery": update_query},
        )

    # Destination rows that need executable Enterprise ETL incremental/datekey metadata.
    for schema, table in [
        ("InventoryHealth_DW", "InventoryClassificationQtyWeekly"),
        ("InventoryHealth_DW", "InventoryHealthSubStatusWeekly"),
        ("InventoryHealth_DW", "FactInventoryHealthFutureWeekEnding"),
        ("InventoryHealth_DW", "ProjectedInventoryHealthSubStatus"),
    ]:
        insert_if_missing(
            GOLD_DB,
            schema,
            table,
            "overwrite",
            "[DW_Developer].[usp_RefreshCuratedTableFromView]",
        )

    update_row(
        PROCESSING_DB,
        "Staging",
        "DemandForecastSnapshotDaily",
        {
            "UpdateMethod": "DateRange",
            "ReplicatedSource": "Staging_Wrk.v_DemandForecastSnapshotDaily",
            "PrimaryKey": "dfcItem,dfcWarehouse,dfcFiscalMonth,dfcSnapshot,DfcCustomerGroups,dfcFCSTTypeCode,dfcMgmtCode",
            "DateKey": "dfcSnapshot",
            "DateRangeDays": 30,
            "UpdateQuery": "[DW_Developer].[usp_IncrementalTableLoad]",
        },
    )
    update_row(
        PROCESSING_DB,
        "InventoryHistory_Enh",
        "HoldingTransferSnapshotDaily",
        {
            "UpdateMethod": "DateKey",
            "ReplicatedSource": "InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily",
            "PrimaryKey": "SnapshotDate,TransferNumber,TransferLine",
            "DateKey": "SnapshotDate",
            "UpdateQuery": "[DW_Developer].[usp_IncrementalTableLoad]",
        },
    )
    update_row(
        PROCESSING_DB,
        "InventoryHistory_Enh",
        "ManufacturingOrderSnapshotDaily",
        {
            "UpdateMethod": "DateKey",
            "ReplicatedSource": "InventoryHistory_Enh_Wrk.v_ManufacturingOrderSnapshotDaily",
            "PrimaryKey": "SnapshotDate,MoNumber,ItemSku,WarehouseCode",
            "DateKey": "SnapshotDate",
            "UpdateQuery": "[DW_Developer].[usp_IncrementalTableLoad]",
        },
    )

    # Minimal source metadata rows so usp_IncrementalTableLoad can bind to wrapper views.
    source_rows = [
        {
            "SchemaName": "Staging_Wrk",
            "TableName": "v_DemandForecastSnapshotDaily",
            "ObjectType": "View",
            "PrimaryKey": "dfcItem,dfcWarehouse,dfcFiscalMonth,dfcSnapshot,DfcCustomerGroups,dfcFCSTTypeCode,dfcMgmtCode",
            "DateKey": "dfcSnapshot",
            "SelectColumn": (
                "dfcItem,dfcWarehouse,dfcFiscalMonth,dfcMainPiece,dfcCollectiveClass,"
                "dfcResultantForecast,dfcPromotionalLift,dfcForcedForecast,dfcValidDemandMonths,"
                "dfcSnapshot,dfcPermComptQty,dfcUsr25Text,dfcUsr32Text,dfcFCSTTypeCode,"
                "dfcDerivedFCSTID,dfcDerivedFCSTFctr,dfcOrderFutureQty,dfcMgmtCode,usra,dtea,usrc,dtec,"
                "DfcCustomerGroups,LoadDT"
            ),
        },
        {
            "SchemaName": "InventoryHistory_Enh_Wrk",
            "TableName": "v_HoldingTransferSnapshotDaily",
            "ObjectType": "View",
            "PrimaryKey": "SnapshotDate,TransferNumber,TransferLine",
            "DateKey": "SnapshotDate",
            "SelectColumn": (
                "SnapshotDate,TransferNumber,TransferLine,ItemSku,WarehouseCode,SourceWarehouseCode,"
                "ReceivingWarehouseCode,ShipDateKey,ShipDate,ShipWeekEndingDate,DueDateKey,DueDate,"
                "DueWeekEndingDate,HeaderComment,DetailComment,TransferQty,ShippedQty,TotalShippedQty,"
                "ExpediteCode,FirmCode,TransferCube,HeaderStatus,CancelFlag,SourceSystem,SourceTable,LoadDT"
            ),
        },
        {
            "SchemaName": "InventoryHistory_Enh_Wrk",
            "TableName": "v_ManufacturingOrderSnapshotDaily",
            "ObjectType": "View",
            "PrimaryKey": "SnapshotDate,MoNumber,ItemSku,WarehouseCode",
            "DateKey": "SnapshotDate",
            "SelectColumn": (
                "SnapshotDate,MoNumber,ItemSku,WarehouseCode,StatusCode,StatusName,RemainingMOQty,OrderQty,"
                "DeviationQty,ReceivedQty,ScrapQty,SplitQty,DueDateKey,SourceSystem,SourceTable,LoadDT"
            ),
        },
    ]

    for row in source_rows:
        lines.append(
            "IF NOT EXISTS (\n"
            "    SELECT 1 FROM DW_Developer.TableDictionary\n"
            f"    WHERE DatabaseName = '{PROCESSING_DB}' AND SchemaName = '{row['SchemaName']}' AND TableName = '{row['TableName']}'\n"
            ")\nBEGIN\n"
            "    INSERT INTO DW_Developer.TableDictionary\n"
            "    (ServerName, DatabaseName, SchemaName, TableName, ObjectType, StorageType, PrimaryKey, DateKey, SelectColumn)\n"
            f"    VALUES ('EDW-Fabric', '{PROCESSING_DB}', '{row['SchemaName']}', '{row['TableName']}', "
            f"'{row['ObjectType']}', 'Delta', '{row['PrimaryKey']}', '{row['DateKey']}', '{row['SelectColumn']}');\n"
            "END\n"
            "GO\n"
        )

    return "\n".join(lines).rstrip() + "\n"


def write_manifest(rows: list[dict[str, str]]) -> None:
    PHASE1E_DIR.mkdir(parents=True, exist_ok=True)
    path = PHASE1E_DIR / "phase1e_manifest_v2_live_contract.csv"
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_drift_summary(drift_notes: list[dict[str, str]], dependency_rows: list[dict[str, str]]) -> None:
    path = PHASE1E_DIR / "phase1e_contract_drift_summary.md"
    lines = [
        "# Phase 1E Contract Drift Summary",
        "",
        "## Dependency drift normalized from Phase 1D",
        "",
    ]
    for row in dependency_rows:
        lines.append(
            f"- `{row['asset_id']}` -> `{row['depends_on']}` classified `{row['status']}` in v1 and normalized in v2"
        )
    lines.extend(["", "## Live-contract adjustments", ""])
    for note in drift_notes:
        lines.append(
            f"- `{note['asset_id']}`: `{note['classification']}` — {note['reason']}"
        )
    path.write_text("\n".join(lines).rstrip() + "\n")


def write_json_summary(drift_notes: list[dict[str, str]], manifest_rows: list[dict[str, str]]) -> None:
    summary = {
        "manifest_v2_rows": len(manifest_rows),
        "gold_rows": sum(1 for row in manifest_rows if row["layer"] == "Gold"),
        "processing_rows": sum(1 for row in manifest_rows if row["database_name"] == PROCESSING_DB),
        "drift_note_count": len(drift_notes),
    }
    (PHASE1E_DIR / "phase1e_summary.json").write_text(json.dumps(summary, indent=2) + "\n")


def main() -> None:
    manifest_rows = load_manifest()
    dependency_rows = load_dependency_validation()
    manifest_v2, drift_notes = normalize_dependencies(manifest_rows)
    processing_targets, gold_targets = fetch_live_targets(manifest_v2)

    with connect(PROCESSING_DB) as processing_conn, connect(GOLD_DB) as gold_conn:
        processing_table_columns = fetch_columns(processing_conn, processing_targets)
        processing_view_columns = fetch_columns(
            processing_conn,
            [SqlTarget(t.database, t.schema, f"v_{t.object_name}") for t in processing_targets],
        )
        gold_table_columns = fetch_columns(gold_conn, gold_targets)
        gold_view_columns = fetch_columns(
            gold_conn,
            [SqlTarget(t.database, t.schema, f"v_{t.object_name}") for t in gold_targets],
        )

    write_manifest(manifest_v2)
    write_drift_summary(drift_notes, dependency_rows)
    write_json_summary(drift_notes, manifest_v2)

    (PHASE1E_DIR / "phase1e_wrapper_apply_processing.sql").write_text(
        build_wrapper_sql(PROCESSING_DB, processing_targets, processing_table_columns, processing_view_columns)
    )
    (PHASE1E_DIR / "phase1e_wrapper_apply_gold.sql").write_text(
        build_wrapper_sql(GOLD_DB, gold_targets, gold_table_columns, gold_view_columns)
    )
    (PHASE1E_DIR / "phase1e_metadata_backfill.sql").write_text(build_metadata_sql(manifest_v2))
    write_phase1g_artifacts(manifest_v2)


if __name__ == "__main__":
    main()
