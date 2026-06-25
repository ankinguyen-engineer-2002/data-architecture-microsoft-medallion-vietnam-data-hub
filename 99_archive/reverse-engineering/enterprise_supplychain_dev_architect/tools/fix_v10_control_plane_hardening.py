#!/usr/bin/env python3
"""
v10 control-plane hardening (live):

Targets:
  1) TableDictionary backfill for active assets (Bob-compatible mapping).
  2) Mart-level pipeline logging (pl_sc_mart -> Meta.usp_LogPipelineRun).
  3) Due-only gating for Silver waves (pl_sc_silver_wave).
  4) Gold per-table run logging + due gating (pl_sc_gold -> Meta.usp_LogRun + ufn_should_run gate).
  5) Cron-aware next_run_time computation (Meta.usp_LogRun + Meta.ufn_cron_next_run_time).

Idempotent intent:
  - Safe to re-run; it snapshots before/after and only applies missing patches.

Artifacts:
  Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/<ts>_v10_control_plane_hardening/
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import pathlib
import struct
import subprocess
import sys
from typing import Any

import pyodbc


WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
FABRIC_BASE = f"https://api.fabric.microsoft.com/v1/workspaces/{WORKSPACE_ID}"

SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
SQL_DATABASE = "SupplyChain_Processing_Warehouse"

PIPELINES = {
    "pl_sc_mart": "20db5725-80e3-4081-9ef5-01700acdf3b3",
    "pl_sc_silver_wave": "797b1a02-f973-4584-bd27-bb0151549d4b",
    "pl_sc_gold": "50ff6263-659d-4b09-9e45-b42a3434e093",
}


def run(cmd: list[str], *, input_text: str | None = None) -> str:
    proc = subprocess.run(
        cmd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0 and not proc.stdout.strip():
        raise RuntimeError(f"command failed rc={proc.returncode}: {' '.join(cmd)}\n{proc.stderr.strip()}")
    return proc.stdout


def az_token(resource: str) -> str:
    return (
        run(
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
            ]
        )
        .strip()
    )


def sql_conn() -> pyodbc.Connection:
    token = az_token("https://database.windows.net/").encode("utf-16-le")
    token_struct = struct.pack("<I", len(token)) + token
    return pyodbc.connect(
        (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={SQL_SERVER};DATABASE={SQL_DATABASE};"
            "Encrypt=yes;TrustServerCertificate=no;"
        ),
        attrs_before={1256: token_struct},
    )


def fabric_request(method: str, url: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    cmd = [
        "az",
        "rest",
        "--method",
        method,
        "--resource",
        "https://api.fabric.microsoft.com",
        "--url",
        url,
    ]
    input_text = None
    if body is not None:
        cmd.extend(["--body", "@-"])
        input_text = json.dumps(body)
    raw = run(cmd, input_text=input_text).strip()
    if not raw:
        return {}
    return json.loads(raw)


def get_pipeline_definition(pipeline_id: str) -> dict[str, Any]:
    return fabric_request("POST", f"{FABRIC_BASE}/items/{pipeline_id}/getDefinition")


def update_pipeline_definition(pipeline_id: str, definition: dict[str, Any]) -> dict[str, Any]:
    return fabric_request(
        "POST",
        f"{FABRIC_BASE}/items/{pipeline_id}/updateDefinition",
        {"definition": definition["definition"]},
    )


def decode_pipeline_content(definition: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    part = next(p for p in definition["definition"]["parts"] if p["path"] == "pipeline-content.json")
    payload = base64.b64decode(part["payload"]).decode("utf-8")
    return part, json.loads(payload)


def encode_pipeline_content(part: dict[str, Any], content: dict[str, Any]) -> dict[str, Any]:
    updated = dict(part)
    updated["payload"] = base64.b64encode(json.dumps(content, indent=2).encode("utf-8")).decode("ascii")
    updated["payloadType"] = "InlineBase64"
    return updated


def write_json(path: pathlib.Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")


def write_text(path: pathlib.Path, payload: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="utf-8")


def build_output_dir(root: pathlib.Path) -> pathlib.Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = (
        root
        / "Enterprise_SupplyChain_Dev_architect"
        / "artifacts"
        / "build_runs"
        / f"{ts}_v10_control_plane_hardening"
    )
    out.mkdir(parents=True, exist_ok=True)
    return out


def fetch_sql_rows(conn: pyodbc.Connection, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    cur = conn.cursor()
    cur.execute(sql, params)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def execute_sql(conn: pyodbc.Connection, sql: str) -> None:
    cur = conn.cursor()
    cur.execute(sql)
    conn.commit()


def snapshot_sql_objects(conn: pyodbc.Connection, output_dir: pathlib.Path) -> None:
    objects = [
        "Meta.ufn_cron_is_due",
        "Meta.ufn_should_run",
        "Meta.ufn_utc_to_cst",
        "Meta.usp_LogRun",
        "Meta.usp_LogPipelineRun",
        "Meta.usp_UpdateTableDictionary_ModifiedDate",
        "Meta.usp_UpdateTableDictionaryModified",
    ]
    for obj in objects:
        rows = fetch_sql_rows(
            conn,
            "SELECT m.definition AS definition FROM sys.sql_modules m WHERE m.object_id = OBJECT_ID(?);",
            (obj,),
        )
        definition = (rows[0]["definition"] if rows else None) or ""
        write_text(output_dir / "sql_defs" / f"{obj.replace('.', '_')}.sql", definition.strip() + "\n")


def snapshot_control_plane_tables(conn: pyodbc.Connection, output_dir: pathlib.Path) -> None:
    snapshots = {
        "asset_registry_active.json": """
            SELECT asset_id, project, canonical_layer,
                   physical_item, physical_schema, physical_object,
                   frequency, cron_expression, scheduled_hour,
                   next_run_time, last_load_date, rows_loaded, load_type,
                   legacy_sp_name, legacy_view_name,
                   is_active, updated_at_utc
            FROM Meta.AssetRegistry
            WHERE is_active = 1
            ORDER BY project, canonical_layer, asset_id;
        """,
        "table_dictionary_inventoryhistory.json": """
            SELECT TOP 500 *
            FROM Meta.TableDictionary
            WHERE SchemaName = 'InventoryHistory_Enh'
            ORDER BY Modified DESC;
        """,
        "pipeline_runlog_recent.json": """
            SELECT TOP 200 *
            FROM Meta.PipelineRunLog
            ORDER BY start_time_utc DESC;
        """,
        "runlog_recent.json": """
            SELECT TOP 200 *
            FROM Meta.RunLog
            ORDER BY start_time_utc DESC;
        """,
        "table_dictionary_updatelog_recent.json": """
            SELECT TOP 200 *
            FROM Meta.TableDictionary_UpdateLog
            ORDER BY LastUpdated DESC;
        """,
        "lineage_edge_counts.json": """
            SELECT edge_type, COUNT(*) AS cnt
            FROM Meta.LineageEdge
            GROUP BY edge_type
            ORDER BY edge_type;
        """,
    }
    for filename, sql in snapshots.items():
        write_json(output_dir / "sql_snapshots" / filename, fetch_sql_rows(conn, sql))


def snapshot_pipelines(output_dir: pathlib.Path, suffix: str) -> None:
    for name, pid in PIPELINES.items():
        definition = get_pipeline_definition(pid)
        write_json(output_dir / "pipeline_defs" / f"{name}_{suffix}_getDefinition.json", definition)
        part, content = decode_pipeline_content(definition)
        write_text(
            output_dir / "pipeline_defs" / f"{name}_{suffix}_pipeline-content.json",
            json.dumps(content, indent=2),
        )
        write_json(output_dir / "pipeline_defs" / f"{name}_{suffix}_pipeline-part.json", part)


def ensure_cron_next_run_time_fn(conn: pyodbc.Connection) -> None:
    ddl = """
    CREATE OR ALTER FUNCTION Meta.ufn_cron_next_run_time(@cron VARCHAR(100), @from_utc DATETIME2(6))
    RETURNS DATETIME2(6)
    AS
    BEGIN
        IF @cron IS NULL OR LTRIM(RTRIM(@cron)) = '' RETURN NULL;

        DECLARE @minute INT, @hour INT, @dom VARCHAR(20), @mon VARCHAR(20), @dow VARCHAR(20);
        DECLARE @parts VARCHAR(100) = LTRIM(RTRIM(@cron));
        DECLARE @f1 VARCHAR(20), @f2 VARCHAR(20), @f3 VARCHAR(20), @f4 VARCHAR(20), @f5 VARCHAR(20);

        SET @f1 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1);
        SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f1) + 2, 100));
        SET @f2 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1);
        SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f2) + 2, 100));
        SET @f3 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1);
        SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f3) + 2, 100));
        SET @f4 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1);
        SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f4) + 2, 100));
        SET @f5 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1);

        -- Only support fixed minute/hour (no lists/ranges/steps) for v10 usage patterns.
        IF @f1 = '*' OR @f2 = '*' RETURN NULL;
        SET @minute = TRY_CAST(@f1 AS INT);
        SET @hour = TRY_CAST(@f2 AS INT);
        SET @dom = @f3;
        SET @mon = @f4;
        SET @dow = @f5;
        IF @minute IS NULL OR @hour IS NULL RETURN NULL;

        DECLARE @from_date DATE = CAST(@from_utc AS DATE);
        DECLARE @candidate DATETIME2(6) = DATEADD(MINUTE, @minute, DATEADD(HOUR, @hour, CAST(@from_date AS DATETIME2(6))));

        -- Monthly: day-of-month fixed, day-of-week wildcard
        IF @dom <> '*' AND @dow = '*'
        BEGIN
            DECLARE @day INT = TRY_CAST(@dom AS INT);
            IF @day IS NULL OR @day < 1 OR @day > 31 RETURN NULL;

            DECLARE @y INT = YEAR(@from_date);
            DECLARE @m INT = MONTH(@from_date);
            DECLARE @in_month DATE = TRY_CONVERT(DATE, CONCAT(@y, '-', RIGHT('00' + CAST(@m AS VARCHAR(2)), 2), '-', RIGHT('00' + CAST(@day AS VARCHAR(2)), 2)));
            IF @in_month IS NULL
                SET @in_month = EOMONTH(DATEFROMPARTS(@y, @m, 1));

            SET @candidate = DATEADD(MINUTE, @minute, DATEADD(HOUR, @hour, CAST(@in_month AS DATETIME2(6))));
            IF @candidate > @from_utc RETURN @candidate;

            DECLARE @next_month DATE = DATEADD(MONTH, 1, DATEFROMPARTS(@y, @m, 1));
            SET @y = YEAR(@next_month);
            SET @m = MONTH(@next_month);
            SET @in_month = TRY_CONVERT(DATE, CONCAT(@y, '-', RIGHT('00' + CAST(@m AS VARCHAR(2)), 2), '-', RIGHT('00' + CAST(@day AS VARCHAR(2)), 2)));
            IF @in_month IS NULL
                SET @in_month = EOMONTH(DATEFROMPARTS(@y, @m, 1));
            RETURN DATEADD(MINUTE, @minute, DATEADD(HOUR, @hour, CAST(@in_month AS DATETIME2(6))));
        END

        -- Weekly: day-of-week fixed, day-of-month wildcard
        IF @dom = '*' AND @dow <> '*'
        BEGIN
            DECLARE @target_dow INT = TRY_CAST(@dow AS INT);
            IF @target_dow IS NULL OR @target_dow < 0 OR @target_dow > 6 RETURN NULL;

            -- Align to ufn_cron_is_due semantics: 0=Mon, 6=Sun (DATEFIRST=7).
            DECLARE @cur_dow INT = (DATEPART(WEEKDAY, @from_date) + 5) % 7;
            DECLARE @days_until INT = (@target_dow - @cur_dow + 7) % 7;
            IF @days_until = 0 AND @candidate <= @from_utc SET @days_until = 7;
            RETURN DATEADD(DAY, @days_until, @candidate);
        END

        -- Daily (or any other pattern treated as daily hour/minute)
        IF @candidate > @from_utc RETURN @candidate;
        RETURN DATEADD(DAY, 1, @candidate);
    END
    """
    execute_sql(conn, ddl)


def alter_ufn_should_run(conn: pyodbc.Connection) -> None:
    ddl = """
    ALTER FUNCTION Meta.ufn_should_run(@asset_id VARCHAR(128))
    RETURNS INT
    AS
    BEGIN
        DECLARE @result INT = 0;
        SELECT @result = CASE
            WHEN is_active = 0 THEN 0
            WHEN next_run_time IS NOT NULL AND next_run_time <= GETUTCDATE() THEN 1
            WHEN next_run_time IS NULL AND (cron_expression IS NULL OR LTRIM(RTRIM(cron_expression)) = '') THEN 1
            WHEN next_run_time IS NULL THEN Meta.ufn_cron_is_due(cron_expression)
            ELSE 0
        END
        FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
        RETURN ISNULL(@result, 0);
    END
    """
    execute_sql(conn, ddl)


def alter_usp_logrun_next_runtime(conn: pyodbc.Connection) -> None:
    ddl = """
    ALTER PROCEDURE Meta.usp_LogRun
        @run_id VARCHAR(128),
        @asset_id VARCHAR(128),
        @status VARCHAR(80),
        @rows_loaded BIGINT = NULL,
        @error_message VARCHAR(4000) = NULL,
        @pipeline_run_id VARCHAR(128) = NULL,
        @load_type VARCHAR(80) = NULL
    AS
    BEGIN
        DECLARE @retry INT = 0, @done INT = 0;
        DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
        DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);
        DECLARE @user VARCHAR(200) = SYSTEM_USER;
        DECLARE @audit_id BIGINT = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', @now) AS BIGINT);
        DECLARE @db VARCHAR(150), @schema VARCHAR(150), @object VARCHAR(150), @sp_name VARCHAR(500);

        WHILE @retry < 3 AND @done = 0
        BEGIN
            BEGIN TRY
                IF @status = 'running'
                BEGIN
                    INSERT INTO Meta.RunLog (run_id, asset_id, object_name, layer_name,
                                              status, start_time_utc, start_time_cst, load_type)
                    SELECT @run_id, @asset_id,
                           CONCAT(physical_schema, '.', physical_object),
                           canonical_layer, 'running', @now, @now_cst,
                           COALESCE(@load_type, load_type)
                    FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
                END
                ELSE
                BEGIN
                    UPDATE Meta.RunLog
                    SET end_time_utc = @now,
                        end_time_cst = @now_cst,
                        rows_loaded = @rows_loaded,
                        status = @status,
                        error_message = @error_message
                    WHERE run_id = @run_id;

                    UPDATE Meta.AssetRegistry
                    SET last_load_date = @now,
                        rows_loaded = @rows_loaded,
                        next_run_time =
                            CASE
                                WHEN cron_expression IS NOT NULL AND LTRIM(RTRIM(cron_expression)) <> ''
                                    THEN Meta.ufn_cron_next_run_time(cron_expression, @now)
                                WHEN frequency = 'daily' AND scheduled_hour IS NOT NULL
                                    THEN DATEADD(HOUR, scheduled_hour, DATEADD(DAY, 1, CAST(@now AS DATE)))
                                WHEN frequency = 'daily'
                                    THEN DATEADD(DAY, 1, CAST(@now AS DATE))
                                WHEN frequency = 'hourly'
                                    THEN DATEADD(HOUR, 1, @now)
                                WHEN frequency = 'weekly'
                                    THEN DATEADD(WEEK, 1, CAST(@now AS DATE))
                                WHEN frequency = 'monthly'
                                    THEN DATEADD(MONTH, 1, CAST(@now AS DATE))
                                ELSE DATEADD(DAY, 1, CAST(@now AS DATE))
                            END
                    WHERE asset_id = @asset_id;

                    -- AuditLog (Bob pattern)
                    INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command,
                                                Description, ErrorMessage, AssetID, RunID,
                                                Severity, LoadDT)
                    SELECT @audit_id, @now_cst, @user,
                           CONCAT('LoadAsset:', physical_schema, '.', physical_object),
                           CASE
                               WHEN @status = 'failed'
                                   THEN CONCAT('FAILED loading ', physical_schema, '.', physical_object)
                               ELSE CONCAT('Loaded ', physical_schema, '.', physical_object,
                                           ' rows=', COALESCE(CAST(@rows_loaded AS VARCHAR(20)), 'NULL'))
                           END,
                           @error_message,
                           @asset_id, @run_id,
                           CASE WHEN @status = 'failed' THEN 'ERROR' ELSE 'INFO' END,
                           @now_cst
                    FROM Meta.AssetRegistry WHERE asset_id = @asset_id;

                    -- NEW (Mức 2): TableDictionary update via Bob's pattern proc
                    IF @status IN ('success', 'skipped')
                    BEGIN
                        SELECT @db = physical_item, @schema = physical_schema,
                               @object = physical_object, @sp_name = legacy_sp_name
                        FROM Meta.AssetRegistry WHERE asset_id = @asset_id;

                        EXEC Meta.usp_UpdateTableDictionary_ModifiedDate
                             @DestinationDatabase = @db,
                             @DestinationSchema = @schema,
                             @DestinationTable = @object,
                             @UpdateQuery = @sp_name,
                             @DateValue = @now_cst,
                             @RowsLoaded = @rows_loaded,
                             @AssetID = @asset_id,
                             @RunID = @run_id;
                    END
                END
                SET @done = 1;
            END TRY
            BEGIN CATCH
                SET @retry = @retry + 1;
                IF @retry >= 3
                BEGIN
                    DECLARE @err_msg VARCHAR(4000) = ERROR_MESSAGE();
                    RAISERROR('usp_LogRun failed after 3 retries: %s', 10, 1, @err_msg);
                END
                WAITFOR DELAY '00:00:02';
            END CATCH
        END
    END
    """
    execute_sql(conn, ddl)


def backfill_table_dictionary(conn: pyodbc.Connection, output_dir: pathlib.Path) -> dict[str, Any]:
    active = fetch_sql_rows(
        conn,
        """
        SELECT asset_id, physical_item, physical_schema, physical_object,
               legacy_sp_name, COALESCE(rows_loaded, 0) AS rows_loaded,
               COALESCE(last_load_date, SYSUTCDATETIME()) AS last_load_date_utc
        FROM Meta.AssetRegistry
        WHERE is_active = 1;
        """,
    )
    missing: list[dict[str, Any]] = []
    skipped_missing_mapping: list[dict[str, Any]] = []
    for row in active:
        if not row.get("physical_item") or not row.get("physical_schema") or not row.get("physical_object"):
            skipped_missing_mapping.append(row)
            continue
        schema = row["physical_schema"]
        table = row["physical_object"]
        cur = conn.cursor()
        cur.execute(
            """
            SELECT COUNT(*)
            FROM Meta.TableDictionary
            WHERE DatabaseName = ?
              AND SchemaName   = ?
              AND TableName    = ?;
            """,
            (row["physical_item"], schema, table),
        )
        exists = int(cur.fetchone()[0]) > 0
        if not exists:
            missing.append(row)

    write_json(output_dir / "table_dictionary_backfill" / "missing_before.json", missing)
    write_json(
        output_dir / "table_dictionary_backfill" / "skipped_missing_mapping.json",
        skipped_missing_mapping,
    )

    results: list[dict[str, Any]] = []
    for row in missing:
        run_id = f"backfill::tabledict::{row['asset_id']}"
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT Meta.ufn_utc_to_cst(CAST(? AS DATETIME2(6))) AS dt_cst;",
                (row["last_load_date_utc"],),
            )
            dt_cst = cur.fetchone()[0]

            cur = conn.cursor()
            cur.execute(
                """
                EXEC Meta.usp_UpdateTableDictionary_ModifiedDate
                     @DestinationDatabase = ?,
                     @DestinationSchema   = ?,
                     @DestinationTable    = ?,
                     @UpdateQuery         = ?,
                     @DateValue           = ?,
                     @RowsLoaded          = ?,
                     @AssetID             = ?,
                     @RunID               = ?;
                """,
                (
                    row["physical_item"],
                    row["physical_schema"],
                    row["physical_object"],
                    row["legacy_sp_name"] or "",
                    dt_cst,
                    row["rows_loaded"],
                    row["asset_id"],
                    run_id,
                ),
            )
            conn.commit()
            results.append({"asset_id": row["asset_id"], "status": "success"})
        except Exception as exc:  # noqa: BLE001 - capture per-asset failure without aborting whole batch
            try:
                conn.rollback()
            except Exception:
                pass
            results.append({"asset_id": row.get("asset_id"), "status": "failed", "error": str(exc)})

    write_json(output_dir / "table_dictionary_backfill" / "results.json", results)
    summary = {
        "active_count": len(active),
        "missing_before_count": len(missing),
        "skipped_missing_mapping_count": len(skipped_missing_mapping),
        "success_count": sum(1 for r in results if r.get("status") == "success"),
        "failed_count": sum(1 for r in results if r.get("status") == "failed"),
    }
    write_json(output_dir / "table_dictionary_backfill" / "summary.json", summary)

    after = fetch_sql_rows(
        conn,
        """
        SELECT SchemaName, TableName, COUNT(*) AS cnt
        FROM Meta.TableDictionary
        GROUP BY SchemaName, TableName
        HAVING SchemaName='InventoryHistory_Enh'
           AND TableName IN ('Cogs52WWeekly','ItemBalanceHistorical_WithInTransit')
        ORDER BY TableName;
        """,
    )
    write_json(output_dir / "table_dictionary_backfill" / "inventory_key_rows_after.json", after)
    return summary


def _ls_wh_processing() -> dict[str, Any]:
    return {
        "name": "wh",
        "properties": {
            "annotations": [],
            "type": "DataWarehouse",
            "typeProperties": {
                "endpoint": SQL_SERVER,
                "artifactId": "c0262cef-b8a7-495f-bccc-53b098c7948c",
                "workspaceId": WORKSPACE_ID,
            },
        },
    }


def patch_pl_sc_mart(definition: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    part, content = decode_pipeline_content(definition)
    raw = json.dumps(content)
    if "usp_LogPipelineRun" in raw:
        return definition, False

    activities = content.get("properties", {}).get("activities", [])
    if not isinstance(activities, list) or not activities:
        raise RuntimeError("pl_sc_mart: unexpected empty activities")

    log_start = {
        "name": "log_start",
        "type": "SqlServerStoredProcedure",
        "dependsOn": [],
        "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
        "typeProperties": {
            "storedProcedureName": "[Meta].[usp_LogPipelineRun]",
            "storedProcedureParameters": {
                "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                "pipeline_name": {"value": "pl_sc_mart", "type": "String"},
                "status": {"value": "running", "type": "String"},
                "project": {"value": {"value": "@pipeline().parameters.project_name", "type": "Expression"}, "type": "String"},
            },
        },
        "linkedService": _ls_wh_processing(),
    }

    log_success = {
        "name": "log_success",
        "type": "SqlServerStoredProcedure",
        "dependsOn": [{"activity": "invoke_gold", "dependencyConditions": ["Succeeded"]}],
        "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
        "typeProperties": {
            "storedProcedureName": "[Meta].[usp_LogPipelineRun]",
            "storedProcedureParameters": {
                "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                "pipeline_name": {"value": "pl_sc_mart", "type": "String"},
                "status": {"value": "success", "type": "String"},
                "project": {"value": {"value": "@pipeline().parameters.project_name", "type": "Expression"}, "type": "String"},
            },
        },
        "linkedService": _ls_wh_processing(),
    }

    def fail_activity(dep: str, msg: str, name: str) -> dict[str, Any]:
        return {
            "name": name,
            "type": "SqlServerStoredProcedure",
            "dependsOn": [{"activity": dep, "dependencyConditions": ["Failed"]}],
            "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
            "typeProperties": {
                "storedProcedureName": "[Meta].[usp_LogPipelineRun]",
                "storedProcedureParameters": {
                    "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                    "pipeline_name": {"value": "pl_sc_mart", "type": "String"},
                    "status": {"value": "failed", "type": "String"},
                    "notes": {"value": msg, "type": "String"},
                    "project": {"value": {"value": "@pipeline().parameters.project_name", "type": "Expression"}, "type": "String"},
                },
            },
            "linkedService": _ls_wh_processing(),
        }

    log_failed_staging = fail_activity("invoke_staging", "invoke_staging failed", "log_failed_staging")
    log_failed_silver = fail_activity("invoke_silver", "invoke_silver failed", "log_failed_silver")
    log_failed_gold = fail_activity("invoke_gold", "invoke_gold failed", "log_failed_gold")

    # Make invoke_staging depend on log_start.
    for a in activities:
        if a.get("name") == "invoke_staging":
            a["dependsOn"] = [{"activity": "log_start", "dependencyConditions": ["Succeeded"]}]

    content["properties"]["activities"] = [log_start] + activities + [
        log_success,
        log_failed_staging,
        log_failed_silver,
        log_failed_gold,
    ]

    definition["definition"]["parts"] = [encode_pipeline_content(part, content)]
    return definition, True


def patch_pl_sc_silver_wave(definition: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    part, content = decode_pipeline_content(definition)

    act = next(a for a in content["properties"]["activities"] if a.get("name") == "lk_wave_sps")
    src = act["typeProperties"]["source"]
    query_expr = src.get("sqlReaderQuery")
    if not isinstance(query_expr, dict) or query_expr.get("type") != "Expression":
        raise RuntimeError("pl_sc_silver_wave: unexpected lk_wave_sps.sqlReaderQuery shape")

    old = query_expr["value"]
    if "SilverDagWaveRuntime" not in old:
        raise RuntimeError("pl_sc_silver_wave: expected SilverDagWaveRuntime in query expression")

    due_pred = "(r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())"
    if "ufn_should_run" in old:
        new = old.replace(
            "SupplyChain_Processing_Warehouse.Meta.ufn_should_run(w.asset_id) = 1",
            due_pred,
        )
        if new == old:
            return definition, False
        query_expr["value"] = new
        definition["definition"]["parts"] = [encode_pipeline_content(part, content)]
        return definition, True

    if "next_run_time" in old:
        return definition, False

    new = old.replace(
        "AND w.is_active = 1 AND r.is_active = 1",
        f"AND w.is_active = 1 AND r.is_active = 1 AND {due_pred}",
    )
    if new == old:
        return definition, False
    query_expr["value"] = new

    definition["definition"]["parts"] = [encode_pipeline_content(part, content)]
    return definition, True


def patch_pl_sc_gold(definition: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    part, content = decode_pipeline_content(definition)
    raw = json.dumps(content)
    changed = False

    # Patch lk_gold query to add due gate
    lk_gold = next(a for a in content["properties"]["activities"] if a.get("name") == "lk_gold")
    query = lk_gold["typeProperties"]["source"]["sqlReaderQuery"]
    if "ufn_should_run" in query:
        query2 = query.replace(
            "SupplyChain_Processing_Warehouse.Meta.ufn_should_run(r.asset_id) = 1",
            "(r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())",
        )
        if query2 != query:
            lk_gold["typeProperties"]["source"]["sqlReaderQuery"] = query2
            changed = True
        query = lk_gold["typeProperties"]["source"]["sqlReaderQuery"]

    if "ufn_should_run" not in query and "next_run_time" not in query:
        if "WHERE r.canonical_layer = 'Gold'" not in query:
            raise RuntimeError("pl_sc_gold: unexpected lk_gold.sqlReaderQuery")
        query = query.replace(
            "WHERE r.canonical_layer = 'Gold' AND r.is_active = 1",
            "WHERE r.canonical_layer = 'Gold' AND r.is_active = 1 AND (r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())",
        )
        lk_gold["typeProperties"]["source"]["sqlReaderQuery"] = query
        changed = True

    # Patch fe_gold inner activities to add per-table logging via Meta.usp_LogRun (processing WH)
    fe_gold = next(a for a in content["properties"]["activities"] if a.get("name") == "fe_gold")
    inner = fe_gold["typeProperties"]["activities"]
    if not isinstance(inner, list) or not inner:
        raise RuntimeError("pl_sc_gold: unexpected empty fe_gold activities")

    if "usp_LogRun" not in raw:
        exec_gold = next(a for a in inner if a.get("name") == "exec_gold")
        # Ensure exec_gold depends on log_start
        exec_gold["dependsOn"] = [{"activity": "log_gold_start", "dependencyConditions": ["Succeeded"]}]

        run_id_expr = {
            "value": "@concat('gld::', pipeline().RunId, '::', item().physical_schema, '.', item().physical_object)",
            "type": "Expression",
        }
        asset_id_expr = {"value": "@concat(item().physical_schema, '.', item().physical_object)", "type": "Expression"}
        project_expr = {"value": "@pipeline().parameters.project_name", "type": "Expression"}

        log_gold_start = {
            "name": "log_gold_start",
            "type": "SqlServerStoredProcedure",
            "dependsOn": [],
            "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
            "typeProperties": {
                "storedProcedureName": "[Meta].[usp_LogRun]",
                "storedProcedureParameters": {
                    "run_id": {"value": run_id_expr, "type": "String"},
                    "asset_id": {"value": asset_id_expr, "type": "String"},
                    "status": {"value": "running", "type": "String"},
                    "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                    "error_message": {"value": {"value": "@concat('project=', ", "type": "Expression"}, "type": "String"},
                },
            },
            "linkedService": _ls_wh_processing(),
        }
        # Remove the accidental error_message expression stub if present (keep minimal required params).
        log_gold_start["typeProperties"]["storedProcedureParameters"].pop("error_message", None)

        log_gold_success = {
            "name": "log_gold_success",
            "type": "SqlServerStoredProcedure",
            "dependsOn": [{"activity": "exec_gold", "dependencyConditions": ["Succeeded"]}],
            "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
            "typeProperties": {
                "storedProcedureName": "[Meta].[usp_LogRun]",
                "storedProcedureParameters": {
                    "run_id": {"value": run_id_expr, "type": "String"},
                    "asset_id": {"value": asset_id_expr, "type": "String"},
                    "status": {"value": "success", "type": "String"},
                    "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                    "error_message": {"value": {"value": "@concat('project=', ", "type": "Expression"}, "type": "String"},
                },
            },
            "linkedService": _ls_wh_processing(),
        }
        log_gold_success["typeProperties"]["storedProcedureParameters"].pop("error_message", None)

        log_gold_failed = {
            "name": "log_gold_failed",
            "type": "SqlServerStoredProcedure",
            "dependsOn": [{"activity": "exec_gold", "dependencyConditions": ["Failed"]}],
            "policy": {"timeout": "0.01:00:00", "retry": 0, "retryIntervalInSeconds": 60, "secureOutput": False, "secureInput": False},
            "typeProperties": {
                "storedProcedureName": "[Meta].[usp_LogRun]",
                "storedProcedureParameters": {
                    "run_id": {"value": run_id_expr, "type": "String"},
                    "asset_id": {"value": asset_id_expr, "type": "String"},
                    "status": {"value": "failed", "type": "String"},
                    "pipeline_run_id": {"value": {"value": "@pipeline().RunId", "type": "Expression"}, "type": "String"},
                    "error_message": {"value": "gold CTAS failed", "type": "String"},
                },
            },
            "linkedService": _ls_wh_processing(),
        }

        fe_gold["typeProperties"]["activities"] = [log_gold_start, exec_gold, log_gold_success, log_gold_failed]
        changed = True

    definition["definition"]["parts"] = [encode_pipeline_content(part, content)]
    return definition, changed


def apply_pipeline_patch(output_dir: pathlib.Path, name: str, patcher, *, dry_run: bool) -> bool:
    pid = PIPELINES[name]
    definition = get_pipeline_definition(pid)
    patched, changed = patcher(definition)
    if not changed:
        write_json(output_dir / "pipeline_patch" / f"{name}_skipped.json", {"reason": "already patched"})
        return False
    write_json(output_dir / "pipeline_patch" / f"{name}_updateDefinition_body.json", {"definition": patched["definition"]})
    if dry_run:
        write_json(output_dir / "pipeline_patch" / f"{name}_dry_run.json", {"dry_run": True})
        return True
    update_pipeline_definition(pid, patched)
    return True


def run_healthcheck(output_dir: pathlib.Path) -> dict[str, Any]:
    raw = run(["python3", "Enterprise_SupplyChain_Dev_architect/05_tools/healthcheck_v10_control_plane.py", "--json"])
    payload = json.loads(raw)
    write_json(output_dir / "healthcheck.json", payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--tabledict-only", action="store_true")
    parser.add_argument("--pipelines-dry-run", action="store_true")
    parser.add_argument("--pipelines-only", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    output_dir = build_output_dir(root)

    with sql_conn() as conn:
        snapshot_sql_objects(conn, output_dir)
        snapshot_control_plane_tables(conn, output_dir)
        snapshot_pipelines(output_dir, "before")

        td: dict[str, Any] = {"failed_count": 0, "skipped_missing_mapping_count": 0}

        if not args.verify_only and not args.tabledict_only and not args.pipelines_only:
            ensure_cron_next_run_time_fn(conn)
            alter_ufn_should_run(conn)
            alter_usp_logrun_next_runtime(conn)
            td = backfill_table_dictionary(conn, output_dir)
            execute_sql(conn, "EXEC Meta.usp_BuildLineage;")

        if not args.verify_only and args.tabledict_only:
            td = backfill_table_dictionary(conn, output_dir)

        # Pipeline patches (Fabric)
        if (
            not args.verify_only
            and not args.tabledict_only
            and not args.pipelines_only
            and td.get("failed_count", 0) == 0
            and td.get("skipped_missing_mapping_count", 0) == 0
        ):
            apply_pipeline_patch(output_dir, "pl_sc_mart", patch_pl_sc_mart, dry_run=args.pipelines_dry_run)
            apply_pipeline_patch(output_dir, "pl_sc_silver_wave", patch_pl_sc_silver_wave, dry_run=args.pipelines_dry_run)
            apply_pipeline_patch(output_dir, "pl_sc_gold", patch_pl_sc_gold, dry_run=args.pipelines_dry_run)
        elif not args.verify_only and args.pipelines_only:
            apply_pipeline_patch(output_dir, "pl_sc_mart", patch_pl_sc_mart, dry_run=args.pipelines_dry_run)
            apply_pipeline_patch(output_dir, "pl_sc_silver_wave", patch_pl_sc_silver_wave, dry_run=args.pipelines_dry_run)
            apply_pipeline_patch(output_dir, "pl_sc_gold", patch_pl_sc_gold, dry_run=args.pipelines_dry_run)
        elif not args.verify_only:
            write_json(
                output_dir / "pipeline_patch" / "skipped_due_to_tabledict.json",
                {
                    "reason": "tabledict backfill had failures or skipped assets with missing mapping",
                    "tabledict": td,
                },
            )

        snapshot_pipelines(output_dir, "after")

    hc = run_healthcheck(output_dir)
    print(json.dumps({"output_dir": str(output_dir), "healthcheck_ok": hc.get("ok"), "healthcheck": hc}, indent=2))
    return 0 if hc.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
