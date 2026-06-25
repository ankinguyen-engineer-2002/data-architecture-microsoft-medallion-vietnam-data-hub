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
