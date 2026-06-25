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

        -- Always log update event (Enterprise ETL's pattern: INSERT into UpdateLog, batch-sync later)
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
