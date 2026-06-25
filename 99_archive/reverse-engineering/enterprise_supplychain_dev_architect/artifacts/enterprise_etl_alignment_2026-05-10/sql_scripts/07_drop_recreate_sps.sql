-- 07_drop_recreate_sps.sql
-- DROP + CREATE all Meta SPs (refs to old schema names removed). Logic unchanged.

DROP PROCEDURE IF EXISTS Meta.usp_CheckDq;
GO
DROP PROCEDURE IF EXISTS Meta.usp_CheckDqSingle;
GO
DROP PROCEDURE IF EXISTS Meta.usp_ComputeSilverWaves;
GO
DROP PROCEDURE IF EXISTS Meta.usp_DebugLoop;
GO
DROP PROCEDURE IF EXISTS Meta.usp_FinalizePipeline;
GO
DROP PROCEDURE IF EXISTS Meta.usp_GenericLoad;
GO
DROP PROCEDURE IF EXISTS Meta.usp_LogPipelineRun;
GO
DROP PROCEDURE IF EXISTS Meta.usp_LogRun;
GO
DROP PROCEDURE IF EXISTS Meta.usp_ResolveAccessMode;
GO
DROP PROCEDURE IF EXISTS Meta.usp_RunDQGate;
GO
DROP PROCEDURE IF EXISTS Meta.usp_RunReconciliation;
GO
DROP PROCEDURE IF EXISTS Meta.usp_RunSilverDag;
GO
DROP PROCEDURE IF EXISTS Meta.usp_ValidateSourceContract;
GO

-- Recreate (transformed):
-- ============================================================
-- Meta Schema — Stored Procedures + Functions
-- ============================================================
-- Control plane: pipeline orchestration, DQ engine, lineage rebuild,
--                generic load patterns, run logging.
-- Source: SupplyChain_Processing_Warehouse.Meta
-- ============================================================

-- ---- [SQL_SCALAR_FUNCTION] Meta.ufn_cron_is_due ----

CREATE FUNCTION Meta.ufn_cron_is_due(@cron VARCHAR(100))
RETURNS INT
AS
BEGIN
    IF @cron IS NULL OR @cron = '' RETURN 1
    DECLARE @now DATETIME2(6) = GETUTCDATE()
    DECLARE @minute INT = DATEPART(MINUTE, @now)
    DECLARE @hour INT = DATEPART(HOUR, @now)
    DECLARE @day INT = DATEPART(DAY, @now)
    DECLARE @month INT = DATEPART(MONTH, @now)
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

    DECLARE @match_min INT = 0, @match_hr INT = 0, @match_day INT = 0, @match_mon INT = 0, @match_dow INT = 0

    -- MINUTE
    IF @f1 = '*' SET @match_min = 1
    ELSE IF @f1 LIKE '*/%' BEGIN DECLARE @step_min INT = CAST(SUBSTRING(@f1, 3, 10) AS INT); IF @minute % @step_min = 0 SET @match_min = 1 END
    ELSE IF @f1 LIKE '%-%' BEGIN IF @minute >= CAST(LEFT(@f1, CHARINDEX('-', @f1) - 1) AS INT) AND @minute <= CAST(SUBSTRING(@f1, CHARINDEX('-', @f1) + 1, 10) AS INT) SET @match_min = 1 END
    ELSE IF CHARINDEX(',', @f1) > 0 BEGIN IF CHARINDEX(CAST(@minute AS VARCHAR), @f1) > 0 SET @match_min = 1 END
    ELSE IF CAST(@f1 AS INT) = @minute SET @match_min = 1

    -- HOUR
    IF @f2 = '*' SET @match_hr = 1
    ELSE IF @f2 LIKE '*/%' BEGIN DECLARE @step_hr INT = CAST(SUBSTRING(@f2, 3, 10) AS INT); IF @hour % @step_hr = 0 SET @match_hr = 1 END
    ELSE IF @f2 LIKE '%-%' BEGIN IF @hour >= CAST(LEFT(@f2, CHARINDEX('-', @f2) - 1) AS INT) AND @hour <= CAST(SUBSTRING(@f2, CHARINDEX('-', @f2) + 1, 10) AS INT) SET @match_hr = 1 END
    ELSE IF CHARINDEX(',', @f2) > 0 BEGIN IF CHARINDEX(CAST(@hour AS VARCHAR), @f2) > 0 SET @match_hr = 1 END
    ELSE IF CAST(@f2 AS INT) = @hour SET @match_hr = 1

    -- DAY OF MONTH
    IF @f3 = '*' SET @match_day = 1
    ELSE IF @f3 LIKE '%-%' BEGIN IF @day >= CAST(LEFT(@f3, CHARINDEX('-', @f3) - 1) AS INT) AND @day <= CAST(SUBSTRING(@f3, CHARINDEX('-', @f3) + 1, 10) AS INT) SET @match_day = 1 END
    ELSE IF CHARINDEX(',', @f3) > 0 BEGIN IF CHARINDEX(CAST(@day AS VARCHAR), @f3) > 0 SET @match_day = 1 END
    ELSE IF CAST(@f3 AS INT) = @day SET @match_day = 1

    -- MONTH
    IF @f4 = '*' SET @match_mon = 1
    ELSE IF @f4 LIKE '%-%' BEGIN IF @month >= CAST(LEFT(@f4, CHARINDEX('-', @f4) - 1) AS INT) AND @month <= CAST(SUBSTRING(@f4, CHARINDEX('-', @f4) + 1, 10) AS INT) SET @match_mon = 1 END
    ELSE IF CHARINDEX(',', @f4) > 0 BEGIN IF CHARINDEX(CAST(@month AS VARCHAR), @f4) > 0 SET @match_mon = 1 END
    ELSE IF CAST(@f4 AS INT) = @month SET @match_mon = 1

    -- DAY OF WEEK (0=Mon, 6=Sun)
    IF @f5 = '*' SET @match_dow = 1
    ELSE IF @f5 LIKE '%-%' BEGIN IF @dow >= CAST(LEFT(@f5, CHARINDEX('-', @f5) - 1) AS INT) AND @dow <= CAST(SUBSTRING(@f5, CHARINDEX('-', @f5) + 1, 10) AS INT) SET @match_dow = 1 END
    ELSE IF CHARINDEX(',', @f5) > 0 BEGIN IF CHARINDEX(CAST(@dow AS VARCHAR), @f5) > 0 SET @match_dow = 1 END
    ELSE IF CAST(@f5 AS INT) = @dow SET @match_dow = 1

    IF @match_min = 1 AND @match_hr = 1 AND @match_day = 1 AND @match_mon = 1 AND @match_dow = 1 RETURN 1
    RETURN 0
END

GO

-- ---- [SQL_SCALAR_FUNCTION] Meta.ufn_should_run ----

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
    FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
    RETURN ISNULL(@result, 0);
END

GO

-- ---- [SQL_SCALAR_FUNCTION] Meta.ufn_utc_to_cst ----

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

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_BuildLineage ----

CREATE   PROCEDURE Meta.usp_BuildLineage
AS
BEGIN
    -- Preserve edges with edge_type='semantic' (managed by build_semantic_model_lineage.py)
    DELETE FROM Meta.LineageEdge WHERE edge_type IN ('direct','derived');

    INSERT INTO Meta.LineageEdge (edge_id, source_asset, target_asset, edge_type, transform_type, is_synthetic, created_at_utc)
    SELECT
        CONCAT('lineage::', ROW_NUMBER() OVER (ORDER BY r.asset_id, src.value)),
        TRIM(REPLACE(REPLACE(REPLACE(src.value, '"', ''), '''', ''), ' ', '')),
        r.asset_id,
        'direct',
        r.load_type,
        0,
        SYSUTCDATETIME()
    FROM Meta.AssetRegistry r
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(r.source_objects, '[', ''), ']', ''), ',') src
    WHERE r.source_objects IS NOT NULL AND LEN(TRIM(src.value)) > 0;
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_CheckDq ----

CREATE PROCEDURE Meta.usp_CheckDq
    @layer VARCHAR(80), @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    DECLARE @rule_id INT, @has_critical INT = 0;
    SELECT @rule_id = MIN(rule_id) FROM Meta.DQRule WHERE layer = @layer AND is_active = 1;

    WHILE @rule_id IS NOT NULL
    BEGIN
        BEGIN TRY
            EXEC Meta.usp_CheckDqSingle @rule_id = @rule_id, @pipeline_run_id = @pipeline_run_id;
        END TRY
        BEGIN CATCH
            SET @has_critical = @has_critical + 1;
        END CATCH

        SELECT @rule_id = MIN(rule_id) FROM Meta.DQRule
        WHERE rule_id > @rule_id AND layer = @layer AND is_active = 1;
    END

    IF @has_critical > 0
    BEGIN
        DECLARE @msg NVARCHAR(500) = N'DQ CRITICAL: ' + CAST(@has_critical AS NVARCHAR(10)) + N' failures in layer ' + CAST(@layer AS NVARCHAR(80));
        THROW 50001, @msg, 1;
    END
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_CheckDqSingle ----

CREATE PROCEDURE Meta.usp_CheckDqSingle
    @rule_id INT, @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rule_name VARCHAR(200), @target_schema VARCHAR(128), @target_table VARCHAR(256);
    DECLARE @check_type VARCHAR(30), @column_name VARCHAR(100), @severity VARCHAR(10);
    DECLARE @threshold DECIMAL(18,2), @params VARCHAR(1000), @layer VARCHAR(80);

    SELECT @rule_name=rule_name, @target_schema=target_schema, @target_table=target_table,
           @check_type=check_type, @column_name=column_name, @severity=severity,
           @threshold=threshold, @params=params, @layer=layer
    FROM Meta.DQRule WHERE rule_id=@rule_id AND is_active=1;
    IF @rule_name IS NULL RETURN;

    DECLARE @sql NVARCHAR(4000), @actual VARCHAR(500), @expected VARCHAR(500);
    DECLARE @result_val DECIMAL(18,4), @status VARCHAR(10);
    DECLARE @full_table NVARCHAR(500) = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    BEGIN TRY
        IF @check_type = 'completeness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(SUM(CASE WHEN ' + QUOTENAME(@column_name) + N' IS NULL THEN 0 ELSE 1 END) * 100.0 / NULLIF(COUNT(*),0) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual = CAST(@result_val AS VARCHAR(50));
            SET @expected = CASE WHEN @threshold IS NOT NULL THEN CAST(@threshold AS VARCHAR(50)) ELSE '100.0' END;
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 100.0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'row_count'
        BEGIN
            SET @sql = N'SELECT @val = CAST(COUNT(*) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected = CAST(@threshold AS VARCHAR(50));
            SET @status = CASE WHEN @result_val >= ISNULL(@threshold, 0) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'uniqueness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(COUNT(*) - COUNT(DISTINCT ' + QUOTENAME(@column_name) + N') AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS BIGINT) AS VARCHAR(50));
            SET @expected = '0';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type = 'freshness'
        BEGIN
            SET @sql = N'SELECT @val = CAST(DATEDIFF(HOUR, MAX(' + QUOTENAME(@column_name) + N'), CAST(GETUTCDATE() AS DATETIME2(6))) AS DECIMAL(18,4)) FROM ' + @full_table;
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual = CAST(CAST(@result_val AS INT) AS VARCHAR(50)) + ' hours';
            SET @expected = '<= ' + CAST(@threshold AS VARCHAR(50)) + ' hours';
            SET @status = CASE WHEN @result_val <= ISNULL(@threshold, 24) THEN 'PASS' ELSE 'FAIL' END;
        END
        ELSE IF @check_type IN ('custom_sql', 'referential_integrity', 'validity')
        BEGIN
            SET @sql = CAST(@params AS NVARCHAR(4000));
            EXEC sp_executesql @sql, N'@val DECIMAL(18,4) OUTPUT', @val = @result_val OUTPUT;
            SET @actual = CAST(@result_val AS VARCHAR(50));
            SET @expected = '0';
            SET @status = CASE WHEN @result_val = 0 THEN 'PASS' ELSE 'FAIL' END;
        END

        DECLARE @write_attempt INT = 0, @write_done INT = 0;
        WHILE @write_attempt < 3 AND @write_done = 0
        BEGIN
            BEGIN TRY
                DELETE FROM Meta.DQGateRun WHERE dq_gate_run_id = CONCAT('dqr::', @rule_id);
                INSERT INTO Meta.DQGateRun (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message)
                VALUES (CONCAT('dqr::', @rule_id), @target_schema + '.' + @target_table, @pipeline_run_id,
                    @check_type + ' on ' + @target_schema + '.' + @target_table
                    + CASE WHEN @column_name IS NOT NULL THEN '.' + @column_name ELSE '' END + ': ' + @severity,
                    @status, CAST(GETUTCDATE() AS DATETIME2(6)),
                    CASE WHEN @status = 'FAIL' THEN 1 ELSE 0 END,
                    @actual + ' vs ' + ISNULL(@expected, 'N/A'));
                SET @write_done = 1;
            END TRY
            BEGIN CATCH
                SET @write_attempt = @write_attempt + 1;
                IF @write_attempt < 3 WAITFOR DELAY '00:00:02';
            END CATCH
        END

        IF @status = 'FAIL' AND @severity = 'CRITICAL'
        BEGIN
            DECLARE @err_msg NVARCHAR(500) = N'DQ CRITICAL FAIL: ' + CAST(@rule_name AS NVARCHAR(200))
                + N' | actual=' + ISNULL(CAST(@actual AS NVARCHAR(100)), N'NULL')
                + N' | expected=' + ISNULL(CAST(@expected AS NVARCHAR(100)), N'NULL');
            THROW 50001, @err_msg, 1;
        END
    END TRY
    BEGIN CATCH
        DECLARE @err_write INT = 0, @err_done INT = 0;
        WHILE @err_write < 3 AND @err_done = 0
        BEGIN
            BEGIN TRY
                IF NOT EXISTS (SELECT 1 FROM Meta.DQGateRun WHERE dq_gate_run_id = CONCAT('dqr::', @rule_id) AND status IN ('PASS','FAIL') AND checked_at_utc >= DATEADD(SECOND, -10, CAST(GETUTCDATE() AS DATETIME2(6))))
                BEGIN
                    DELETE FROM Meta.DQGateRun WHERE dq_gate_run_id = CONCAT('dqr::', @rule_id);
                    INSERT INTO Meta.DQGateRun (dq_gate_run_id, asset_id, run_id, gate_name, status, checked_at_utc, failed_rule_count, error_message)
                    VALUES (CONCAT('dqr::', @rule_id), @target_schema + '.' + @target_table, @pipeline_run_id, 'ERROR', 'ERROR', CAST(GETUTCDATE() AS DATETIME2(6)), 1, ERROR_MESSAGE());
                END
                SET @err_done = 1;
            END TRY
            BEGIN CATCH SET @err_write = @err_write + 1; IF @err_write < 3 WAITFOR DELAY '00:00:02'; END CATCH
        END
        IF @severity = 'CRITICAL' THROW;
    END CATCH
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_ComputeSilverWaves ----

CREATE PROCEDURE Meta.usp_ComputeSilverWaves AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Meta.SilverDagWaveRuntime;

    DECLARE @wave INT = 0, @assigned INT = 0, @new_count INT = 1, @total INT, @max_waves INT = 30;
    SELECT @total = COUNT(*) FROM Meta.AssetRegistry WHERE canonical_layer = 'DomainSilver' AND is_active = 1;

    -- Wave 0: assets with no Silver dependencies
    INSERT INTO Meta.SilverDagWaveRuntime (runtime_id, project, asset_id, physical_schema, physical_object, wave_number, dependency_count, is_active, computed_at_utc)
    SELECT CONCAT('wave::', asset_id), project, asset_id, physical_schema, physical_object, 0,
        CASE WHEN depends_on IS NULL OR depends_on = '' THEN 0 ELSE 1 END, is_active, SYSUTCDATETIME()
    FROM Meta.AssetRegistry
    WHERE canonical_layer = 'DomainSilver' AND is_active = 1
    AND (depends_on IS NULL OR (depends_on NOT LIKE '%silver.slv_%' AND depends_on NOT LIKE '%SalesHistory%' AND depends_on NOT LIKE '%ForecastHistory%' AND depends_on NOT LIKE '%OpenOrderHistory%'));

    SELECT @assigned = COUNT(*) FROM Meta.SilverDagWaveRuntime;
    SET @wave = 1;

    WHILE @assigned < @total AND @wave < @max_waves AND @new_count > 0
    BEGIN
        INSERT INTO Meta.SilverDagWaveRuntime (runtime_id, project, asset_id, physical_schema, physical_object, wave_number, dependency_count, is_active, computed_at_utc)
        SELECT CONCAT('wave::', r.asset_id), r.project, r.asset_id, r.physical_schema, r.physical_object, @wave,
            1, r.is_active, SYSUTCDATETIME()
        FROM Meta.AssetRegistry r
        WHERE r.canonical_layer = 'DomainSilver' AND r.is_active = 1
        AND r.asset_id NOT IN (SELECT asset_id FROM Meta.SilverDagWaveRuntime)
        AND NOT EXISTS (
            SELECT 1 FROM Meta.AssetRegistry dep
            WHERE dep.canonical_layer = 'DomainSilver' AND dep.is_active = 1
            AND r.depends_on LIKE '%' + dep.asset_id + '%'
            AND dep.asset_id NOT IN (SELECT asset_id FROM Meta.SilverDagWaveRuntime WHERE wave_number < @wave)
        );
        SET @new_count = @@ROWCOUNT;
        SET @assigned = @assigned + @new_count;
        SET @wave = @wave + 1;
    END
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_DebugLoop ----

CREATE PROCEDURE Meta.usp_DebugLoop
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 'AssetRegistry' AS object_name, COUNT(*) AS row_count FROM Meta.AssetRegistry
    UNION ALL SELECT 'SourceFeed', COUNT(*) FROM Meta.SourceFeed
    UNION ALL SELECT 'SourceContract', COUNT(*) FROM Meta.SourceContract
    UNION ALL SELECT 'DQRule', COUNT(*) FROM Meta.DQRule
    UNION ALL SELECT 'LineageEdge', COUNT(*) FROM Meta.LineageEdge
    UNION ALL SELECT 'ReconciliationRule', COUNT(*) FROM Meta.ReconciliationRule
    UNION ALL SELECT 'SilverDagWaveRuntime', COUNT(*) FROM Meta.SilverDagWaveRuntime;
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_FinalizePipeline ----

CREATE PROCEDURE Meta.usp_FinalizePipeline
    @pipeline_run_id VARCHAR(128) = NULL
AS
BEGIN
    EXEC Meta.usp_BuildLineage;

    DECLARE @succeeded INT = 0, @failed INT = 0;
    SELECT @succeeded = COUNT(*) FROM Meta.RunLog WHERE status = 'success' AND start_time_utc >= DATEADD(MINUTE, -60, GETUTCDATE());
    SELECT @failed = COUNT(*) FROM Meta.RunLog WHERE status = 'failed' AND start_time_utc >= DATEADD(MINUTE, -60, GETUTCDATE());

    IF @pipeline_run_id IS NOT NULL
    BEGIN
        DECLARE @notes VARCHAR(2000);
        SET @notes = CAST(@succeeded AS VARCHAR) + ' succeeded, ' + CAST(@failed AS VARCHAR) + ' failed';
        UPDATE Meta.PipelineRunLog
        SET status = CASE WHEN @failed > 0 THEN 'partial' ELSE 'success' END,
            end_time_utc = CAST(GETUTCDATE() AS DATETIME2(6)),
            error_message = @notes
        WHERE pipeline_run_id = @pipeline_run_id;
    END
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_GenericLoad ----

CREATE PROCEDURE Meta.usp_GenericLoad
    @target_schema VARCHAR(128), @target_table VARCHAR(256)
AS
BEGIN
    DECLARE @run_id VARCHAR(128) = CONVERT(VARCHAR(36), NEWID());
    DECLARE @asset_id VARCHAR(128), @view_name NVARCHAR(512), @load_type VARCHAR(80);
    DECLARE @wm_col NVARCHAR(256), @pk_col NVARCHAR(1000), @last_wm VARCHAR(1000);
    DECLARE @dt_key NVARCHAR(128), @dt_range_days INT;
    DECLARE @rows BIGINT, @sql NVARCHAR(4000), @full_target NVARCHAR(500);
    DECLARE @new_wm VARCHAR(200), @err VARCHAR(4000);

    SELECT @asset_id=asset_id, @view_name=legacy_view_name, @load_type=load_type,
           @wm_col=watermark_column, @pk_col=primary_key, @last_wm=last_watermark_value,
           @dt_key=date_key, @dt_range_days=date_range_days
    FROM Meta.AssetRegistry
    WHERE physical_schema=@target_schema AND physical_object=@target_table;

    IF @asset_id IS NULL BEGIN RAISERROR('Table %s.%s not found in registry',16,1,@target_schema,@target_table); RETURN; END
    SET @full_target = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    EXEC Meta.usp_LogRun @run_id, @asset_id, 'running', @load_type=@load_type;

    BEGIN TRY
        DECLARE @tbl_exists INT = 0;
        EXEC sp_executesql N'SELECT @out=COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name=@s AND t.name=@t',
            N'@s VARCHAR(128),@t VARCHAR(256),@out INT OUT', @s=@target_schema,@t=@target_table,@out=@tbl_exists OUT;

        -- ═══ OVERWRITE ═══
        IF @load_type = 'overwrite'
        BEGIN
            IF @view_name IS NULL BEGIN RAISERROR('overwrite requires view_name',16,1); RETURN; END
            SET @sql = N'DROP TABLE IF EXISTS ' + @full_target; EXEC sp_executesql @sql;
            SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql;
        END

        -- ═══ INCREMENTAL ═══
        ELSE IF @load_type = 'incremental'
        BEGIN
            IF @tbl_exists = 0 OR @last_wm IS NULL
            BEGIN
                SET @sql = N'DROP TABLE IF EXISTS ' + @full_target; EXEC sp_executesql @sql;
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name + N' WHERE ' + QUOTENAME(@wm_col) + N' >= CAST(''2023-01-01'' AS DATETIME2(6))'; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name + N' WHERE ' + QUOTENAME(@wm_col) + N' > CAST(@wm AS DATETIME2(6))';
                EXEC sp_executesql @sql, N'@wm VARCHAR(200)', @wm=@last_wm;
            END
            SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@wm_col) + N') AS VARCHAR(200)) FROM ' + @full_target;
            EXEC sp_executesql @sql, N'@out VARCHAR(200) OUT', @out=@new_wm OUT;
            IF @new_wm IS NOT NULL
                UPDATE Meta.AssetRegistry SET last_watermark_value=@new_wm WHERE asset_id=@asset_id;
        END

        -- ═══ UPSERT (DELETE matching + INSERT) ═══
        ELSE IF @load_type = 'upsert'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('upsert requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@pk_col) + N' IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N')'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql;
            END
        END

        -- ═══ DATEKEY (delete today + insert today) ═══
        ELSE IF @load_type = 'datekey'
        BEGIN
            DECLARE @dk NVARCHAR(128) = COALESCE(@dt_key, @wm_col);
            IF @dk IS NULL BEGIN RAISERROR('datekey requires date_key or watermark_column',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE CAST(' + QUOTENAME(@dk) + N' AS DATE) = CAST(GETDATE() AS DATE)'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name + N' WHERE CAST(' + QUOTENAME(@dk) + N' AS DATE) = CAST(GETDATE() AS DATE)'; EXEC sp_executesql @sql;
            END
        END

        -- ═══ DATERANGE (delete N days + insert N days) ═══
        ELSE IF @load_type = 'daterange'
        BEGIN
            DECLARE @dr_col NVARCHAR(128) = COALESCE(@dt_key, @wm_col);
            DECLARE @neg_days INT = -1 * COALESCE(@dt_range_days, 30);
            IF @dr_col IS NULL BEGIN RAISERROR('daterange requires date_key or watermark_column',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@dr_col) + N' >= DATEADD(DAY,@d,CAST(GETDATE() AS DATE))';
                EXEC sp_executesql @sql, N'@d INT', @d=@neg_days;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name + N' WHERE ' + QUOTENAME(@dr_col) + N' >= DATEADD(DAY,@d,CAST(GETDATE() AS DATE))';
                EXEC sp_executesql @sql, N'@d INT', @d=@neg_days;
            END
        END

        -- ═══ IDENTITY (append WHERE pk > MAX) ═══
        ELSE IF @load_type = 'identity'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('identity requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                DECLARE @max_pk NVARCHAR(200);
                SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@pk_col) + N') AS NVARCHAR(200)) FROM ' + @full_target;
                EXEC sp_executesql @sql, N'@out NVARCHAR(200) OUT', @out=@max_pk OUT;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name + N' WHERE ' + QUOTENAME(@pk_col) + N' > @mx';
                EXEC sp_executesql @sql, N'@mx NVARCHAR(200)', @mx=@max_pk;
            END
        END

        -- ═══ CDC (apply changes from CDC log view) ═══
        ELSE IF @load_type = 'cdc'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('cdc requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql; END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@pk_col) + N' IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N')'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            IF @wm_col IS NOT NULL
            BEGIN
                SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@wm_col) + N') AS VARCHAR(200)) FROM ' + @full_target;
                EXEC sp_executesql @sql, N'@out VARCHAR(200) OUT', @out=@new_wm OUT;
                IF @new_wm IS NOT NULL
                    UPDATE Meta.AssetRegistry SET last_watermark_value=@new_wm WHERE asset_id=@asset_id;
            END
        END

        -- ═══ SCD2 (close old versions + insert new) ═══
        ELSE IF @load_type = 'scd2'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('scd2 requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)) AS SCD2StartDT,'
                    + N'CAST(''9999-12-31'' AS DATETIME2(6)) AS SCD2EndDT,'
                    + N'CAST(1 AS INT) AS SCD2IsCurrent,'
                    + N'CAST(1 AS INT) AS SCD2Version,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT'
                    + N' FROM ' + @view_name;
                EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'UPDATE ' + @full_target + N' SET SCD2EndDT=CAST(GETUTCDATE() AS DATETIME2(6)),SCD2IsCurrent=0'
                    + N' WHERE SCD2IsCurrent=1 AND ' + QUOTENAME(@pk_col) + N' IN ('
                    + N'SELECT src.' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N' src'
                    + N' INNER JOIN ' + @full_target + N' tgt ON src.' + QUOTENAME(@pk_col) + N'=tgt.' + QUOTENAME(@pk_col)
                    + N' WHERE tgt.SCD2IsCurrent=1)';
                EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target
                    + N' SELECT src.*,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)),'
                    + N'CAST(''9999-12-31'' AS DATETIME2(6)),'
                    + N'1,'
                    + N'COALESCE(v.mx,0)+1,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6))'
                    + N' FROM ' + @view_name + N' src'
                    + N' LEFT JOIN (SELECT ' + QUOTENAME(@pk_col) + N',MAX(SCD2Version) AS mx FROM ' + @full_target + N' GROUP BY ' + QUOTENAME(@pk_col) + N') v'
                    + N' ON src.' + QUOTENAME(@pk_col) + N'=v.' + QUOTENAME(@pk_col)
                    + N' WHERE src.' + QUOTENAME(@pk_col) + N' NOT IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @full_target + N' WHERE SCD2IsCurrent=1)';
                EXEC sp_executesql @sql;
            END
        END

        ELSE BEGIN RAISERROR('Unsupported load_type: %s',16,1,@load_type); RETURN; END

        -- COUNT + LOG
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

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_LogPipelineRun ----

CREATE PROCEDURE Meta.usp_LogPipelineRun
    @pipeline_run_id VARCHAR(128), @pipeline_name VARCHAR(256), @status VARCHAR(80),
    @tables_succeeded INT = NULL, @tables_failed INT = NULL, @notes VARCHAR(2000) = NULL
AS
BEGIN
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    IF @status = 'running'
        INSERT INTO Meta.PipelineRunLog (pipeline_run_id, pipeline_name, status, start_time_utc, trigger_type)
        VALUES (@pipeline_run_id, @pipeline_name, 'running', @now, 'Manual');
    ELSE
        UPDATE Meta.PipelineRunLog
        SET status = @status, end_time_utc = @now,
            error_message = @notes
        WHERE pipeline_run_id = @pipeline_run_id;
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_LogRun ----

CREATE PROCEDURE Meta.usp_LogRun
    @run_id VARCHAR(128), @asset_id VARCHAR(128), @status VARCHAR(80),
    @rows_loaded BIGINT = NULL, @error_message VARCHAR(4000) = NULL,
    @pipeline_run_id VARCHAR(128) = NULL, @load_type VARCHAR(80) = NULL
AS
BEGIN
    DECLARE @retry INT = 0, @done INT = 0;
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);

    WHILE @retry < 3 AND @done = 0
    BEGIN
        BEGIN TRY
            IF @status = 'running'
            BEGIN
                INSERT INTO Meta.RunLog (run_id, asset_id, object_name, layer_name, status, start_time_utc, start_time_cst, load_type)
                SELECT @run_id, @asset_id, CONCAT(physical_schema,'.',physical_object), canonical_layer, 'running', @now, @now_cst, COALESCE(@load_type, load_type)
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
                    next_run_time = CASE
                        WHEN frequency = 'daily'   THEN DATEADD(DAY, 1, CAST(@now AS DATE))
                        WHEN frequency = 'hourly'  THEN DATEADD(HOUR, 1, @now)
                        WHEN frequency = 'weekly'  THEN DATEADD(WEEK, 1, CAST(@now AS DATE))
                        WHEN frequency = 'monthly' THEN DATEADD(MONTH, 1, CAST(@now AS DATE))
                        ELSE DATEADD(DAY, 1, CAST(@now AS DATE))
                    END
                WHERE asset_id = @asset_id;
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

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_ResolveAccessMode ----

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
    FROM Meta.AssetRegistry
    WHERE asset_id = @asset_id;
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_RunDQGate ----

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
    FROM Meta.AssetRegistry
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

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_RunReconciliation ----

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

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_RunSilverDag ----

CREATE PROCEDURE Meta.usp_RunSilverDag AS
BEGIN
    EXEC Meta.usp_ComputeSilverWaves;

    DECLARE @max_wave INT;
    EXEC sp_executesql N'SELECT @mw = ISNULL(MAX(wave_number), -1) FROM Meta.SilverDagWaveRuntime',
         N'@mw INT OUTPUT', @mw = @max_wave OUTPUT;

    IF @max_wave < 0 BEGIN PRINT 'No Silver SPs to run'; RETURN; END

    DECLARE @current_wave INT = 0;
    DECLARE @asset_id NVARCHAR(200), @target_schema NVARCHAR(128), @target_table NVARCHAR(256);
    DECLARE @find_sql NVARCHAR(500);

    WHILE @current_wave <= @max_wave
    BEGIN
        SET @asset_id = NULL;
        SET @find_sql = N'SELECT @out = MIN(asset_id) FROM Meta.SilverDagWaveRuntime WHERE wave_number = @w';
        EXEC sp_executesql @find_sql, N'@w INT, @out NVARCHAR(200) OUTPUT', @w = @current_wave, @out = @asset_id OUTPUT;

        WHILE @asset_id IS NOT NULL
        BEGIN
            SELECT @target_schema = physical_schema, @target_table = physical_object
            FROM Meta.AssetRegistry WHERE asset_id = @asset_id;

            IF @target_schema IS NOT NULL
                EXEC Meta.usp_GenericLoad @target_schema = @target_schema, @target_table = @target_table;

            SET @find_sql = N'SELECT @out = MIN(asset_id) FROM Meta.SilverDagWaveRuntime WHERE wave_number = @w AND asset_id > @prev';
            EXEC sp_executesql @find_sql, N'@w INT, @prev NVARCHAR(200), @out NVARCHAR(200) OUTPUT',
                 @w = @current_wave, @prev = @asset_id, @out = @asset_id OUTPUT;
        END
        SET @current_wave = @current_wave + 1;
    END
END

GO

-- ---- [SQL_STORED_PROCEDURE] Meta.usp_ValidateSourceContract ----

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

GO
