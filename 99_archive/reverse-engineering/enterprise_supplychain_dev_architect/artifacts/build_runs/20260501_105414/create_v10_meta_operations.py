#!/usr/bin/env python3
"""Create v10 Meta operation views/procedures and seed runtime control rules."""

from __future__ import annotations

import json
import struct
import subprocess

import pyodbc


SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DATABASE = "SupplyChain_Processing_Warehouse"


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


def connect() -> pyodbc.Connection:
    token_struct = get_access_token()
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
        timeout=30,
        autocommit=True,
    )


def scalar(cur: pyodbc.Cursor, sql: str, params: tuple = ()) -> int:
    cur.execute(sql, params)
    return cur.fetchone()[0]


def create_view(cur: pyodbc.Cursor, name: str, sql: str) -> bool:
    schema, view = name.split(".", 1)
    if scalar(
        cur,
        """
        SELECT COUNT(*)
        FROM sys.views v
        JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE s.name = ? AND v.name = ?;
        """,
        (schema, view),
    ):
        return False
    cur.execute(sql)
    return True


def create_proc(cur: pyodbc.Cursor, name: str, sql: str) -> bool:
    schema, proc = name.split(".", 1)
    if scalar(
        cur,
        """
        SELECT COUNT(*)
        FROM sys.procedures p
        JOIN sys.schemas s ON s.schema_id = p.schema_id
        WHERE s.name = ? AND p.name = ?;
        """,
        (schema, proc),
    ):
        return False
    cur.execute(sql)
    return True


def insert_if_missing(cur: pyodbc.Cursor, sql: str, key_sql: str, key: tuple) -> bool:
    if scalar(cur, key_sql, key):
        return False
    cur.execute(sql)
    return True


def seed_silver_waves(cur: pyodbc.Cursor) -> int:
    wave_map = {
        "silver.slv_invoice_detail_line_level": 1,
        "silver.slv_forecast_demand_monthly": 1,
        "silver.slv_open_order_line_level": 1,
        "silver.slv_actual_demand_monthly": 2,
        "silver.slv_actual_demand_weekly": 2,
        "silver.slv_invoice_weekly": 2,
        "silver.slv_open_order_monthly": 2,
        "silver.slv_naive_forecast_monthly": 3,
    }
    inserted = 0
    for asset_id, wave in wave_map.items():
        if scalar(cur, "SELECT COUNT(*) FROM Meta.SilverDagWaveRuntime WHERE asset_id = ?;", (asset_id,)):
            continue
        cur.execute(
            """
            INSERT INTO Meta.SilverDagWaveRuntime
            (runtime_id, project, asset_id, physical_schema, physical_object,
             wave_number, dependency_count, is_active, computed_at_utc)
            SELECT
                CONCAT('wave::', asset_id),
                project,
                asset_id,
                physical_schema,
                physical_object,
                ?,
                CASE WHEN depends_on IS NULL OR depends_on = '' THEN 0 ELSE 1 END,
                is_active,
                SYSUTCDATETIME()
            FROM Meta.AssetRegistryV10
            WHERE asset_id = ?;
            """,
            (wave, asset_id),
        )
        inserted += 1
    return inserted


def seed_reconciliation_rules(cur: pyodbc.Cursor) -> int:
    rules = [
        ("recon::staging::InvoiceDetailEdw::rowcount", "bronze.brz_saleshistory_afi__invoicedetail", "SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2", "Staging.InvoiceDetailEdw", "RowCount"),
        ("recon::staging::InvoiceHeaderEdw::rowcount", "bronze.brz_saleshistory_afi__invoiceheader", "SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2", "Staging.InvoiceHeaderEdw", "RowCount"),
        ("recon::staging::DemandForecastSnapshotDailyEdw::rowcount", "bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily", "SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2", "Staging.DemandForecastSnapshotDailyEdw", "RowCount"),
        ("recon::staging::ProductEdw::rowcount", "bronze.ref_product", "SupplyChain_Lakehouse.dbo.ref_product_ver2", "Staging.ProductEdw", "RowCount"),
        ("recon::gold::FactForecastActual::rowcount", "gold.gld_fact_flat_forecast_actual", "SupplyChain_Warehouse.gold.gld_fact_flat_forecast_actual", "SupplyChain_Gold_Warehouse.ForecastAccuracy.FactForecastActual", "RowCount"),
        ("recon::gold::FactForecastKpi::rowcount", "gold.gld_fact_forecast_kpi", "SupplyChain_Warehouse.gold.gld_fact_forecast_kpi", "SupplyChain_Gold_Warehouse.ForecastAccuracy.FactForecastKpi", "RowCount"),
    ]
    inserted = 0
    for rule_id, asset_id, source, target, rule_type in rules:
        if scalar(cur, "SELECT COUNT(*) FROM Meta.ReconciliationRule WHERE rule_id = ?;", (rule_id,)):
            continue
        cur.execute(
            """
            INSERT INTO Meta.ReconciliationRule
            (rule_id, asset_id, source_object, target_object, reconciliation_type,
             tolerance_value, severity, is_active)
            VALUES (?, ?, ?, ?, ?, 0, 'CRITICAL', 1);
            """,
            (rule_id, asset_id, source, target, rule_type),
        )
        inserted += 1
    return inserted


def create_operations(cur: pyodbc.Cursor) -> dict[str, int]:
    created_views = 0
    created_procs = 0

    if create_view(
        cur,
        "Meta.vw_SilverWaveRuntime",
        """
CREATE VIEW Meta.vw_SilverWaveRuntime AS
SELECT
    r.project,
    r.wave_number,
    r.asset_id,
    r.physical_schema AS target_schema,
    r.physical_object AS target_object,
    a.depends_on AS depends_on_asset_ids,
    CASE
        WHEN a.is_active = 1
         AND (a.next_run_time IS NULL OR a.next_run_time <= SYSUTCDATETIME()) THEN 1
        ELSE 0
    END AS is_due,
    CAST('Pending' AS VARCHAR(80)) AS execution_status,
    r.computed_at_utc
FROM Meta.SilverDagWaveRuntime r
JOIN Meta.AssetRegistryV10 a
    ON a.asset_id = r.asset_id;
""",
    ):
        created_views += 1

    procedures = {
        "Meta.usp_ResolveAccessMode": """
CREATE PROCEDURE Meta.usp_ResolveAccessMode
    @asset_id VARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        asset_id,
        canonical_layer,
        access_mode,
        physical_workspace,
        physical_item,
        physical_schema,
        physical_object,
        source_contract_status,
        approval_status,
        edw_exit_status,
        staging_reason
    FROM Meta.AssetRegistryV10
    WHERE asset_id = @asset_id;
END
""",
        "Meta.usp_GenericLoad": """
CREATE PROCEDURE Meta.usp_GenericLoad
    @asset_id VARCHAR(128),
    @run_mode VARCHAR(40) = 'PlanOnly'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        @run_mode AS run_mode,
        asset_id,
        canonical_layer,
        access_mode,
        physical_item,
        physical_schema,
        physical_object,
        CASE
            WHEN @run_mode <> 'PlanOnly' THEN 'Execution is intentionally gated until load SQL is approved'
            WHEN access_mode = 'EDWSupplement' THEN 'Stage from LegacyDataflowBridge source'
            WHEN access_mode = 'DirectShortcut' THEN 'Read from Enterprise_Lakehouse shortcut'
            WHEN access_mode = 'WarehouseTransform' THEN 'Run Domain Silver transform'
            WHEN access_mode = 'GoldPublish' THEN 'Publish physical Gold table'
            ELSE 'Review access mode'
        END AS execution_plan
    FROM Meta.AssetRegistryV10
    WHERE asset_id = @asset_id;
END
""",
        "Meta.usp_ComputeSilverWaves": """
CREATE PROCEDURE Meta.usp_ComputeSilverWaves
    @project VARCHAR(128) = 'ForecastAccuracy'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        project,
        wave_number,
        asset_id,
        target_schema,
        target_object,
        depends_on_asset_ids,
        is_due,
        execution_status
    FROM Meta.vw_SilverWaveRuntime
    WHERE project = @project
    ORDER BY wave_number, asset_id;
END
""",
        "Meta.usp_ValidateSourceContract": """
CREATE PROCEDURE Meta.usp_ValidateSourceContract
    @asset_id VARCHAR(128),
    @gate_mode VARCHAR(40) = 'WarnOnly'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @status VARCHAR(80);
    SELECT @status =
        CASE
            WHEN COUNT(*) = 0 THEN 'NoContract'
            WHEN SUM(CASE WHEN validation_status = 'valid' THEN 1 ELSE 0 END) = COUNT(*) THEN 'Valid'
            ELSE 'NeedsReview'
        END
    FROM Meta.SourceContract
    WHERE target_table = PARSENAME(REPLACE(@asset_id, '.', '.'), 1)
      AND is_active = 1;

    INSERT INTO Meta.SourceContractRun
    (contract_run_id, asset_id, run_id, validation_status, checked_at_utc, error_message)
    VALUES
    (CONCAT('contract::', CONVERT(VARCHAR(36), NEWID())), @asset_id, NULL, @status, SYSUTCDATETIME(), NULL);

    SELECT @asset_id AS asset_id, @gate_mode AS gate_mode, @status AS validation_status;
END
""",
        "Meta.usp_RunDQGate": """
CREATE PROCEDURE Meta.usp_RunDQGate
    @asset_id VARCHAR(128),
    @gate_mode VARCHAR(40) = 'WarnOnly'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @legacy_schema VARCHAR(128);
    DECLARE @legacy_table VARCHAR(256);
    DECLARE @rule_count INT;

    SELECT
        @legacy_schema = legacy_target_schema,
        @legacy_table = legacy_target_table
    FROM Meta.AssetRegistryV10
    WHERE asset_id = @asset_id;

    SELECT @rule_count = COUNT(*)
    FROM Meta.DQRule
    WHERE target_schema = @legacy_schema
      AND target_table = @legacy_table
      AND is_active = 1;

    INSERT INTO Meta.DQGateRun
    (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message)
    VALUES
    (CONCAT('dq::', CONVERT(VARCHAR(36), NEWID())), @asset_id, NULL, @gate_mode, 'Configured', SYSUTCDATETIME(), 0, NULL);

    SELECT @asset_id AS asset_id, @gate_mode AS gate_mode, @rule_count AS active_rule_count, 'Configured' AS status;
END
""",
        "Meta.usp_RunReconciliation": """
CREATE PROCEDURE Meta.usp_RunReconciliation
    @asset_id VARCHAR(128),
    @run_id VARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Meta.ReconciliationResult
    (result_id, rule_id, run_id, status, source_value, target_value, variance_value, checked_at_utc, error_message)
    SELECT
        CONCAT('recon::', CONVERT(VARCHAR(36), NEWID())),
        rule_id,
        @run_id,
        'NotRun',
        NULL,
        NULL,
        NULL,
        SYSUTCDATETIME(),
        'Rule scaffold exists; source/target query implementation pending approved load SQL'
    FROM Meta.ReconciliationRule
    WHERE asset_id = @asset_id
      AND is_active = 1;

    SELECT *
    FROM Meta.ReconciliationRule
    WHERE asset_id = @asset_id
      AND is_active = 1;
END
""",
        "Meta.usp_BuildLineage": """
CREATE PROCEDURE Meta.usp_BuildLineage
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        edge_id,
        source_asset,
        target_asset,
        edge_type,
        transform_type,
        is_synthetic,
        created_at_utc,
        notes
    FROM Meta.LineageEdge
    ORDER BY target_asset, edge_type, source_asset;
END
""",
        "Meta.usp_LogRun": """
CREATE PROCEDURE Meta.usp_LogRun
    @run_id VARCHAR(128),
    @asset_id VARCHAR(128),
    @status VARCHAR(80),
    @rows_loaded BIGINT = NULL,
    @error_message VARCHAR(4000) = NULL,
    @load_type VARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Meta.RunLog
    (run_id, asset_id, object_name, layer_name, status, start_time_utc, end_time_utc,
     start_time_cst, end_time_cst, rows_loaded, error_message, load_type)
    SELECT
        @run_id,
        asset_id,
        CONCAT(physical_schema, '.', physical_object),
        canonical_layer,
        @status,
        SYSUTCDATETIME(),
        SYSUTCDATETIME(),
        NULL,
        NULL,
        @rows_loaded,
        @error_message,
        COALESCE(@load_type, load_type)
    FROM Meta.AssetRegistryV10
    WHERE asset_id = @asset_id;
END
""",
        "Meta.usp_LogPipelineRun": """
CREATE PROCEDURE Meta.usp_LogPipelineRun
    @pipeline_run_id VARCHAR(128),
    @pipeline_name VARCHAR(256),
    @project VARCHAR(128),
    @status VARCHAR(80),
    @trigger_type VARCHAR(80) = NULL,
    @error_message VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Meta.PipelineRunLog
    (pipeline_run_id, pipeline_name, project, status, start_time_utc, end_time_utc, trigger_type, error_message)
    VALUES
    (@pipeline_run_id, @pipeline_name, @project, @status, SYSUTCDATETIME(), SYSUTCDATETIME(), @trigger_type, @error_message);
END
""",
        "Meta.usp_FinalizePipeline": """
CREATE PROCEDURE Meta.usp_FinalizePipeline
    @pipeline_run_id VARCHAR(128),
    @project VARCHAR(128) = 'ForecastAccuracy'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        @pipeline_run_id AS pipeline_run_id,
        @project AS project,
        (SELECT COUNT(*) FROM Meta.AssetRegistryV10 WHERE project = @project AND is_active = 1) AS active_asset_count,
        (SELECT COUNT(*) FROM Meta.LineageEdge) AS lineage_edge_count,
        (SELECT COUNT(*) FROM Meta.DQGateRun WHERE run_id = @pipeline_run_id) AS dq_gate_count,
        (SELECT COUNT(*) FROM Meta.ReconciliationResult WHERE run_id = @pipeline_run_id) AS reconciliation_result_count,
        SYSUTCDATETIME() AS finalized_at_utc;
END
""",
        "Meta.usp_DebugLoop": """
CREATE PROCEDURE Meta.usp_DebugLoop
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 'AssetRegistryV10' AS object_name, COUNT(*) AS row_count FROM Meta.AssetRegistryV10
    UNION ALL SELECT 'SourceFeed', COUNT(*) FROM Meta.SourceFeed
    UNION ALL SELECT 'SourceContract', COUNT(*) FROM Meta.SourceContract
    UNION ALL SELECT 'DQRule', COUNT(*) FROM Meta.DQRule
    UNION ALL SELECT 'LineageEdge', COUNT(*) FROM Meta.LineageEdge
    UNION ALL SELECT 'ReconciliationRule', COUNT(*) FROM Meta.ReconciliationRule
    UNION ALL SELECT 'SilverDagWaveRuntime', COUNT(*) FROM Meta.SilverDagWaveRuntime;
END
""",
    }

    for name, sql in procedures.items():
        if create_proc(cur, name, sql):
            created_procs += 1

    return {"created_views": created_views, "created_procs": created_procs}


def verify(cur: pyodbc.Cursor) -> dict[str, int]:
    result = {}
    queries = {
        "meta_tables": "SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='Meta';",
        "meta_views": "SELECT COUNT(*) FROM sys.views v JOIN sys.schemas s ON s.schema_id=v.schema_id WHERE s.name='Meta';",
        "meta_procs": "SELECT COUNT(*) FROM sys.procedures p JOIN sys.schemas s ON s.schema_id=p.schema_id WHERE s.name='Meta';",
        "silver_wave_runtime_rows": "SELECT COUNT(*) FROM Meta.SilverDagWaveRuntime;",
        "reconciliation_rules": "SELECT COUNT(*) FROM Meta.ReconciliationRule;",
        "dq_rules": "SELECT COUNT(*) FROM Meta.DQRule;",
    }
    for key, sql in queries.items():
        result[key] = scalar(cur, sql)
    return result


def main() -> int:
    conn = connect()
    cur = conn.cursor()
    created = create_operations(cur)
    waves_inserted = seed_silver_waves(cur)
    reconciliation_inserted = seed_reconciliation_rules(cur)
    result = {
        **created,
        "silver_waves_inserted": waves_inserted,
        "reconciliation_rules_inserted": reconciliation_inserted,
        "verification": verify(cur),
    }
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
