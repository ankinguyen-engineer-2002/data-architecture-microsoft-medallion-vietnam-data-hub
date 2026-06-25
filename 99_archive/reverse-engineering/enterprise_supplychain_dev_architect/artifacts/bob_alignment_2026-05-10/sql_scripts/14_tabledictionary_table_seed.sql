-- 14_tabledictionary_table_seed.sql
-- Convert Meta.vw_TableDictionary (view) → Meta.TableDictionary (TABLE).
-- Mirror Bob's ETL_Framework.DW_Developer.TableDictionary schema (65 cols + 6 VN extensions = 71 total).
-- Also create Meta.TableDictionary_UpdateLog (clone of Bob's update-log pattern).
-- Initial seed from Meta.AssetRegistry (33 rows).

-- ========================================================================
-- 1. Drop the view from step 10
-- ========================================================================
DROP VIEW IF EXISTS Meta.vw_TableDictionary;
GO

-- ========================================================================
-- 2. Create Meta.TableDictionary base table (71 cols)
-- ========================================================================
CREATE TABLE Meta.TableDictionary (
    ServerName                          VARCHAR(50)     NOT NULL,
    DatabaseName                        VARCHAR(150)    NOT NULL,
    SchemaName                          VARCHAR(150)    NOT NULL,
    TableName                           VARCHAR(150)    NOT NULL,
    ObjectType                          VARCHAR(50)     NULL,
    PrimaryKey                          VARCHAR(500)    NULL,
    AlternateKey                        VARCHAR(500)    NULL,
    StorageType                         VARCHAR(50)     NULL,
    RowSToreClusteredKey                VARCHAR(750)    NULL,
    AdditionalIndexes                   VARCHAR(500)    NULL,
    DistributionKey                     VARCHAR(500)    NULL,
    IndexType                           VARCHAR(25)     NULL,
    SourceSystem                        VARCHAR(150)    NULL,
    SourceServer                        VARCHAR(100)    NULL,
    SourceDatabase                      VARCHAR(200)    NULL,
    SourceObject                        VARCHAR(500)    NULL,
    SourceObjectAlias                   VARCHAR(100)    NULL,
    SourcePlatform                      VARCHAR(100)    NULL,
    ReplicatedSource                    VARCHAR(500)    NULL,
    ETLTool                             VARCHAR(50)     NULL,
    PackageName                         VARCHAR(500)    NULL,
    TFSPath                             VARCHAR(400)    NULL,
    JobName                             VARCHAR(100)    NULL,
    JobServer                           VARCHAR(50)     NULL,
    RefreshRate                         INT             NULL,
    RefreshDescription                  VARCHAR(50)     NULL,
    UpdateMethod                        VARCHAR(80)     NULL,
    ExtractQuery                        VARCHAR(8000)   NULL,
    UpdateQuery                         VARCHAR(8000)   NULL,
    AdditionaNotes                      VARCHAR(8000)   NULL,
    InvalidCount                        DECIMAL(12,0)   NULL,
    [RowCount]                          DECIMAL(12,0)   NULL,
    CreateDate                          DATETIME2(6)    NULL,
    Modified                            DATETIME2(6)    NULL,
    CreatedBy                           VARCHAR(200)    NULL,
    ModifiedBy                          VARCHAR(200)    NULL,
    LastAudit                           DATETIME2(6)    NULL,
    ErrorMsg                            VARCHAR(500)    NULL,
    CreatedDate                         DATETIME2(6)    NULL,
    Created                             DATETIME2(6)    NULL,
    SourceObjectType                    VARCHAR(15)     NULL,
    PartitionKey                        VARCHAR(200)    NULL,
    ColumnStatsCount                    INT             NULL,
    ColumnCount                         INT             NULL,
    ColumnStatsLastUpdated              DATETIME2(6)    NULL,
    DeletedRows                         DECIMAL(12,0)   NULL,
    DataLake                            VARCHAR(200)    NULL,
    DataLakeFolder                      VARCHAR(200)    NULL,
    DataLakeFolderArchive               VARCHAR(500)    NULL,
    ReplicatedSourceExpiryHours         INT             NULL,
    ReplicatedSourceArchiveExpiryHours  INT             NULL,
    StageDataLakeFolder                 VARCHAR(150)    NULL,
    LastBatchStartDate                  DATETIME2(6)    NULL,
    LibraryList                         VARCHAR(500)    NULL,
    DateKey                             VARCHAR(50)     NULL,
    DateRangeDays                       INT             NULL,
    OperationKey                        VARCHAR(128)    NULL,
    PII                                 VARCHAR(8000)   NULL,
    ValidKeyValues                      BIT             NULL,
    SelectColumn                        VARCHAR(8000)   NULL,
    DataBricksClusterVersion            VARCHAR(30)     NULL,
    DataBricksNodeType                  VARCHAR(30)     NULL,
    DataBricksClusterRange              VARCHAR(10)     NULL,
    -- VN extensions (6 cols, optional)
    v9_Layer                            VARCHAR(50)     NULL,
    v9_ExecutionOrder                   INT             NULL,
    v9_DependsOn                        VARCHAR(500)    NULL,
    v9_WatermarkColumn                  VARCHAR(100)    NULL,
    v9_LastWatermarkValue               VARCHAR(100)    NULL,
    v9_IsActive                         BIT             NULL
);
GO

-- ========================================================================
-- 3. Create Meta.TableDictionary_UpdateLog (append-only event log)
-- ========================================================================
CREATE TABLE Meta.TableDictionary_UpdateLog (
    UpdateLogID         BIGINT          NOT NULL,
    DatabaseName        VARCHAR(150)    NOT NULL,
    SchemaName          VARCHAR(150)    NOT NULL,
    TableName           VARCHAR(150)    NOT NULL,
    LastUpdated         DATETIME2(6)    NOT NULL,
    UpdateQuery         VARCHAR(5000)   NULL,
    RowsLoaded          BIGINT          NULL,
    AssetID             VARCHAR(128)    NULL,
    RunID               VARCHAR(128)    NULL
);
GO

-- ========================================================================
-- 4. Initial seed from Meta.AssetRegistry (33 rows from Processing+Gold WH)
-- ========================================================================
INSERT INTO Meta.TableDictionary (
    ServerName, DatabaseName, SchemaName, TableName, ObjectType,
    PrimaryKey, StorageType, SourceSystem, SourceObject, SourcePlatform,
    ReplicatedSource, ETLTool, PackageName,
    RefreshRate, RefreshDescription, UpdateMethod, AdditionaNotes,
    [RowCount], Modified, CreatedBy, ModifiedBy, LastAudit,
    DataLake, DataLakeFolder, StageDataLakeFolder,
    LastBatchStartDate, DateKey, DateRangeDays, OperationKey,
    v9_Layer, v9_DependsOn, v9_WatermarkColumn, v9_LastWatermarkValue, v9_IsActive
)
SELECT
    'EDW-Fabric'                          AS ServerName,
    physical_item                         AS DatabaseName,
    physical_schema                       AS SchemaName,
    physical_object                       AS TableName,
    'Table'                               AS ObjectType,
    primary_key                           AS PrimaryKey,
    'Delta'                               AS StorageType,
    project                               AS SourceSystem,
    source_objects                        AS SourceObject,
    source_feed_type                      AS SourcePlatform,
    legacy_view_name                      AS ReplicatedSource,
    'Fabric Pipeline'                     AS ETLTool,
    legacy_sp_name                        AS PackageName,
    CASE frequency
        WHEN 'daily'   THEN 24
        WHEN 'hourly'  THEN 1
        WHEN 'weekly'  THEN 168
        WHEN 'monthly' THEN 720
        ELSE 24
    END                                   AS RefreshRate,
    frequency                             AS RefreshDescription,
    load_type                             AS UpdateMethod,
    staging_reason                        AS AdditionaNotes,
    CAST(rows_loaded AS DECIMAL(12,0))    AS [RowCount],
    last_load_date                        AS Modified,
    owner_name                            AS CreatedBy,
    owner_name                            AS ModifiedBy,
    last_load_date                        AS LastAudit,
    physical_workspace                    AS DataLake,
    physical_item                         AS DataLakeFolder,
    CASE WHEN access_mode IN ('EDWSupplement', 'StageRequired')
         THEN physical_schema ELSE NULL END AS StageDataLakeFolder,
    last_load_date                        AS LastBatchStartDate,
    date_key                              AS DateKey,
    date_range_days                       AS DateRangeDays,
    asset_id                              AS OperationKey,
    canonical_layer                       AS v9_Layer,
    depends_on                            AS v9_DependsOn,
    watermark_column                      AS v9_WatermarkColumn,
    last_watermark_value                  AS v9_LastWatermarkValue,
    is_active                             AS v9_IsActive
FROM Meta.AssetRegistry;
GO
