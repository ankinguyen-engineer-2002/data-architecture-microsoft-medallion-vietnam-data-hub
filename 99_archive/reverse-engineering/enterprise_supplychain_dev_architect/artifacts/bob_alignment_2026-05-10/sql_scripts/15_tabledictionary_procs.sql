-- 15_tabledictionary_procs.sql
-- Port 3 procs from Bob's ETL_Framework pattern, adapted to Meta schema:
--   1. usp_UpdateTableDictionary_ModifiedDate — per-load INSERT/UPDATE entry
--   2. usp_UpdateTableDictionaryModified — batch sync Modified from UpdateLog
--   3. usp_RefreshTableStats — probe sys.indexes/sys.columns to populate ColumnCount/IndexType/PartitionKey/etc.

-- ========================================================================
-- Proc 1: usp_UpdateTableDictionary_ModifiedDate
-- Mirrors Bob's [DW_Developer].[usp_UpdateTableDictionary_ModifiedDate]
--   Behaviour:
--     - If row not in TableDictionary: INSERT base row (8 cols)
--     - Always: INSERT into TableDictionary_UpdateLog
--     - Logs Process Start / Process End to AuditLog
-- ========================================================================
DROP PROCEDURE IF EXISTS Meta.usp_UpdateTableDictionary_ModifiedDate;
GO

CREATE PROCEDURE Meta.usp_UpdateTableDictionary_ModifiedDate
    @DestinationDatabase VARCHAR(150),
    @DestinationSchema   VARCHAR(150),
    @DestinationTable    VARCHAR(150),
    @UpdateQuery         VARCHAR(5000) = NULL,
    @DateValue           DATETIME2(6)  = NULL,
    @RowsLoaded          BIGINT        = NULL,
    @AssetID             VARCHAR(128)  = NULL,
    @RunID               VARCHAR(128)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @String VARCHAR(500), @User VARCHAR(200);
    DECLARE @Exists INT;
    DECLARE @AuditID BIGINT;
    DECLARE @LogID   BIGINT;

    SET @String = CONCAT('Meta.usp_UpdateTableDictionary_ModifiedDate: ',
                         @DestinationDatabase, '.', @DestinationSchema, '.', @DestinationTable);
    SET @User = SYSTEM_USER;

    IF @DateValue IS NULL
        SET @DateValue = Meta.ufn_utc_to_cst(CAST(GETUTCDATE() AS DATETIME2(6)));
    IF @UpdateQuery IS NULL
        SET @UpdateQuery = '';

    SET @AuditID = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);

    INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command, Description, AssetID, RunID, Severity, LoadDT)
    VALUES (@AuditID, @DateValue, @User, 'Process Start', @String, @AssetID, @RunID, 'INFO', @DateValue);

    BEGIN TRY
        SELECT @Exists = COUNT(*)
        FROM Meta.TableDictionary
        WHERE DatabaseName = @DestinationDatabase
          AND SchemaName   = @DestinationSchema
          AND TableName    = @DestinationTable;

        IF @Exists = 0
        BEGIN
            INSERT INTO Meta.TableDictionary
            (ServerName, DatabaseName, SchemaName, TableName, ObjectType,
             StorageType, UpdateQuery, Modified, [RowCount], ETLTool, OperationKey, LastAudit, CreateDate, Created)
            VALUES
            ('EDW-Fabric', @DestinationDatabase, @DestinationSchema, @DestinationTable, 'Table',
             'Delta', @UpdateQuery, @DateValue, CAST(@RowsLoaded AS DECIMAL(12,0)),
             'Fabric Pipeline', @AssetID, @DateValue, @DateValue, @DateValue);
        END

        -- Always log update event (Bob's pattern: INSERT into UpdateLog, batch-sync later)
        SET @LogID = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
        INSERT INTO Meta.TableDictionary_UpdateLog
        (UpdateLogID, DatabaseName, SchemaName, TableName, LastUpdated, UpdateQuery, RowsLoaded, AssetID, RunID)
        VALUES
        (@LogID, @DestinationDatabase, @DestinationSchema, @DestinationTable,
         @DateValue, @UpdateQuery, @RowsLoaded, @AssetID, @RunID);

        SET @AuditID = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
        INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command, Description, AssetID, RunID, Severity, LoadDT)
        VALUES (@AuditID, @DateValue, @User, 'Process End', @String, @AssetID, @RunID, 'INFO', @DateValue);
    END TRY
    BEGIN CATCH
        DECLARE @Err VARCHAR(500) = ERROR_MESSAGE();
        SET @AuditID = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
        INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command, Description, ErrorMessage, AssetID, RunID, Severity, LoadDT)
        VALUES (@AuditID, @DateValue, @User, 'Process Failed', @String, @Err, @AssetID, @RunID, 'ERROR', @DateValue);
        THROW;
    END CATCH
END;
GO

-- ========================================================================
-- Proc 2: usp_UpdateTableDictionaryModified
-- Mirrors Bob's [DW_Developer].[usp_UpdateTableDictionaryModified]
--   Behaviour: batch-sync Modified column from MAX(LastUpdated) of UpdateLog
-- ========================================================================
DROP PROCEDURE IF EXISTS Meta.usp_UpdateTableDictionaryModified;
GO

CREATE PROCEDURE Meta.usp_UpdateTableDictionaryModified
AS
BEGIN
    SET NOCOUNT ON;
    -- Batch sync Modified, RowCount, LastAudit from UpdateLog max(LastUpdated)
    UPDATE td
    SET td.Modified  = ul.MaxLastUpdated,
        td.LastAudit = ul.MaxLastUpdated,
        td.[RowCount] = COALESCE(CAST(ul.MaxRows AS DECIMAL(12,0)), td.[RowCount]),
        td.LastBatchStartDate = ul.MaxLastUpdated
    FROM Meta.TableDictionary AS td
    INNER JOIN (
        SELECT DatabaseName, SchemaName, TableName,
               MAX(LastUpdated) AS MaxLastUpdated,
               MAX(RowsLoaded)  AS MaxRows
        FROM Meta.TableDictionary_UpdateLog
        GROUP BY DatabaseName, SchemaName, TableName
    ) AS ul
        ON td.DatabaseName = ul.DatabaseName
        AND td.SchemaName  = ul.SchemaName
        AND td.TableName   = ul.TableName
    WHERE td.Modified IS NULL OR td.Modified < ul.MaxLastUpdated;
END;
GO

-- ========================================================================
-- Proc 3: usp_RefreshTableStats
-- Probe sys.indexes/sys.columns/sys.partitions to populate
-- ColumnCount, IndexType, PartitionKey, ColumnStatsCount, ColumnStatsLastUpdated, CreateDate
-- (Fabric WH: DistributionKey is auto-managed, kept NULL.)
-- ========================================================================
DROP PROCEDURE IF EXISTS Meta.usp_RefreshTableStats;
GO

CREATE PROCEDURE Meta.usp_RefreshTableStats
AS
BEGIN
    SET NOCOUNT ON;

    -- Update column count from sys.columns
    UPDATE td
    SET td.ColumnCount = c.cnt,
        td.CreateDate  = COALESCE(td.CreateDate, o.create_date),
        td.Created     = COALESCE(td.Created, o.create_date)
    FROM Meta.TableDictionary AS td
    INNER JOIN sys.objects AS o
        ON o.name = td.TableName
       AND o.schema_id = SCHEMA_ID(td.SchemaName)
       AND o.type = 'U'
    INNER JOIN (
        SELECT object_id, COUNT(*) AS cnt
        FROM sys.columns
        GROUP BY object_id
    ) AS c ON c.object_id = o.object_id;

    -- Update index info from sys.indexes
    UPDATE td
    SET td.IndexType = i.type_desc
    FROM Meta.TableDictionary AS td
    INNER JOIN sys.objects AS o
        ON o.name = td.TableName
       AND o.schema_id = SCHEMA_ID(td.SchemaName)
       AND o.type = 'U'
    INNER JOIN (
        SELECT object_id, MAX(type_desc) AS type_desc
        FROM sys.indexes
        WHERE type IN (1, 2, 5, 6)  -- clustered, non-clustered, columnstore, columnstore-clustered
        GROUP BY object_id
    ) AS i ON i.object_id = o.object_id;

    -- Update column stats count from sys.stats
    UPDATE td
    SET td.ColumnStatsCount = s.cnt,
        td.ColumnStatsLastUpdated = s.last_updated
    FROM Meta.TableDictionary AS td
    INNER JOIN sys.objects AS o
        ON o.name = td.TableName
       AND o.schema_id = SCHEMA_ID(td.SchemaName)
       AND o.type = 'U'
    INNER JOIN (
        SELECT object_id,
               COUNT(*) AS cnt,
               MAX(STATS_DATE(object_id, stats_id)) AS last_updated
        FROM sys.stats
        GROUP BY object_id
    ) AS s ON s.object_id = o.object_id;
END;
GO
