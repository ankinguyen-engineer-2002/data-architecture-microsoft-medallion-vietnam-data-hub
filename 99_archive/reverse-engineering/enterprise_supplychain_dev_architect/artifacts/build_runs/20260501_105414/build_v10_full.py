#!/usr/bin/env python3
"""Build v10 full architecture: functions, working SPs, views, REF tables, data load.

Phases:
  2: Functions + working SPs in Processing Warehouse
  3: ReferenceMaster tables + source access views
  4: Silver transformation views
  5: Update registry + load Staging/REF
  6: Load Silver via DAG waves
  7: Gold Warehouse views + SP + load
"""
from __future__ import annotations
import json, struct, subprocess, time, sys, traceback
from datetime import datetime, timezone
from pathlib import Path

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
PROCESSING_DB = "SupplyChain_Processing_Warehouse"
GOLD_DB = "SupplyChain_Gold_Warehouse"
OUT_DIR = Path("Enterprise_SupplyChain_Dev_architect/build_runs/20260501_105414")

def get_token():
    raw = subprocess.run(["az","account","get-access-token","--resource","https://database.windows.net/","--output","json"], check=True, capture_output=True, text=True)
    token = json.loads(raw.stdout)["accessToken"].encode("UTF-16-LE")
    return struct.pack(f"<I{len(token)}s", len(token), token)

def connect(db):
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={db};Encrypt=yes;TrustServerCertificate=no",
        attrs_before={1256: get_token()}, timeout=60, autocommit=True
    )

def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]

def exe(cur, sql, label=""):
    try:
        cur.execute(sql)
        return {"status": "ok", "label": label}
    except Exception as e:
        return {"status": "error", "label": label, "error": str(e)}

def drop_if_exists(cur, schema, name, obj_type="PROCEDURE"):
    """Drop object if exists. obj_type: PROCEDURE, VIEW, FUNCTION"""
    type_map = {"PROCEDURE": "procedures", "VIEW": "views", "FUNCTION": "objects"}
    check_map = {"PROCEDURE": "p", "VIEW": "v", "FUNCTION": "o"}
    alias = check_map[obj_type]
    if obj_type == "FUNCTION":
        cnt = scalar(cur, f"SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON o.schema_id=s.schema_id WHERE s.name=? AND o.name=? AND o.type IN ('FN','IF','TF')", (schema, name))
    elif obj_type == "PROCEDURE":
        cnt = scalar(cur, f"SELECT COUNT(*) FROM sys.procedures p JOIN sys.schemas s ON p.schema_id=s.schema_id WHERE s.name=? AND p.name=?", (schema, name))
    else:
        cnt = scalar(cur, f"SELECT COUNT(*) FROM sys.views v JOIN sys.schemas s ON v.schema_id=s.schema_id WHERE s.name=? AND v.name=?", (schema, name))
    if cnt > 0:
        cur.execute(f"DROP {obj_type} [{schema}].[{name}]")
        return True
    return False

# ═══════════════════════════════════════════════════════════════════
# PHASE 2: Functions + Working SPs
# ═══════════════════════════════════════════════════════════════════

FUNCTIONS = {
    "Meta.ufn_utc_to_cst": """
CREATE FUNCTION Meta.ufn_utc_to_cst(@dt DATETIME2(6))
RETURNS DATETIME2(6)
AS
BEGIN
    RETURN DATEADD(HOUR,
        CASE
            WHEN @dt >= CAST(DATEADD(DAY, (8 - DATEPART(WEEKDAY, DATEFROMPARTS(YEAR(@dt),3,1))) % 7 + 7, DATEFROMPARTS(YEAR(@dt),3,1)) AS DATETIME2(6))
             AND @dt < CAST(DATEADD(DAY, (8 - DATEPART(WEEKDAY, DATEFROMPARTS(YEAR(@dt),11,1))) % 7, DATEFROMPARTS(YEAR(@dt),11,1)) AS DATETIME2(6))
            THEN -5
            ELSE -6
        END, @dt)
END
""",
    "Meta.ufn_should_run": """
CREATE FUNCTION Meta.ufn_should_run(@asset_id VARCHAR(128))
RETURNS INT
AS
BEGIN
    DECLARE @result INT = 0;
    SELECT @result = CASE
        WHEN is_active = 0 THEN 0
        WHEN next_run_time IS NULL THEN 1
        WHEN next_run_time <= GETUTCDATE() THEN 1
        ELSE 0
    END
    FROM Meta.AssetRegistryV10 WHERE asset_id = @asset_id;
    RETURN ISNULL(@result, 0);
END
""",
    "Meta.ufn_cron_is_due": """
CREATE FUNCTION Meta.ufn_cron_is_due(@cron VARCHAR(100))
RETURNS INT
AS
BEGIN
    IF @cron IS NULL OR @cron = '' RETURN 1
    DECLARE @now DATETIME2(6) = GETUTCDATE()
    DECLARE @minute INT = DATEPART(MINUTE, @now), @hour INT = DATEPART(HOUR, @now)
    DECLARE @day INT = DATEPART(DAY, @now), @month INT = DATEPART(MONTH, @now)
    DECLARE @dow INT = (DATEPART(WEEKDAY, @now) + 5) % 7
    DECLARE @f1 VARCHAR(20), @f2 VARCHAR(20), @f3 VARCHAR(20), @f4 VARCHAR(20), @f5 VARCHAR(20)
    DECLARE @parts VARCHAR(100) = LTRIM(RTRIM(@cron))
    SET @f1 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f1) + 2, 100))
    SET @f2 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f2) + 2, 100))
    SET @f3 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f3) + 2, 100))
    SET @f4 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    SET @parts = LTRIM(SUBSTRING(@parts, LEN(@f4) + 2, 100))
    SET @f5 = LEFT(@parts, CHARINDEX(' ', @parts + ' ') - 1)
    DECLARE @m1 INT=0, @m2 INT=0, @m3 INT=0, @m4 INT=0, @m5 INT=0
    IF @f1='*' SET @m1=1 ELSE IF CAST(@f1 AS INT)=@minute SET @m1=1
    IF @f2='*' SET @m2=1 ELSE IF CAST(@f2 AS INT)=@hour SET @m2=1
    IF @f3='*' SET @m3=1 ELSE IF @f3 LIKE '*/%' BEGIN IF @day % CAST(SUBSTRING(@f3,3,10) AS INT)=0 SET @m3=1 END ELSE IF CAST(@f3 AS INT)=@day SET @m3=1
    IF @f4='*' SET @m4=1 ELSE IF CAST(@f4 AS INT)=@month SET @m4=1
    IF @f5='*' SET @m5=1 ELSE IF CAST(@f5 AS INT)=@dow SET @m5=1
    IF @m1=1 AND @m2=1 AND @m3=1 AND @m4=1 AND @m5=1 RETURN 1
    RETURN 0
END
""",
}

# Working SPs - adapted from v9 to use v10 AssetRegistryV10
WORKING_SPS = {
    # ── usp_LogRun: log start/end of each table load ──
    "Meta.usp_LogRun": """
CREATE PROCEDURE Meta.usp_LogRun
    @run_id VARCHAR(128), @asset_id VARCHAR(128), @status VARCHAR(80),
    @rows_loaded BIGINT = NULL, @error_message VARCHAR(4000) = NULL, @load_type VARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);
    DECLARE @retry INT = 0, @done INT = 0;
    WHILE @retry < 3 AND @done = 0
    BEGIN
        BEGIN TRY
            IF @status = 'running'
            BEGIN
                INSERT INTO Meta.RunLog (run_id, asset_id, object_name, layer_name, status, start_time_utc, start_time_cst, load_type)
                SELECT @run_id, @asset_id, CONCAT(physical_schema,'.',physical_object), canonical_layer, 'running', @now, @now_cst, COALESCE(@load_type, load_type)
                FROM Meta.AssetRegistryV10 WHERE asset_id = @asset_id;
            END
            ELSE
            BEGIN
                UPDATE Meta.RunLog SET end_time_utc=@now, end_time_cst=@now_cst, duration_seconds=DATEDIFF(SECOND, start_time_utc, @now), rows_loaded=@rows_loaded, status=@status, error_message=@error_message WHERE run_id=@run_id;
                UPDATE Meta.AssetRegistryV10 SET last_load_date=@now, rows_loaded=@rows_loaded,
                    next_run_time = CASE WHEN frequency='daily' THEN DATEADD(DAY,1,CAST(@now AS DATE)) WHEN frequency='hourly' THEN DATEADD(HOUR,1,@now) WHEN frequency='weekly' THEN DATEADD(WEEK,1,CAST(@now AS DATE)) WHEN frequency='monthly' THEN DATEADD(MONTH,1,CAST(@now AS DATE)) ELSE DATEADD(DAY,1,CAST(@now AS DATE)) END
                WHERE asset_id = @asset_id;
            END
            SET @done = 1;
        END TRY
        BEGIN CATCH
            SET @retry = @retry + 1;
            IF @retry >= 3 RAISERROR('usp_LogRun failed after 3 retries: %s', 10, 1, 'retry exhausted');
            WAITFOR DELAY '00:00:02';
        END CATCH
    END
END
""",

    # ── usp_GenericLoad: actual working data loader ──
    "Meta.usp_GenericLoad": """
CREATE PROCEDURE Meta.usp_GenericLoad
    @target_schema VARCHAR(128), @target_table VARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id VARCHAR(128) = CONVERT(VARCHAR(36), NEWID());
    DECLARE @asset_id VARCHAR(128), @view_name NVARCHAR(512), @load_type VARCHAR(80);
    DECLARE @wm_col NVARCHAR(256), @pk_col NVARCHAR(1000), @last_wm VARCHAR(1000);
    DECLARE @dt_key NVARCHAR(128), @dt_range_days INT;
    DECLARE @rows BIGINT, @sql NVARCHAR(4000), @full_target NVARCHAR(500);
    DECLARE @new_wm VARCHAR(200), @err VARCHAR(4000);

    -- Read config from v10 registry (match by physical_schema + physical_object)
    SELECT @asset_id=asset_id, @view_name=legacy_view_name, @load_type=load_type,
           @wm_col=watermark_column, @pk_col=primary_key, @last_wm=last_watermark_value,
           @dt_key=date_key, @dt_range_days=date_range_days
    FROM Meta.AssetRegistryV10
    WHERE physical_schema=@target_schema AND physical_object=@target_table;

    IF @asset_id IS NULL BEGIN RAISERROR('Table %s.%s not found in registry',16,1,@target_schema,@target_table); RETURN; END
    SET @full_target = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    EXEC Meta.usp_LogRun @run_id, @asset_id, 'running', @load_type=@load_type;

    BEGIN TRY
        DECLARE @tbl_exists INT = 0;
        EXEC sp_executesql N'SELECT @out=COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name=@s AND t.name=@t',
            N'@s VARCHAR(128),@t VARCHAR(256),@out INT OUT', @s=@target_schema,@t=@target_table,@out=@tbl_exists OUT;

        IF @load_type = 'overwrite'
        BEGIN
            IF @view_name IS NULL BEGIN RAISERROR('overwrite requires view_name',16,1); RETURN; END
            SET @sql = N'DROP TABLE IF EXISTS ' + @full_target; EXEC sp_executesql @sql;
            SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
        END
        ELSE IF @load_type = 'incremental'
        BEGIN
            IF @tbl_exists = 0 OR @last_wm IS NULL
            BEGIN
                SET @sql = N'DROP TABLE IF EXISTS ' + @full_target; EXEC sp_executesql @sql;
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name + N' WHERE ' + QUOTENAME(@wm_col) + N' >= CAST(''2023-01-01'' AS DATETIME2(6))'; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name + N' WHERE ' + QUOTENAME(@wm_col) + N' > CAST(@wm AS DATETIME2(6))';
                EXEC sp_executesql @sql, N'@wm VARCHAR(200)', @wm=@last_wm;
            END
            SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@wm_col) + N') AS VARCHAR(200)) FROM ' + @full_target;
            EXEC sp_executesql @sql, N'@out VARCHAR(200) OUT', @out=@new_wm OUT;
            IF @new_wm IS NOT NULL
                UPDATE Meta.AssetRegistryV10 SET last_watermark_value=@new_wm WHERE asset_id=@asset_id;
        END
        ELSE IF @load_type = 'upsert'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('upsert requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@pk_col) + N' IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N')'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
        END
        ELSE BEGIN RAISERROR('Unsupported load_type: %s',16,1,@load_type); RETURN; END

        SET @sql = N'SELECT @out=COUNT(*) FROM ' + @full_target;
        EXEC sp_executesql @sql, N'@out BIGINT OUT', @out=@rows OUT;
        EXEC Meta.usp_LogRun @run_id, @asset_id, 'success', @rows_loaded=@rows, @load_type=@load_type;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
        EXEC Meta.usp_LogRun @run_id, @asset_id, 'failed', @error_message=@err, @load_type=@load_type;
        THROW;
    END CATCH
END
""",

    # ── usp_RefreshEdwTables: stage 4 EDW supplement tables ──
    "Staging.usp_RefreshEdwTables": """
CREATE PROCEDURE Staging.usp_RefreshEdwTables
AS
BEGIN
    SET NOCOUNT ON;
    -- 1. ProductEdw
    DROP TABLE IF EXISTS Staging.ProductEdw;
    CREATE TABLE Staging.ProductEdw AS SELECT * FROM SupplyChain_Lakehouse.dbo.ref_product_ver2;

    -- 2. InvoiceHeaderEdw
    DROP TABLE IF EXISTS Staging.InvoiceHeaderEdw;
    CREATE TABLE Staging.InvoiceHeaderEdw AS SELECT * FROM SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2;

    -- 3. InvoiceDetailEdw
    DROP TABLE IF EXISTS Staging.InvoiceDetailEdw;
    CREATE TABLE Staging.InvoiceDetailEdw AS SELECT * FROM SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2;

    -- 4. DemandForecastSnapshotDailyEdw (exclude fiscal_month_last_date)
    DROP TABLE IF EXISTS Staging.DemandForecastSnapshotDailyEdw;
    CREATE TABLE Staging.DemandForecastSnapshotDailyEdw AS
    SELECT id_item_sku, code_warehouse, num_fiscal_month, code_customer_group,
        qty_resultant_forecast, qty_promotional_lift, qty_forced_forecast,
        qty_order_future, qty_perm_component, ts_snapshot,
        code_main_piece, name_collective_class, name_product_category,
        code_forecast_type, code_management, id_derived_forecast,
        val_derived_forecast_factor, num_valid_demand_months, name_usr25,
        name_created_by, ts_created, name_modified_by, ts_modified
    FROM SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2;
END
""",

    # ── usp_LogPipelineRun ──
    "Meta.usp_LogPipelineRun": """
CREATE PROCEDURE Meta.usp_LogPipelineRun
    @pipeline_run_id VARCHAR(128), @pipeline_name VARCHAR(256), @status VARCHAR(80),
    @tables_succeeded INT = NULL, @tables_failed INT = NULL, @notes VARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);
    IF @status = 'running'
        INSERT INTO Meta.PipelineRunLog (pipeline_run_id, pipeline_name, status, start_time_utc, trigger_type)
        VALUES (@pipeline_run_id, @pipeline_name, 'running', @now, 'Manual');
    ELSE
        UPDATE Meta.PipelineRunLog SET status=@status, end_time_utc=@now, error_message=@notes WHERE pipeline_run_id=@pipeline_run_id;
END
""",

    # ── usp_BuildLineage: rebuild lineage from source_objects ──
    "Meta.usp_BuildLineage": """
CREATE PROCEDURE Meta.usp_BuildLineage
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Meta.LineageEdge;
    INSERT INTO Meta.LineageEdge (edge_id, source_asset, target_asset, edge_type, transform_type, is_synthetic, created_at_utc)
    SELECT
        CONCAT('lineage::', ROW_NUMBER() OVER (ORDER BY r.asset_id, src.value)),
        TRIM(REPLACE(REPLACE(src.value, '"', ''), '''', '')),
        r.asset_id, 'direct', r.load_type, 0, SYSUTCDATETIME()
    FROM Meta.AssetRegistryV10 r
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(r.source_objects, '[', ''), ']', ''), ',') src
    WHERE r.source_objects IS NOT NULL AND LEN(TRIM(src.value)) > 0;
END
""",

    # ── usp_FinalizePipeline ──
    "Meta.usp_FinalizePipeline": """
CREATE PROCEDURE Meta.usp_FinalizePipeline @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC Meta.usp_BuildLineage;
    DECLARE @succeeded INT=0, @failed INT=0;
    SELECT @succeeded=COUNT(*) FROM Meta.RunLog WHERE status='success' AND start_time_utc >= DATEADD(MINUTE,-60,GETUTCDATE());
    SELECT @failed=COUNT(*) FROM Meta.RunLog WHERE status='failed' AND start_time_utc >= DATEADD(MINUTE,-60,GETUTCDATE());
    IF @pipeline_run_id IS NOT NULL
        UPDATE Meta.PipelineRunLog SET status=CASE WHEN @failed>0 THEN 'partial' ELSE 'success' END, end_time_utc=CAST(GETUTCDATE() AS DATETIME2(6)),
            error_message=CAST(@succeeded AS VARCHAR)+' succeeded, '+CAST(@failed AS VARCHAR)+' failed'
        WHERE pipeline_run_id=@pipeline_run_id;
END
""",

    # ── usp_CheckDqSingle: run single DQ rule (same v9 pattern) ──
    "Meta.usp_CheckDqSingle": """
CREATE PROCEDURE Meta.usp_CheckDqSingle @rule_id INT, @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rule_name VARCHAR(200), @target_schema VARCHAR(50), @target_table VARCHAR(200);
    DECLARE @check_type VARCHAR(30), @column_name VARCHAR(100), @severity VARCHAR(10);
    DECLARE @threshold DECIMAL(18,2), @layer VARCHAR(10);

    SELECT @rule_name=rule_name, @target_schema=target_schema, @target_table=target_table,
           @check_type=check_type, @column_name=column_name, @severity=severity,
           @threshold=threshold, @layer=layer
    FROM Meta.DQRule WHERE rule_id=@rule_id AND is_active=1;
    IF @rule_name IS NULL RETURN;

    DECLARE @sql NVARCHAR(4000), @actual VARCHAR(500), @expected VARCHAR(500);
    DECLARE @val DECIMAL(18,4), @status VARCHAR(10);
    DECLARE @tgt NVARCHAR(500) = QUOTENAME(@target_schema)+N'.'+QUOTENAME(@target_table);

    BEGIN TRY
        IF @check_type='completeness'
        BEGIN
            SET @sql=N'SELECT @v=CAST(SUM(CASE WHEN '+QUOTENAME(@column_name)+N' IS NULL THEN 0 ELSE 1 END)*100.0/NULLIF(COUNT(*),0) AS DECIMAL(18,4)) FROM '+@tgt;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUT', @v=@val OUT;
            SET @actual=CAST(@val AS VARCHAR(50)); SET @expected=CAST(ISNULL(@threshold,100.0) AS VARCHAR(50));
            SET @status=CASE WHEN @val>=ISNULL(@threshold,100.0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type='row_count'
        BEGIN
            SET @sql=N'SELECT @v=CAST(COUNT(*) AS DECIMAL(18,4)) FROM '+@tgt;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUT', @v=@val OUT;
            SET @actual=CAST(CAST(@val AS BIGINT) AS VARCHAR(50)); SET @expected=CAST(@threshold AS VARCHAR(50));
            SET @status=CASE WHEN @val>=ISNULL(@threshold,0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type='uniqueness'
        BEGIN
            SET @sql=N'SELECT @v=CAST(COUNT(*)-COUNT(DISTINCT '+QUOTENAME(@column_name)+N') AS DECIMAL(18,4)) FROM '+@tgt;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUT', @v=@val OUT;
            SET @actual=CAST(CAST(@val AS BIGINT) AS VARCHAR(50)); SET @expected='0';
            SET @status=CASE WHEN @val=0 THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type='freshness'
        BEGIN
            SET @sql=N'SELECT @v=CAST(DATEDIFF(HOUR,MAX(_load_dt),CAST(GETUTCDATE() AS DATETIME2(6))) AS DECIMAL(18,4)) FROM '+@tgt;
            EXEC sp_executesql @sql, N'@v DECIMAL(18,4) OUT', @v=@val OUT;
            SET @actual=CAST(CAST(@val AS INT) AS VARCHAR(50))+' hours'; SET @expected='<= '+CAST(@threshold AS VARCHAR(50))+' hours';
            SET @status=CASE WHEN @val<=ISNULL(@threshold,24) THEN 'PASS' ELSE 'FAIL' END;
        END

        DECLARE @wa INT=0, @wd INT=0;
        WHILE @wa<3 AND @wd=0
        BEGIN
            BEGIN TRY
                DELETE FROM Meta.DQGateRun WHERE dq_gate_run_id=CONCAT('dqr::',@rule_id);
                INSERT INTO Meta.DQGateRun (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message)
                VALUES (CONCAT('dqr::',@rule_id), @target_schema+'.'+@target_table, @pipeline_run_id, @check_type, @status, CAST(GETUTCDATE() AS DATETIME2(6)), CASE WHEN @status='FAIL' THEN 1 ELSE 0 END, @actual+' vs '+@expected);
                SET @wd=1;
            END TRY
            BEGIN CATCH SET @wa=@wa+1; IF @wa<3 WAITFOR DELAY '00:00:02'; END CATCH
        END

        IF @status='FAIL' AND @severity='CRITICAL'
        BEGIN
            DECLARE @msg NVARCHAR(500) = N'DQ CRITICAL FAIL: '+CAST(@rule_name AS NVARCHAR(200))+N' | actual='+ISNULL(CAST(@actual AS NVARCHAR(100)),N'NULL');
            THROW 50001, @msg, 1;
        END
    END TRY
    BEGIN CATCH
        IF @severity='CRITICAL' THROW;
    END CATCH
END
""",
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 3: ReferenceMaster tables + Source Access Views
# ═══════════════════════════════════════════════════════════════════

# REF table → Enterprise_Lakehouse source
REF_VIEW_MAP = {
    "ReferenceMaster.vw_Calendar": """
CREATE VIEW ReferenceMaster.vw_Calendar AS
SELECT
    CAST(DateKey AS INT) AS sk_date, CAST(MapicsDate AS INT) AS id_mapics_date,
    CAST(DateID AS DATE) AS dt_date, CAST(DateTimeID AS DATE) AS dt_datetime,
    CAST(CalendarDate AS DATE) AS dt_calendar, TRIM(CalendarDateName) AS name_calendar_date,
    CAST(CalendarDayOfWeek AS INT) AS num_cal_day_of_week, TRIM(CalendarDayOfWeekName) AS name_cal_day_of_week,
    CAST(CalendarDayOfMonth AS INT) AS num_cal_day_of_month, CAST(CalendarDayOfYear AS INT) AS num_cal_day_of_year,
    CAST(CalendarWeek AS INT) AS num_cal_week, CAST(CalendarWeekYear AS INT) AS num_cal_week_year,
    TRIM(CalendarWeekYearName) AS name_cal_week_year,
    CAST(CalendarWeekFirstDate AS DATE) AS dt_cal_week_first, CAST(CalendarWeekLastDate AS DATE) AS dt_cal_week_last,
    CAST(CalendarMonth AS INT) AS num_cal_month, CAST(CalendarMonthYear AS INT) AS num_cal_month_year,
    TRIM(CalendarMonthName) AS name_cal_month, TRIM(CalendarMonthYearName) AS name_cal_month_year,
    CAST(CalendarMonthFirstDate AS DATE) AS dt_cal_month_first, CAST(CalendarMonthLastDate AS DATE) AS dt_cal_month_last,
    CAST(CalendarQuarter AS INT) AS num_cal_quarter, TRIM(CalendarQuarterName) AS name_cal_quarter,
    CAST(CalendarYear AS INT) AS num_cal_year, TRIM(CalendarYearName) AS name_cal_year,
    CAST(FiscalMonth AS INT) AS num_fsc_month, CAST(FiscalMonthYear AS INT) AS num_fsc_month_year,
    TRIM(FiscalMonthName) AS name_fsc_month, TRIM(FiscalMonthYearName) AS name_fsc_month_year,
    CAST(FiscalMonthFirstDate AS DATE) AS dt_fsc_month_first, CAST(FiscalMonthLastDate AS DATE) AS dt_fsc_month_last,
    CAST(FiscalQuarter AS INT) AS num_fsc_quarter, TRIM(FiscalQuarterName) AS name_fsc_quarter,
    CAST(FiscalQuarterYear AS INT) AS num_fsc_quarter_year, TRIM(FiscalQuarterYearName) AS name_fsc_quarter_year,
    CAST(FiscalYear AS INT) AS num_fsc_year, TRIM(FiscalYearName) AS name_fsc_year,
    CAST(FiscalWeek AS INT) AS num_fsc_week, CAST(FiscalWeekYear AS INT) AS num_fsc_week_year,
    CAST(FiscalWeekFirstDate AS DATE) AS dt_fsc_week_first, CAST(FiscalWeekLastDate AS DATE) AS dt_fsc_week_last,
    TRIM(HolidayIndicator) AS code_holiday_indicator, TRIM(HolidayName) AS name_holiday,
    TRIM(WorkingDayIndicator) AS code_working_day, TRIM(WeekdayWeekend) AS code_weekday_weekend
FROM Enterprise_Lakehouse.MasterData_DW.DimDate WHERE DateKey IS NOT NULL
""",
    "ReferenceMaster.vw_CustomerAccount": "CREATE VIEW ReferenceMaster.vw_CustomerAccount AS SELECT * FROM Enterprise_Lakehouse.Customers.AccountMaster",
    "ReferenceMaster.vw_CustomerAccountGroup": "CREATE VIEW ReferenceMaster.vw_CustomerAccountGroup AS SELECT * FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping",
    "ReferenceMaster.vw_CustomerGrouping": """
CREATE VIEW ReferenceMaster.vw_CustomerGrouping AS
SELECT DISTINCT UPPER(TRIM(CustomerGroupCode)) AS code_customer_group, TRIM(AccountNumber) AS id_customer
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping WHERE CustomerGroupCode IS NOT NULL
""",
    "ReferenceMaster.vw_CustomerShippingLocation": "CREATE VIEW ReferenceMaster.vw_CustomerShippingLocation AS SELECT * FROM Enterprise_Lakehouse.Customers.ShippingLocations",
    "ReferenceMaster.vw_ForecastCycle": "CREATE VIEW ReferenceMaster.vw_ForecastCycle AS SELECT * FROM SupplyChain_Lakehouse.dbo.ref_forecast_cycle",
    "ReferenceMaster.vw_ForecastHorizon": """
CREATE VIEW ReferenceMaster.vw_ForecastHorizon AS
SELECT 'Lag-0' AS code_horizon UNION ALL SELECT 'Lag-1' UNION ALL SELECT 'Lag-2'
UNION ALL SELECT 'Lag-3' UNION ALL SELECT 'Lag-4' UNION ALL SELECT '>Lag-4'
UNION ALL SELECT 'Actual demand' UNION ALL SELECT 'Naive forecast'
""",
    "ReferenceMaster.vw_ItemMaster": "CREATE VIEW ReferenceMaster.vw_ItemMaster AS SELECT * FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster",
    "ReferenceMaster.vw_OrderType": "CREATE VIEW ReferenceMaster.vw_OrderType AS SELECT * FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP",
    "ReferenceMaster.vw_Product": "CREATE VIEW ReferenceMaster.vw_Product AS SELECT * FROM Staging.ProductEdw",
    "ReferenceMaster.vw_Warehouse": "CREATE VIEW ReferenceMaster.vw_Warehouse AS SELECT * FROM Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses",
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 4: Silver Transformation Views
# ═══════════════════════════════════════════════════════════════════

SILVER_VIEWS = {
    "SalesHistory.vw_InvoiceDetailLineLevel": """
CREATE VIEW SalesHistory.vw_InvoiceDetailLineLevel AS
SELECT
    INV.id_invoice, INV.id_invoice_extended, INV.id_order, INV.num_item_sequence,
    INV.id_customer, INV.code_ship_to,
    UPPER(RTRIM(CASE WHEN INV.code_ship_to IS NULL OR TRIM(INV.code_ship_to)='' THEN TRIM(INV.id_customer) ELSE CONCAT(TRIM(INV.id_customer),'-',TRIM(INV.code_ship_to)) END)) AS id_account_ship_to,
    INV.id_item_sku, INV.code_warehouse,
    UPPER(CG.code_customer_group) AS code_customer_group,
    IH.num_lead_time_days,
    INV.qty_shipped, INV.qty_ordered, INV.qty_backordered,
    INV.amt_invoice, INV.amt_net_sales, INV.amt_price, INV.amt_standard_price,
    INV.amt_contract_price, INV.amt_discount, INV.amt_price_adjustment, INV.amt_freight,
    INV.dt_invoice, INV.dt_order, INV.dt_request, INV.dt_current_request,
    INV.dt_current_promise, INV.dt_original_request, INV.dt_original_promise,
    INV.dt_promised_delivery, INV.dt_delivery, INV.dt_actual_delivery,
    INV.code_order_type, INV.code_order_type_3, INV.code_credit,
    INV.code_item_class, INV.code_order_item_status
FROM Staging.InvoiceDetailEdw AS INV
LEFT JOIN Staging.InvoiceHeaderEdw AS IH
    ON INV.id_invoice=IH.id_invoice AND INV.dt_invoice=IH.dt_invoice AND INV.dt_order=IH.dt_order AND INV.id_order=IH.id_order
LEFT JOIN ReferenceMaster.CustomerAccountGroup AS CG ON CG.id_customer=INV.id_customer
""",

    "SalesHistory.vw_InvoiceWeekly": """
CREATE VIEW SalesHistory.vw_InvoiceWeekly AS
WITH current_fiscal AS (SELECT TOP 1 num_fsc_year FROM ReferenceMaster.Calendar WHERE dt_date=CAST(GETDATE() AS DATE))
SELECT INV.id_account_ship_to, INV.id_item_sku, INV.code_warehouse, INV.code_customer_group,
    CAL.dt_fsc_week_first, CAL.dt_fsc_week_last,
    SUM(INV.qty_shipped) AS qty_shipped, SUM(INV.amt_net_sales) AS amt_net_sales,
    SUM(INV.amt_invoice) AS amt_invoice, SUM(INV.amt_freight) AS amt_freight,
    COUNT(*) AS num_invoice_lines, COUNT(DISTINCT INV.id_invoice) AS num_distinct_invoices
FROM SalesHistory.InvoiceDetailLineLevel AS INV
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=INV.dt_invoice
CROSS JOIN current_fiscal AS CF
WHERE INV.qty_shipped > 0 AND CAL.num_fsc_year >= CF.num_fsc_year - 3
GROUP BY INV.id_account_ship_to, INV.id_item_sku, INV.code_warehouse, INV.code_customer_group, CAL.dt_fsc_week_first, CAL.dt_fsc_week_last
""",

    "SalesHistory.vw_ActualDemandMonthly": """
CREATE VIEW SalesHistory.vw_ActualDemandMonthly AS
WITH current_fiscal AS (SELECT TOP 1 num_fsc_year FROM ReferenceMaster.Calendar WHERE dt_date=CAST(GETDATE() AS DATE))
SELECT INV.id_item_sku, INV.code_warehouse,
    CASE WHEN CAL.dt_fsc_month_first < '2025-04-01' THEN 'AFICONS' ELSE INV.code_customer_group END AS code_customer_group,
    CAL.dt_fsc_month_first, CAL.dt_fsc_month_last,
    SUM(INV.qty_shipped) AS qty_demand, SUM(INV.amt_net_sales) AS amt_demand,
    'Invoice' AS code_status, 'Actual Demand' AS name_version
FROM SalesHistory.InvoiceDetailLineLevel AS INV
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=DATEADD(DAY,-INV.num_lead_time_days,INV.dt_current_request)
CROSS JOIN current_fiscal AS CF
WHERE INV.qty_shipped > 0 AND CAL.num_fsc_year BETWEEN CF.num_fsc_year-3 AND CF.num_fsc_year+1
GROUP BY INV.id_item_sku, INV.code_warehouse, CASE WHEN CAL.dt_fsc_month_first<'2025-04-01' THEN 'AFICONS' ELSE INV.code_customer_group END, CAL.dt_fsc_month_first, CAL.dt_fsc_month_last
UNION ALL
SELECT OO.id_item_sku, OO.code_warehouse,
    CASE WHEN CAL.dt_fsc_month_first < '2025-04-01' THEN 'AFICONS' ELSE CG.code_customer_group END AS code_customer_group,
    CAL.dt_fsc_month_first, CAL.dt_fsc_month_last,
    SUM(OO.qty_open_order) AS qty_demand, SUM(OO.amt_open_order) AS amt_demand,
    'Open Order' AS code_status, 'Actual Demand' AS name_version
FROM OpenOrderHistory.OpenOrderLineLevel AS OO
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=DATEADD(DAY,-OO.num_lead_time_days,OO.dt_current_request)
LEFT JOIN ReferenceMaster.CustomerAccountGroup AS CG ON CG.id_customer=OO.id_customer
CROSS JOIN current_fiscal AS CF
WHERE OO.code_allocation_flag='2' AND CAL.num_fsc_year BETWEEN CF.num_fsc_year-3 AND CF.num_fsc_year+1
GROUP BY OO.id_item_sku, OO.code_warehouse, CASE WHEN CAL.dt_fsc_month_first<'2025-04-01' THEN 'AFICONS' ELSE CG.code_customer_group END, CAL.dt_fsc_month_first, CAL.dt_fsc_month_last
""",

    "SalesHistory.vw_ActualDemandWeekly": """
CREATE VIEW SalesHistory.vw_ActualDemandWeekly AS
WITH current_fiscal AS (SELECT TOP 1 num_fsc_year FROM ReferenceMaster.Calendar WHERE dt_date=CAST(GETDATE() AS DATE))
SELECT INV.id_item_sku, INV.code_warehouse,
    CASE WHEN CAL.dt_fsc_week_first < '2025-04-01' THEN 'AFICONS' ELSE INV.code_customer_group END AS code_customer_group,
    CAL.dt_fsc_week_first, CAL.dt_fsc_week_last,
    SUM(INV.qty_shipped) AS qty_demand, SUM(INV.amt_net_sales) AS amt_demand,
    'Invoice' AS code_status, 'Actual Demand' AS name_version
FROM SalesHistory.InvoiceDetailLineLevel AS INV
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=DATEADD(DAY,-INV.num_lead_time_days,INV.dt_current_request)
CROSS JOIN current_fiscal AS CF
WHERE INV.qty_shipped > 0 AND CAL.num_fsc_year BETWEEN CF.num_fsc_year-3 AND CF.num_fsc_year+1
GROUP BY INV.id_item_sku, INV.code_warehouse, CASE WHEN CAL.dt_fsc_week_first<'2025-04-01' THEN 'AFICONS' ELSE INV.code_customer_group END, CAL.dt_fsc_week_first, CAL.dt_fsc_week_last
UNION ALL
SELECT OO.id_item_sku, OO.code_warehouse,
    CASE WHEN CAL.dt_fsc_week_first < '2025-04-01' THEN 'AFICONS' ELSE CG.code_customer_group END AS code_customer_group,
    CAL.dt_fsc_week_first, CAL.dt_fsc_week_last,
    SUM(OO.qty_open_order) AS qty_demand, SUM(OO.amt_open_order) AS amt_demand,
    'Open Order' AS code_status, 'Actual Demand' AS name_version
FROM OpenOrderHistory.OpenOrderLineLevel AS OO
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=DATEADD(DAY,-OO.num_lead_time_days,OO.dt_current_request)
LEFT JOIN ReferenceMaster.CustomerAccountGroup AS CG ON CG.id_customer=OO.id_customer
CROSS JOIN current_fiscal AS CF
WHERE OO.code_allocation_flag='2' AND CAL.num_fsc_year BETWEEN CF.num_fsc_year-3 AND CF.num_fsc_year+1
GROUP BY OO.id_item_sku, OO.code_warehouse, CASE WHEN CAL.dt_fsc_week_first<'2025-04-01' THEN 'AFICONS' ELSE CG.code_customer_group END, CAL.dt_fsc_week_first, CAL.dt_fsc_week_last
""",

    "ForecastHistory.vw_ForecastDemandMonthly": """
CREATE VIEW ForecastHistory.vw_ForecastDemandMonthly AS
WITH RawForecast AS (
    SELECT f.id_item_sku, f.code_warehouse, UPPER(f.code_customer_group) AS code_customer_group,
        DATEFROMPARTS(CAST(f.num_fiscal_month/100 AS INT), CAST(f.num_fiscal_month%100 AS INT), 1) AS dt_fiscal_month,
        CAST(f.ts_snapshot AS DATE) AS dt_snapshot, f.qty_resultant_forecast, f.qty_promotional_lift
    FROM Staging.DemandForecastSnapshotDailyEdw AS f
    INNER JOIN ReferenceMaster.ForecastCycle AS c ON CAST(f.ts_snapshot AS DATE)=c.dt_forecast_snapshot
),
CalculatedForecast AS (
    SELECT FC.id_item_sku, FC.code_warehouse, FC.code_customer_group,
        CAL.dt_fsc_month_first, CAL.dt_fsc_month_last, FC.dt_snapshot,
        CASE WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))=0 THEN 'Lag-0'
             WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))=1 THEN 'Lag-1'
             WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))=2 THEN 'Lag-2'
             WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))=3 THEN 'Lag-3'
             WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))=4 THEN 'Lag-4'
             WHEN (YEAR(FC.dt_fiscal_month)*12+MONTH(FC.dt_fiscal_month))-(YEAR(FC.dt_snapshot)*12+MONTH(FC.dt_snapshot))>4 THEN '>Lag-4'
        END AS code_horizon,
        CAST(SUM(FC.qty_resultant_forecast+FC.qty_promotional_lift) AS FLOAT) AS qty_forecast,
        CAST(CONCAT('V ',FORMAT(FC.dt_snapshot,'yyyy.MM')) AS VARCHAR(20)) AS code_version, 'Forecast' AS code_status
    FROM RawForecast AS FC
    INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=FC.dt_fiscal_month
    WHERE FC.dt_fiscal_month >= DATEADD(MONTH,-36,DATETRUNC(YEAR,DATEADD(MONTH,-6,CAST(GETDATE() AS DATE))))
      AND FC.dt_fiscal_month <= DATEADD(MONTH,12,DATETRUNC(YEAR,DATEADD(MONTH,6,CAST(GETDATE() AS DATE))))
    GROUP BY FC.id_item_sku, FC.code_warehouse, FC.code_customer_group, CAL.dt_fsc_month_first, CAL.dt_fsc_month_last, FC.dt_snapshot, FC.dt_fiscal_month
)
SELECT CAST(TRIM(id_item_sku) AS VARCHAR(50)) AS id_item_sku, CAST(TRIM(code_warehouse) AS VARCHAR(10)) AS code_warehouse,
    CAST(TRIM(code_customer_group) AS VARCHAR(50)) AS code_customer_group,
    CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first, CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
    CAST(dt_snapshot AS DATE) AS dt_snapshot, CAST(TRIM(code_horizon) AS VARCHAR(10)) AS code_horizon,
    CAST(qty_forecast AS FLOAT) AS qty_forecast, CAST(TRIM(code_version) AS VARCHAR(20)) AS code_version,
    CAST(TRIM(code_status) AS VARCHAR(20)) AS code_status
FROM CalculatedForecast
""",

    "ForecastHistory.vw_NaiveForecastMonthly": """
CREATE VIEW ForecastHistory.vw_NaiveForecastMonthly AS
WITH
month_weeks AS (SELECT dt_fsc_month_first, COUNT(DISTINCT dt_fsc_week_first) AS num_weeks FROM ReferenceMaster.Calendar GROUP BY dt_fsc_month_first),
actuals_monthly AS (SELECT id_item_sku, code_warehouse, code_customer_group, dt_fsc_month_first, dt_fsc_month_last, SUM(qty_demand) AS qty_actual FROM SalesHistory.ActualDemandMonthly GROUP BY id_item_sku, code_warehouse, code_customer_group, dt_fsc_month_first, dt_fsc_month_last),
actuals_with_lag AS (
    SELECT A.id_item_sku, A.code_warehouse, A.code_customer_group, A.dt_fsc_month_first, A.dt_fsc_month_last, A.qty_actual, MW.num_weeks,
        LAG(A.qty_actual) OVER (PARTITION BY A.id_item_sku, A.code_warehouse, A.code_customer_group ORDER BY A.dt_fsc_month_first) AS qty_actual_prior,
        LAG(MW.num_weeks) OVER (PARTITION BY A.id_item_sku, A.code_warehouse, A.code_customer_group ORDER BY A.dt_fsc_month_first) AS num_weeks_prior
    FROM actuals_monthly AS A INNER JOIN month_weeks AS MW ON MW.dt_fsc_month_first=A.dt_fsc_month_first
),
current_fiscal AS (SELECT TOP 1 num_fsc_year FROM ReferenceMaster.Calendar WHERE dt_date=CAST(GETDATE() AS DATE))
SELECT L.id_item_sku, L.code_warehouse, L.code_customer_group, L.dt_fsc_month_first, L.dt_fsc_month_last,
    CAST(L.qty_actual_prior/L.num_weeks_prior*L.num_weeks AS INT) AS qty_demand,
    'Naive Forecast' AS code_status, 'Naive Forecast' AS name_version
FROM actuals_with_lag AS L
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=L.dt_fsc_month_first
CROSS JOIN current_fiscal AS CF
WHERE L.qty_actual_prior IS NOT NULL AND L.num_weeks_prior > 0 AND L.code_warehouse NOT IN ('C','CNW','C35','55')
    AND CAL.num_fsc_month_year >= (CF.num_fsc_year-3)*100 AND CAL.num_fsc_month_year <= (CF.num_fsc_year+1)*100+1299
""",

    "OpenOrderHistory.vw_OpenOrderLineLevel": """
CREATE VIEW OpenOrderHistory.vw_OpenOrderLineLevel AS
SELECT
    T1.id_order, T1.num_item_sequence, T1.id_customer, T1.code_ship_to,
    UPPER(RTRIM(CASE WHEN T1.code_ship_to IS NULL OR TRIM(T1.code_ship_to)='' THEN TRIM(T1.id_customer) ELSE CONCAT(TRIM(T1.id_customer),'-',TRIM(T1.code_ship_to)) END)) AS id_account_ship_to,
    T1.id_item_sku, T1.code_warehouse, IM.code_afi_item_status,
    CAST(T1.qty_ordered-T1.qty_shipped AS INT) AS qty_open_order,
    CAST(T1.qty_backordered AS INT) AS qty_backorder,
    CAST((T1.amt_extended_selling/CASE WHEN T1.qty_backordered>0 THEN T1.qty_backordered WHEN T1.qty_ordered>0 THEN T1.qty_ordered ELSE 1 END - COALESCE(T2.amt_freight,0))
        * CASE WHEN T1.qty_backordered>0 THEN T1.qty_backordered WHEN T1.qty_ordered>0 THEN T1.qty_ordered ELSE 1 END AS DECIMAL(13,2)) AS amt_open_order,
    CAST(CASE WHEN T1.qty_backordered>0 THEN (T1.amt_extended_selling/T1.qty_backordered-COALESCE(T2.amt_freight,0))*T1.qty_backordered ELSE 0 END AS DECIMAL(13,2)) AS amt_backorder,
    T3.dt_order AS dt_order_taken, T2.dt_promise AS dt_original_promise, T1.dt_requested AS dt_current_promise,
    T4.dt_freeze AS dt_original_request, T4.dt_requested_ship AS dt_current_request, T1.dt_manufactured AS dt_current_load,
    OT1.name_order_type AS name_primary_order_type, OT2.name_order_type AS name_secondary_order_type,
    OT3.name_order_type AS name_3rd_order_type, OT4.name_order_type AS name_4th_order_type,
    T4.code_order_arrangement AS code_order_arrival, T1.code_allocation_flag, T1.num_load_date_changes,
    T3.num_lead_time_days, T3.name_shipping_instructions,
    CASE WHEN T1.name_item_description_short=T1.name_item_description THEN '' ELSE T1.name_item_description_short END AS name_customer_sku,
    COALESCE(T2.amt_freight,0) AS amt_order_freight,
    CASE WHEN DATEADD(DAY,7,T4.dt_requested_ship)<CAST(GETDATE() AS DATE) THEN 'Past Due' ELSE 'Future Ord' END AS code_past_due_flag
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan AS T1_raw
CROSS APPLY (SELECT
    TRIM(T1_raw.ORDNO) AS id_order, TRIM(T1_raw.ITNBR) AS id_item_sku, TRIM(T1_raw.HOUSE) AS code_warehouse,
    CAST(T1_raw.ITMSQ AS INT) AS num_item_sequence, CAST(T1_raw.COQTY AS DECIMAL(12,3)) AS qty_ordered,
    CAST(T1_raw.QTYSH AS DECIMAL(12,3)) AS qty_shipped, CAST(T1_raw.QTYBO AS DECIMAL(12,3)) AS qty_backordered,
    CAST(T1_raw.INSAM AS DECIMAL(12,2)) AS amt_extended_selling, CAST(T1_raw.PRICE AS DECIMAL(12,4)) AS amt_selling_price,
    TRY_CONVERT(DATE, CAST(T1_raw.RQIDT AS VARCHAR(20))) AS dt_requested,
    TRY_CONVERT(DATE, CAST(T1_raw.MFIDT AS VARCHAR(20))) AS dt_manufactured,
    TRIM(T1_raw.CCUSNO) AS id_customer, TRIM(T1_raw.CSHPNO) AS code_ship_to,
    TRIM(T1_raw.ITDSC) AS name_item_description, TRIM(T1_raw.ITDSI) AS name_item_description_short,
    CAST(T1_raw.IAFLG AS VARCHAR(200)) AS code_allocation_flag,
    CAST(T1_raw.NUMLDDTCHG AS INT) AS num_load_date_changes
) AS T1
LEFT JOIN Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT AS T2_raw ON T1.id_order=TRIM(T2_raw.ORDNO) AND T1.num_item_sequence=CAST(T2_raw.ITMSQ AS INT)
CROSS APPLY (SELECT CAST(T2_raw.FRGHT AS DECIMAL(12,2)) AS amt_freight, TRY_CONVERT(DATE,CAST(T2_raw.PRDTE AS VARCHAR(20))) AS dt_promise) AS T2
INNER JOIN Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST AS T3_raw ON T1.id_order=TRIM(T3_raw.ORDNO)
CROSS APPLY (SELECT TRY_CONVERT(DATE,CAST(T3_raw.ORDDT AS VARCHAR(20))) AS dt_order, CAST(T3_raw.LTDAY AS INT) AS num_lead_time_days, TRIM(T3_raw.SPINM) AS name_shipping_instructions, TRIM(T3_raw.RCDCD) AS code_record_type) AS T3
INNER JOIN Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD AS T4_raw ON T1.id_order=TRIM(T4_raw.ORDNO)
CROSS APPLY (SELECT TRY_CONVERT(DATE,CAST(T4_raw.FRZDT AS VARCHAR(20))) AS dt_freeze, TRY_CONVERT(DATE,CAST(T4_raw.RQSHP AS VARCHAR(20))) AS dt_requested_ship, TRIM(T4_raw.ODARR) AS code_order_arrangement, TRIM(T4_raw.ORDTYP1) AS code_order_type_1, TRIM(T4_raw.ORDTYP2) AS code_order_type_2, TRIM(T4_raw.ORDTYP3) AS code_order_type_3, TRIM(T4_raw.ORDTYP4) AS code_order_type_4) AS T4
INNER JOIN ReferenceMaster.ItemMaster AS IM ON IM.id_item_sku=T1.id_item_sku
LEFT JOIN ReferenceMaster.OrderType AS OT1 ON OT1.code_order_type=T4.code_order_type_1
LEFT JOIN ReferenceMaster.OrderType AS OT2 ON OT2.code_order_type=T4.code_order_type_2
LEFT JOIN ReferenceMaster.OrderType AS OT3 ON OT3.code_order_type=T4.code_order_type_3
LEFT JOIN ReferenceMaster.OrderType AS OT4 ON OT4.code_order_type=T4.code_order_type_4
WHERE (T1.qty_backordered<>0 OR T1.qty_ordered<>0) AND T1.amt_selling_price<>0 AND T3.code_record_type<>'X' AND T1.qty_ordered>=0
""",

    "OpenOrderHistory.vw_OpenOrderMonthly": """
CREATE VIEW OpenOrderHistory.vw_OpenOrderMonthly AS
WITH current_fiscal AS (SELECT TOP 1 num_fsc_year FROM ReferenceMaster.Calendar WHERE dt_date=CAST(GETDATE() AS DATE))
SELECT OO.id_item_sku, OO.code_warehouse, UPPER(CG.code_customer_group) AS code_customer_group,
    CAL.dt_fsc_month_first, CAL.dt_fsc_month_last,
    SUM(OO.qty_open_order) AS qty_open_order, SUM(OO.qty_backorder) AS qty_backorder,
    SUM(OO.amt_open_order) AS amt_open_order, SUM(OO.amt_backorder) AS amt_backorder,
    COUNT(*) AS num_order_lines, COUNT(DISTINCT OO.id_order) AS num_distinct_orders,
    SUM(CASE WHEN OO.code_past_due_flag='Past Due' THEN OO.qty_open_order ELSE 0 END) AS qty_past_due,
    SUM(CASE WHEN OO.code_past_due_flag='Past Due' THEN OO.amt_open_order ELSE 0 END) AS amt_past_due
FROM OpenOrderHistory.OpenOrderLineLevel AS OO
INNER JOIN ReferenceMaster.Calendar AS CAL ON CAL.dt_date=OO.dt_current_request
LEFT JOIN ReferenceMaster.CustomerAccountGroup AS CG ON CG.id_customer=OO.id_customer
CROSS JOIN current_fiscal AS CF
WHERE CAL.num_fsc_year BETWEEN CF.num_fsc_year-3 AND CF.num_fsc_year+1
GROUP BY OO.id_item_sku, OO.code_warehouse, UPPER(CG.code_customer_group), CAL.dt_fsc_month_first, CAL.dt_fsc_month_last
""",
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 5: Registry update for v10 view names
# ═══════════════════════════════════════════════════════════════════

# Map asset_id → (physical_schema, physical_object, v10_view_name)
V10_REGISTRY_MAP = {
    # Staging (loaded by usp_RefreshEdwTables, not via generic_load views)
    "bronze.brz_saleshistory_afi__invoicedetail": ("Staging", "InvoiceDetailEdw", None),
    "bronze.brz_saleshistory_afi__invoiceheader": ("Staging", "InvoiceHeaderEdw", None),
    "bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily": ("Staging", "DemandForecastSnapshotDailyEdw", None),
    "bronze.ref_product": ("Staging", "ProductEdw", None),  # Goes through RefreshEdw then vw_Product
    # Direct shortcut Bronze (no local table - Silver reads directly from Enterprise_Lakehouse)
    "bronze.brz_wholesale_codis_afi__codatan": (None, None, None),
    "bronze.brz_wholesale_codis_afi__comast": (None, None, None),
    "bronze.brz_wholesale_codis_afi__extord": (None, None, None),
    "bronze.brz_wholesale_codis_afi__extorit": (None, None, None),
    # ReferenceMaster
    "bronze.ref_calendar": ("ReferenceMaster", "Calendar", "ReferenceMaster.vw_Calendar"),
    "bronze.ref_customer_account": ("ReferenceMaster", "CustomerAccount", "ReferenceMaster.vw_CustomerAccount"),
    "bronze.ref_customer_account_group": ("ReferenceMaster", "CustomerAccountGroup", "ReferenceMaster.vw_CustomerAccountGroup"),
    "bronze.ref_customer_grouping": ("ReferenceMaster", "CustomerGrouping", "ReferenceMaster.vw_CustomerGrouping"),
    "bronze.ref_customer_shipping_location": ("ReferenceMaster", "CustomerShippingLocation", "ReferenceMaster.vw_CustomerShippingLocation"),
    "bronze.ref_forecast_cycle": ("ReferenceMaster", "ForecastCycle", "ReferenceMaster.vw_ForecastCycle"),
    "bronze.ref_forecast_horizon": ("ReferenceMaster", "ForecastHorizon", "ReferenceMaster.vw_ForecastHorizon"),
    "bronze.ref_item_master": ("ReferenceMaster", "ItemMaster", "ReferenceMaster.vw_ItemMaster"),
    "bronze.ref_order_type": ("ReferenceMaster", "OrderType", "ReferenceMaster.vw_OrderType"),
    "bronze.ref_warehouse": ("ReferenceMaster", "Warehouse", "ReferenceMaster.vw_Warehouse"),
    # Silver
    "silver.slv_invoice_detail_line_level": ("SalesHistory", "InvoiceDetailLineLevel", "SalesHistory.vw_InvoiceDetailLineLevel"),
    "silver.slv_invoice_weekly": ("SalesHistory", "InvoiceWeekly", "SalesHistory.vw_InvoiceWeekly"),
    "silver.slv_actual_demand_monthly": ("SalesHistory", "ActualDemandMonthly", "SalesHistory.vw_ActualDemandMonthly"),
    "silver.slv_actual_demand_weekly": ("SalesHistory", "ActualDemandWeekly", "SalesHistory.vw_ActualDemandWeekly"),
    "silver.slv_forecast_demand_monthly": ("ForecastHistory", "ForecastDemandMonthly", "ForecastHistory.vw_ForecastDemandMonthly"),
    "silver.slv_naive_forecast_monthly": ("ForecastHistory", "NaiveForecastMonthly", "ForecastHistory.vw_NaiveForecastMonthly"),
    "silver.slv_open_order_line_level": ("OpenOrderHistory", "OpenOrderLineLevel", "OpenOrderHistory.vw_OpenOrderLineLevel"),
    "silver.slv_open_order_monthly": ("OpenOrderHistory", "OpenOrderMonthly", "OpenOrderHistory.vw_OpenOrderMonthly"),
    # Gold
    "gold.gld_fact_flat_forecast_actual": ("ForecastAccuracy", "FactForecastActual", None),  # Gold WH
    "gold.gld_fact_forecast_kpi": ("ForecastAccuracy", "FactForecastKpi", None),  # Gold WH
}

# Data load order for Phases 5-6
REF_LOAD_ORDER = [
    ("ReferenceMaster", "Calendar"),
    ("ReferenceMaster", "CustomerAccount"),
    ("ReferenceMaster", "CustomerAccountGroup"),
    ("ReferenceMaster", "CustomerGrouping"),
    ("ReferenceMaster", "CustomerShippingLocation"),
    ("ReferenceMaster", "ForecastCycle"),
    ("ReferenceMaster", "ForecastHorizon"),
    ("ReferenceMaster", "ItemMaster"),
    ("ReferenceMaster", "OrderType"),
    ("ReferenceMaster", "Warehouse"),
]

# Silver DAG wave order
SILVER_WAVES = {
    0: [("SalesHistory", "InvoiceDetailLineLevel"), ("ForecastHistory", "ForecastDemandMonthly"), ("OpenOrderHistory", "OpenOrderLineLevel")],
    1: [("SalesHistory", "ActualDemandMonthly"), ("SalesHistory", "ActualDemandWeekly"), ("SalesHistory", "InvoiceWeekly"), ("OpenOrderHistory", "OpenOrderMonthly")],
    2: [("ForecastHistory", "NaiveForecastMonthly")],
}

# ═══════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════

import pyodbc

def run_phase(phase_num, label, func):
    print(f"\n{'='*60}")
    print(f"PHASE {phase_num}: {label}")
    print(f"{'='*60}")
    result = func()
    print(f"  ✓ Phase {phase_num} complete: {json.dumps(result, default=str)}")
    return result

def phase2():
    """Create functions + working SPs"""
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    results = {"functions": [], "sps_replaced": []}

    # Create functions
    for name, sql in FUNCTIONS.items():
        schema, fname = name.split(".", 1)
        drop_if_exists(cur, schema, fname, "FUNCTION")
        r = exe(cur, sql, name)
        results["functions"].append(r)
        print(f"  Function {name}: {r['status']}")

    # Replace placeholder SPs with working ones
    for name, sql in WORKING_SPS.items():
        schema, pname = name.split(".", 1)
        drop_if_exists(cur, schema, pname, "PROCEDURE")
        r = exe(cur, sql, name)
        results["sps_replaced"].append(r)
        print(f"  SP {name}: {r['status']}")

    conn.close()
    return results

def phase3():
    """Create ReferenceMaster tables + source access views"""
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    results = {"ref_views": [], "errors": []}

    # Create REF views
    for name, sql in REF_VIEW_MAP.items():
        schema, vname = name.split(".", 1)
        drop_if_exists(cur, schema, vname, "VIEW")
        r = exe(cur, sql, name)
        results["ref_views"].append(r)
        if r["status"] == "error":
            results["errors"].append(r)
        print(f"  View {name}: {r['status']}" + (f" ERROR: {r.get('error','')[:80]}" if r["status"]=="error" else ""))

    conn.close()
    return results

def phase4():
    """Create Silver transformation views"""
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    results = {"silver_views": [], "errors": []}

    for name, sql in SILVER_VIEWS.items():
        schema, vname = name.split(".", 1)
        drop_if_exists(cur, schema, vname, "VIEW")
        r = exe(cur, sql, name)
        results["silver_views"].append(r)
        if r["status"] == "error":
            results["errors"].append(r)
        print(f"  View {name}: {r['status']}" + (f" ERROR: {r.get('error','')[:100]}" if r["status"]=="error" else ""))

    conn.close()
    return results

def phase5():
    """Update registry + load Staging + ReferenceMaster"""
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    results = {"registry_updates": 0, "staging_load": None, "ref_loads": []}

    # Update registry with v10 physical mappings + view names
    for asset_id, (phys_schema, phys_obj, view_name) in V10_REGISTRY_MAP.items():
        if phys_schema is None:
            continue  # Direct shortcut, no physical table
        sql = "UPDATE Meta.AssetRegistryV10 SET physical_schema=?, physical_object=?"
        params = [phys_schema, phys_obj]
        if view_name:
            sql += ", legacy_view_name=?"
            params.append(view_name)
        sql += " WHERE asset_id=?"
        params.append(asset_id)
        cur.execute(sql, params)
        results["registry_updates"] += 1

    print(f"  Registry updated: {results['registry_updates']} rows")

    # Load Staging (EDW refresh)
    print("  Loading Staging (EDW tables)...")
    try:
        cur.execute("EXEC Staging.usp_RefreshEdwTables")
        # Check row counts
        for tbl in ["InvoiceDetailEdw", "InvoiceHeaderEdw", "DemandForecastSnapshotDailyEdw", "ProductEdw"]:
            cnt = scalar(cur, f"SELECT COUNT(*) FROM Staging.[{tbl}]")
            print(f"    Staging.{tbl}: {cnt:,} rows")
        results["staging_load"] = "success"
    except Exception as e:
        results["staging_load"] = f"error: {e}"
        print(f"    Staging load ERROR: {e}")

    # Load ReferenceMaster tables via generic_load
    print("  Loading ReferenceMaster tables...")
    for schema, table in REF_LOAD_ORDER:
        try:
            cur.execute(f"EXEC Meta.usp_GenericLoad @target_schema='{schema}', @target_table='{table}'")
            cnt = scalar(cur, f"SELECT COUNT(*) FROM [{schema}].[{table}]")
            results["ref_loads"].append({"table": f"{schema}.{table}", "rows": cnt, "status": "ok"})
            print(f"    {schema}.{table}: {cnt:,} rows")
        except Exception as e:
            results["ref_loads"].append({"table": f"{schema}.{table}", "status": "error", "error": str(e)[:200]})
            print(f"    {schema}.{table} ERROR: {str(e)[:100]}")

    conn.close()
    return results

def phase6():
    """Load Silver via DAG waves"""
    conn = connect(PROCESSING_DB)
    cur = conn.cursor()
    results = {"waves": {}}

    for wave_num in sorted(SILVER_WAVES.keys()):
        tables = SILVER_WAVES[wave_num]
        results["waves"][wave_num] = []
        print(f"  Wave {wave_num}:")
        for schema, table in tables:
            try:
                cur.execute(f"EXEC Meta.usp_GenericLoad @target_schema='{schema}', @target_table='{table}'")
                cnt = scalar(cur, f"SELECT COUNT(*) FROM [{schema}].[{table}]")
                results["waves"][wave_num].append({"table": f"{schema}.{table}", "rows": cnt, "status": "ok"})
                print(f"    {schema}.{table}: {cnt:,} rows")
            except Exception as e:
                results["waves"][wave_num].append({"table": f"{schema}.{table}", "status": "error", "error": str(e)[:200]})
                print(f"    {schema}.{table} ERROR: {str(e)[:100]}")

    conn.close()
    return results

def phase7():
    """Gold Warehouse: views + load"""
    conn_gold = connect(GOLD_DB)
    cur_gold = conn_gold.cursor()
    results = {"gold_views": [], "gold_loads": []}

    # Create Gold views in Gold Warehouse (reading from Processing WH via cross-DB)
    gold_views = {
        "ForecastAccuracy.vw_FactForecastActual": """
CREATE VIEW ForecastAccuracy.vw_FactForecastActual AS
SELECT id_item_sku, code_warehouse, code_customer_group, dt_fsc_month_first, dt_fsc_month_last,
    CAST('Actual demand' AS VARCHAR(20)) AS code_horizon, code_status, name_version, CAST(qty_demand AS FLOAT) AS qty
FROM SupplyChain_Processing_Warehouse.SalesHistory.ActualDemandMonthly
UNION ALL
SELECT id_item_sku, code_warehouse, code_customer_group, dt_fsc_month_first, dt_fsc_month_last,
    code_horizon, code_status, code_version AS name_version, CAST(qty_forecast AS FLOAT) AS qty
FROM SupplyChain_Processing_Warehouse.ForecastHistory.ForecastDemandMonthly
UNION ALL
SELECT id_item_sku, code_warehouse, code_customer_group, dt_fsc_month_first, dt_fsc_month_last,
    CAST('Naive forecast' AS VARCHAR(20)) AS code_horizon, code_status, name_version, CAST(qty_demand AS FLOAT) AS qty
FROM SupplyChain_Processing_Warehouse.ForecastHistory.NaiveForecastMonthly
""",
        "ForecastAccuracy.vw_FactForecastKpi": """
CREATE VIEW ForecastAccuracy.vw_FactForecastKpi AS
WITH
forecast AS (
    SELECT UPPER(TRIM(id_item_sku)) AS id_item_sku, UPPER(TRIM(code_warehouse)) AS code_warehouse,
        CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first, CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
        TRIM(code_horizon) AS code_horizon, CAST(dt_snapshot AS DATE) AS dt_snapshot, CAST(SUM(qty_forecast) AS FLOAT) AS qty_forecast
    FROM SupplyChain_Processing_Warehouse.ForecastHistory.ForecastDemandMonthly
    WHERE code_horizon IN ('Lag-0','Lag-1','Lag-2','Lag-3','Lag-4','>Lag-4')
    GROUP BY UPPER(TRIM(id_item_sku)), UPPER(TRIM(code_warehouse)), CAST(dt_fsc_month_first AS DATE), CAST(dt_fsc_month_last AS DATE), TRIM(code_horizon), CAST(dt_snapshot AS DATE)
),
actuals AS (
    SELECT UPPER(TRIM(id_item_sku)) AS id_item_sku, UPPER(TRIM(code_warehouse)) AS code_warehouse,
        CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first, CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS FLOAT) AS qty_actual
    FROM SupplyChain_Processing_Warehouse.SalesHistory.ActualDemandMonthly
    GROUP BY UPPER(TRIM(id_item_sku)), UPPER(TRIM(code_warehouse)), CAST(dt_fsc_month_first AS DATE), CAST(dt_fsc_month_last AS DATE)
),
naive AS (
    SELECT UPPER(TRIM(id_item_sku)) AS id_item_sku, UPPER(TRIM(code_warehouse)) AS code_warehouse,
        CAST(dt_fsc_month_first AS DATE) AS dt_fsc_month_first, CAST(dt_fsc_month_last AS DATE) AS dt_fsc_month_last,
        CAST(SUM(qty_demand) AS FLOAT) AS qty_naive_forecast
    FROM SupplyChain_Processing_Warehouse.ForecastHistory.NaiveForecastMonthly
    GROUP BY UPPER(TRIM(id_item_sku)), UPPER(TRIM(code_warehouse)), CAST(dt_fsc_month_first AS DATE), CAST(dt_fsc_month_last AS DATE)
),
dimkeys AS (
    SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last FROM forecast
    UNION SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last FROM actuals
    UNION SELECT id_item_sku, code_warehouse, dt_fsc_month_first, dt_fsc_month_last FROM naive
),
spine AS (
    SELECT K.id_item_sku, K.code_warehouse, K.dt_fsc_month_first, K.dt_fsc_month_last, H.code_horizon
    FROM dimkeys K CROSS JOIN SupplyChain_Processing_Warehouse.ReferenceMaster.ForecastHorizon H
)
SELECT SP.id_item_sku, SP.code_warehouse, SP.dt_fsc_month_first, SP.dt_fsc_month_last, SP.code_horizon, FC.dt_snapshot,
    CAST(FC.qty_forecast AS FLOAT) AS qty_forecast, CAST(ACT.qty_actual AS FLOAT) AS qty_actual, CAST(NF.qty_naive_forecast AS FLOAT) AS qty_naive_forecast,
    CAST(COALESCE(FC.qty_forecast,0)-COALESCE(ACT.qty_actual,0) AS FLOAT) AS qty_fcst_error,
    CAST(ABS(COALESCE(FC.qty_forecast,0)-COALESCE(ACT.qty_actual,0)) AS FLOAT) AS qty_abs_fcst_error,
    CAST(COALESCE(NF.qty_naive_forecast,0)-COALESCE(ACT.qty_actual,0) AS FLOAT) AS qty_naive_fcst_error,
    CAST(ABS(COALESCE(NF.qty_naive_forecast,0)-COALESCE(ACT.qty_actual,0)) AS FLOAT) AS qty_abs_naive_fcst_error,
    CAST(POWER(COALESCE(FC.qty_forecast,0)-COALESCE(ACT.qty_actual,0),2) AS FLOAT) AS qty_squared_fcst_error,
    CAST(POWER(COALESCE(NF.qty_naive_forecast,0)-COALESCE(ACT.qty_actual,0),2) AS FLOAT) AS qty_squared_naive_fcst_error,
    CAST(CASE WHEN ACT.qty_actual IS NOT NULL AND FC.qty_forecast IS NOT NULL THEN 1 ELSE 0 END AS INT) AS valid_obs_flag,
    CAST(CASE WHEN ACT.qty_actual IS NOT NULL AND ACT.qty_actual<>0 THEN 1 ELSE 0 END AS INT) AS valid_actual_nonzero_flag,
    CAST(CASE WHEN ACT.qty_actual IS NOT NULL AND ACT.qty_actual<>0 THEN ABS((COALESCE(FC.qty_forecast,0)-ACT.qty_actual)/ACT.qty_actual) ELSE NULL END AS FLOAT) AS abs_pct_error
FROM spine AS SP
LEFT JOIN forecast AS FC ON SP.id_item_sku=FC.id_item_sku AND SP.code_warehouse=FC.code_warehouse AND SP.dt_fsc_month_first=FC.dt_fsc_month_first AND SP.dt_fsc_month_last=FC.dt_fsc_month_last AND SP.code_horizon=FC.code_horizon
LEFT JOIN actuals AS ACT ON SP.id_item_sku=ACT.id_item_sku AND SP.code_warehouse=ACT.code_warehouse AND SP.dt_fsc_month_first=ACT.dt_fsc_month_first AND SP.dt_fsc_month_last=ACT.dt_fsc_month_last
LEFT JOIN naive AS NF ON SP.id_item_sku=NF.id_item_sku AND SP.code_warehouse=NF.code_warehouse AND SP.dt_fsc_month_first=NF.dt_fsc_month_first AND SP.dt_fsc_month_last=NF.dt_fsc_month_last
""",
    }

    for name, sql in gold_views.items():
        schema, vname = name.split(".", 1)
        drop_if_exists(cur_gold, schema, vname, "VIEW")
        r = exe(cur_gold, sql, name)
        results["gold_views"].append(r)
        print(f"  Gold View {name}: {r['status']}" + (f" ERROR: {r.get('error','')[:100]}" if r["status"]=="error" else ""))

    # Load Gold tables
    for tbl, view in [("FactForecastActual", "ForecastAccuracy.vw_FactForecastActual"), ("FactForecastKpi", "ForecastAccuracy.vw_FactForecastKpi")]:
        print(f"  Loading Gold ForecastAccuracy.{tbl}...")
        try:
            cur_gold.execute(f"DROP TABLE IF EXISTS ForecastAccuracy.[{tbl}]")
            cur_gold.execute(f"CREATE TABLE ForecastAccuracy.[{tbl}] AS SELECT *, CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM {view}")
            cnt = scalar(cur_gold, f"SELECT COUNT(*) FROM ForecastAccuracy.[{tbl}]")
            results["gold_loads"].append({"table": tbl, "rows": cnt, "status": "ok"})
            print(f"    ForecastAccuracy.{tbl}: {cnt:,} rows")
        except Exception as e:
            results["gold_loads"].append({"table": tbl, "status": "error", "error": str(e)[:200]})
            print(f"    ForecastAccuracy.{tbl} ERROR: {str(e)[:100]}")

    conn_gold.close()
    return results

def main():
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    all_results = {"started_at": ts}

    try:
        all_results["phase2"] = run_phase(2, "Functions + Working SPs", phase2)
        all_results["phase3"] = run_phase(3, "ReferenceMaster views", phase3)
        all_results["phase4"] = run_phase(4, "Silver views", phase4)
        all_results["phase5"] = run_phase(5, "Registry + Staging + REF load", phase5)
        all_results["phase6"] = run_phase(6, "Silver load", phase6)
        all_results["phase7"] = run_phase(7, "Gold Warehouse", phase7)
    except Exception as e:
        all_results["fatal_error"] = traceback.format_exc()
        print(f"\nFATAL ERROR: {e}")

    all_results["finished_at"] = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    out_file = OUT_DIR / f"build_v10_full_results_{ts}.json"
    out_file.write_text(json.dumps(all_results, indent=2, default=str))
    print(f"\nResults saved to: {out_file}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())