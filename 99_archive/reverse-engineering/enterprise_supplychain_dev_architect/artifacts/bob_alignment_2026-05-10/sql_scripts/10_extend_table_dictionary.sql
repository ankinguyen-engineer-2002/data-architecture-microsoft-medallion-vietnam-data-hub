-- 10_extend_table_dictionary.sql
-- DROP + CREATE Meta.vw_TableDictionary with full 65-col schema matching Bob's
-- ETL_Framework.DW_Developer.TableDictionary (EnterpriseData-Dev workspace).
--
-- Bob's schema observed via repo scan: 65 cols including ServerName, DatabaseName,
-- SchemaName, TableName, ObjectType, PrimaryKey, AlternateKey, StorageType,
-- DistributionKey, IndexType, SourceSystem, ETLTool, RefreshRate, UpdateMethod,
-- UpdateQuery, ExtractQuery, RowCount, Modified, LastAudit, ErrorMsg, etc.

DROP VIEW IF EXISTS Meta.vw_TableDictionary;
GO

CREATE VIEW Meta.vw_TableDictionary AS
SELECT
    'EDW-Fabric'                          AS ServerName,
    physical_item                         AS DatabaseName,
    physical_schema                       AS SchemaName,
    physical_object                       AS TableName,
    'Table'                               AS ObjectType,
    primary_key                           AS PrimaryKey,
    CAST(NULL AS VARCHAR(500))            AS AlternateKey,
    'Delta'                               AS StorageType,
    CAST(NULL AS VARCHAR(750))            AS RowSToreClusteredKey,
    CAST(NULL AS VARCHAR(500))            AS AdditionalIndexes,
    CAST(NULL AS VARCHAR(500))            AS DistributionKey,
    CAST(NULL AS VARCHAR(25))             AS IndexType,
    project                               AS SourceSystem,
    CAST(NULL AS VARCHAR(100))            AS SourceServer,
    CAST(NULL AS VARCHAR(200))            AS SourceDatabase,
    source_objects                        AS SourceObject,
    CAST(NULL AS VARCHAR(100))            AS SourceObjectAlias,
    source_feed_type                      AS SourcePlatform,
    legacy_view_name                      AS ReplicatedSource,
    'Fabric Pipeline'                     AS ETLTool,
    legacy_sp_name                        AS PackageName,
    CAST(NULL AS VARCHAR(400))            AS TFSPath,
    CAST(NULL AS VARCHAR(100))            AS JobName,
    CAST(NULL AS VARCHAR(50))             AS JobServer,
    CASE frequency
        WHEN 'daily'   THEN 24
        WHEN 'hourly'  THEN 1
        WHEN 'weekly'  THEN 168
        WHEN 'monthly' THEN 720
        ELSE 24
    END                                   AS RefreshRate,
    frequency                             AS RefreshDescription,
    load_type                             AS UpdateMethod,
    CAST(NULL AS VARCHAR(8000))           AS ExtractQuery,
    CAST(NULL AS VARCHAR(8000))           AS UpdateQuery,
    staging_reason                        AS AdditionaNotes,
    CAST(NULL AS DECIMAL(12,0))           AS InvalidCount,
    CAST(rows_loaded AS DECIMAL(12,0))    AS [RowCount],
    CAST(NULL AS DATETIME2(6))            AS CreateDate,
    last_load_date                        AS Modified,
    owner_name                            AS CreatedBy,
    owner_name                            AS ModifiedBy,
    last_load_date                        AS LastAudit,
    CAST(NULL AS VARCHAR(500))            AS ErrorMsg,
    CAST(NULL AS DATETIME2(6))            AS CreatedDate,
    CAST(NULL AS DATETIME2(6))            AS Created,
    CAST(NULL AS VARCHAR(15))             AS SourceObjectType,
    CAST(NULL AS VARCHAR(200))            AS PartitionKey,
    CAST(NULL AS INT)                     AS ColumnStatsCount,
    CAST(NULL AS INT)                     AS ColumnCount,
    CAST(NULL AS DATETIME2(6))            AS ColumnStatsLastUpdated,
    CAST(NULL AS DECIMAL(12,0))           AS DeletedRows,
    physical_workspace                    AS DataLake,
    physical_item                         AS DataLakeFolder,
    CAST(NULL AS VARCHAR(500))            AS DataLakeFolderArchive,
    CAST(NULL AS INT)                     AS ReplicatedSourceExpiryHours,
    CAST(NULL AS INT)                     AS ReplicatedSourceArchiveExpiryHours,
    CASE WHEN access_mode IN ('EDWSupplement', 'StageRequired')
         THEN physical_schema ELSE NULL END AS StageDataLakeFolder,
    last_load_date                        AS LastBatchStartDate,
    CAST(NULL AS VARCHAR(500))            AS LibraryList,
    date_key                              AS DateKey,
    date_range_days                       AS DateRangeDays,
    asset_id                              AS OperationKey,
    CAST(NULL AS VARCHAR(8000))           AS PII,
    CAST(NULL AS BIT)                     AS ValidKeyValues,
    CAST(NULL AS VARCHAR(8000))           AS SelectColumn,
    CAST(NULL AS VARCHAR(30))             AS DataBricksClusterVersion,
    CAST(NULL AS VARCHAR(30))             AS DataBricksNodeType,
    CAST(NULL AS VARCHAR(10))             AS DataBricksClusterRange,
    canonical_layer                       AS v9_Layer,
    CAST(NULL AS INT)                     AS v9_ExecutionOrder,
    depends_on                            AS v9_DependsOn,
    watermark_column                      AS v9_WatermarkColumn,
    last_watermark_value                  AS v9_LastWatermarkValue,
    is_active                             AS v9_IsActive
FROM Meta.AssetRegistry;
GO
