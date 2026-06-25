-- Source: SupplyChain_Warehouse.meta.usp_generic_load
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_generic_load
    @target_schema  VARCHAR(50),
    @target_table   VARCHAR(200)
AS
BEGIN
    DECLARE @run_id VARCHAR(36) = CONVERT(VARCHAR(36), NEWID());
    DECLARE @sp_name VARCHAR(200), @view_name NVARCHAR(200), @load_type VARCHAR(20);
    DECLARE @wm_col NVARCHAR(100), @pk_col NVARCHAR(500), @last_wm VARCHAR(200);
    DECLARE @dt_key NVARCHAR(100), @dt_range_days INT;
    DECLARE @rows BIGINT, @sql NVARCHAR(4000), @full_target NVARCHAR(500);
    DECLARE @new_wm VARCHAR(200), @err VARCHAR(4000);

    -- 1. READ CONFIG
    EXEC sp_executesql
        N'SELECT @o1=sp_name,@o2=view_name,@o3=load_type,@o4=watermark_column,@o5=primary_key,@o6=last_watermark_value,@o7=date_key,@o8=date_range_days FROM meta.sp_registry WHERE target_schema=@p1 AND target_table=@p2',
        N'@p1 VARCHAR(50),@p2 VARCHAR(200),@o1 VARCHAR(200) OUT,@o2 NVARCHAR(200) OUT,@o3 VARCHAR(20) OUT,@o4 NVARCHAR(100) OUT,@o5 NVARCHAR(500) OUT,@o6 VARCHAR(200) OUT,@o7 NVARCHAR(100) OUT,@o8 INT OUT',
        @p1=@target_schema,@p2=@target_table,@o1=@sp_name OUT,@o2=@view_name OUT,@o3=@load_type OUT,@o4=@wm_col OUT,@o5=@pk_col OUT,@o6=@last_wm OUT,@o7=@dt_key OUT,@o8=@dt_range_days OUT;

    IF @sp_name IS NULL BEGIN RAISERROR('Table %s.%s not found in sp_registry',16,1,@target_schema,@target_table); RETURN; END
    SET @full_target = QUOTENAME(@target_schema) + N'.' + QUOTENAME(@target_table);

    -- 2. LOG START
    EXEC meta.usp_log_run @run_id, @sp_name, 'running', @load_type = @load_type;

    BEGIN TRY
        -- Helper: check table exists
        DECLARE @tbl_exists INT = 0;
        EXEC sp_executesql N'SELECT @out=COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name=@s AND t.name=@t',
            N'@s VARCHAR(50),@t VARCHAR(200),@out INT OUT', @s=@target_schema,@t=@target_table,@out=@tbl_exists OUT;

        -- ═══ OVERWRITE ═══
        IF @load_type = 'overwrite'
        BEGIN
            IF @view_name IS NULL BEGIN RAISERROR('overwrite requires view_name',16,1); RETURN; END
            SET @sql = N'DROP TABLE IF EXISTS ' + @full_target; EXEC sp_executesql @sql;
            SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
        END

        -- ═══ INCREMENTAL ═══
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
                EXEC sp_executesql N'UPDATE meta.sp_registry SET last_watermark_value=@wm WHERE target_schema=@s AND target_table=@t',
                    N'@wm VARCHAR(200),@s VARCHAR(50),@t VARCHAR(200)', @wm=@new_wm,@s=@target_schema,@t=@target_table;
        END

        -- ═══ UPSERT (DELETE matching + INSERT) ═══
        ELSE IF @load_type = 'upsert'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('upsert requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@pk_col) + N' IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N')'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
        END

        -- ═══ DATEKEY (delete today + insert today) ═══
        ELSE IF @load_type = 'datekey'
        BEGIN
            DECLARE @dk NVARCHAR(100) = COALESCE(@dt_key, @wm_col);
            IF @dk IS NULL BEGIN RAISERROR('datekey requires date_key or watermark_column',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE CAST(' + QUOTENAME(@dk) + N' AS DATE) = CAST(GETDATE() AS DATE)'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name + N' WHERE CAST(' + QUOTENAME(@dk) + N' AS DATE) = CAST(GETDATE() AS DATE)'; EXEC sp_executesql @sql;
            END
        END

        -- ═══ DATERANGE (delete N days + insert N days) ═══
        ELSE IF @load_type = 'daterange'
        BEGIN
            DECLARE @dr_col NVARCHAR(100) = COALESCE(@dt_key, @wm_col);
            DECLARE @neg_days INT = -1 * COALESCE(@dt_range_days, 30);
            IF @dr_col IS NULL BEGIN RAISERROR('daterange requires date_key or watermark_column',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@dr_col) + N' >= DATEADD(DAY,@d,CAST(GETDATE() AS DATE))';
                EXEC sp_executesql @sql, N'@d INT', @d=@neg_days;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name + N' WHERE ' + QUOTENAME(@dr_col) + N' >= DATEADD(DAY,@d,CAST(GETDATE() AS DATE))';
                EXEC sp_executesql @sql, N'@d INT', @d=@neg_days;
            END
        END

        -- ═══ IDENTITY (append WHERE pk > MAX) ═══
        ELSE IF @load_type = 'identity'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('identity requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                DECLARE @max_pk NVARCHAR(200);
                SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@pk_col) + N') AS NVARCHAR(200)) FROM ' + @full_target;
                EXEC sp_executesql @sql, N'@out NVARCHAR(200) OUT', @out=@max_pk OUT;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name + N' WHERE ' + QUOTENAME(@pk_col) + N' > @mx';
                EXEC sp_executesql @sql, N'@mx NVARCHAR(200)', @mx=@max_pk;
            END
        END

        -- ═══ CDC (apply changes from CDC log view) ═══
        ELSE IF @load_type = 'cdc'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('cdc requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                SET @sql = N'DELETE FROM ' + @full_target + N' WHERE ' + QUOTENAME(@pk_col) + N' IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N')'; EXEC sp_executesql @sql;
                SET @sql = N'INSERT INTO ' + @full_target + N' SELECT *,CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt FROM ' + @view_name; EXEC sp_executesql @sql;
            END
            IF @wm_col IS NOT NULL
            BEGIN
                SET @sql = N'SELECT @out=CAST(MAX(' + QUOTENAME(@wm_col) + N') AS VARCHAR(200)) FROM ' + @full_target;
                EXEC sp_executesql @sql, N'@out VARCHAR(200) OUT', @out=@new_wm OUT;
                IF @new_wm IS NOT NULL
                    EXEC sp_executesql N'UPDATE meta.sp_registry SET last_watermark_value=@wm WHERE target_schema=@s AND target_table=@t',
                        N'@wm VARCHAR(200),@s VARCHAR(50),@t VARCHAR(200)', @wm=@new_wm,@s=@target_schema,@t=@target_table;
            END
        END

        -- ═══ SCD2 (close old versions + insert new) ═══
        ELSE IF @load_type = 'scd2'
        BEGIN
            IF @pk_col IS NULL BEGIN RAISERROR('scd2 requires primary_key',16,1); RETURN; END
            IF @tbl_exists = 0
            BEGIN
                SET @sql = N'CREATE TABLE ' + @full_target + N' AS SELECT *,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)) AS _scd2_start_dt,'
                    + N'CAST(''9999-12-31'' AS DATETIME2(6)) AS _scd2_end_dt,'
                    + N'CAST(1 AS INT) AS _scd2_is_current,'
                    + N'CAST(1 AS INT) AS _scd2_version,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)) AS _load_dt'
                    + N' FROM ' + @view_name;
                EXEC sp_executesql @sql;
            END
            ELSE
            BEGIN
                -- Close changed rows
                SET @sql = N'UPDATE ' + @full_target + N' SET _scd2_end_dt=CAST(GETUTCDATE() AS DATETIME2(6)),_scd2_is_current=0'
                    + N' WHERE _scd2_is_current=1 AND ' + QUOTENAME(@pk_col) + N' IN ('
                    + N'SELECT src.' + QUOTENAME(@pk_col) + N' FROM ' + @view_name + N' src'
                    + N' INNER JOIN ' + @full_target + N' tgt ON src.' + QUOTENAME(@pk_col) + N'=tgt.' + QUOTENAME(@pk_col)
                    + N' WHERE tgt._scd2_is_current=1)';
                EXEC sp_executesql @sql;

                -- Insert new versions + new rows
                SET @sql = N'INSERT INTO ' + @full_target
                    + N' SELECT src.*,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6)),'
                    + N'CAST(''9999-12-31'' AS DATETIME2(6)),'
                    + N'1,'
                    + N'COALESCE(v.mx,0)+1,'
                    + N'CAST(GETUTCDATE() AS DATETIME2(6))'
                    + N' FROM ' + @view_name + N' src'
                    + N' LEFT JOIN (SELECT ' + QUOTENAME(@pk_col) + N',MAX(_scd2_version) AS mx FROM ' + @full_target + N' GROUP BY ' + QUOTENAME(@pk_col) + N') v'
                    + N' ON src.' + QUOTENAME(@pk_col) + N'=v.' + QUOTENAME(@pk_col)
                    + N' WHERE src.' + QUOTENAME(@pk_col) + N' NOT IN (SELECT ' + QUOTENAME(@pk_col) + N' FROM ' + @full_target + N' WHERE _scd2_is_current=1)';
                EXEC sp_executesql @sql;
            END
        END

        ELSE BEGIN RAISERROR('Unsupported load_type: %s',16,1,@load_type); RETURN; END

        -- COUNT + LOG
        SET @sql = N'SELECT @out=COUNT(*) FROM ' + @full_target;
        EXEC sp_executesql @sql, N'@out BIGINT OUT', @out=@rows OUT;
        EXEC meta.usp_log_run @run_id, @sp_name, 'success', @rows_affected = @rows, @load_type = @load_type;

    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
        EXEC meta.usp_log_run @run_id, @sp_name, 'failed', @error_message = @err, @load_type = @load_type;
        THROW;
    END CATCH
END
