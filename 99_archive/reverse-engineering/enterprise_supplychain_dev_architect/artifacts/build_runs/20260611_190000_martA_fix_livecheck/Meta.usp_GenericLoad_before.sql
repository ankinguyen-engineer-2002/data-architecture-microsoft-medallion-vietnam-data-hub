-- ---- [SQL_STORED_PROCEDURE] Meta.usp_GenericLoad ----

CREATE   PROCEDURE Meta.usp_GenericLoad
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

        -- ═══ VIEW (view-only — no materialization, skip) ═══
        IF @load_type = 'view'
        BEGIN
            EXEC Meta.usp_LogRun @run_id, @asset_id, 'success';
            RETURN;
        END

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