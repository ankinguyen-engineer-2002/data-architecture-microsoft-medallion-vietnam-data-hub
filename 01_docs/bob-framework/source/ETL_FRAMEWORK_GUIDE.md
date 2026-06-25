# ETL_Framework Developer Guide

## Overview

The `ETL_Framework` is a shared, centrally-managed framework deployed to all Fabric workspaces that provides standardized audit logging, metadata tracking, and data curation procedures.

**Key Role:** Enable consistent monitoring, SLA compliance tracking, and reusable ETL patterns across all warehouse tiers.

---

## Framework Architecture

### Project Location and Deployment

**Repository Location:**
```
c:\Projects\EDW-Fabric\ETL_Framework\
├── ETL_Framework.sqlproj
├── DW_Developer/
│   ├── Tables/
│   ├── Stored Procedures/
│   └── Functions/
├── Performance_Logs/
├── SecurityAccess/
└── Publish Profiles/
    ├── ETL_Framework_Dev.publish.xml
    └── ETL_Framework_Prod.publish.xml
```

**Deployment Pattern:**
- Single source of truth in repository
- Deployed to **Enterprise_Data Workspace** (primary)
- Copied to all Business Unit workspaces
- Referenced via `[$(ETL_Framework)]` SqlCmdVariable

**Deployment Scope:**
```
Enterprise_Data Workspace
├── [$(ETL_Framework)] (Primary instance)

Business Unit Workspace (Retail)
├── [$(ETL_Framework)] (Copy - read-only)

Business Unit Workspace (Finance)
├── [$(ETL_Framework)] (Copy - read-only)

Business Unit Workspace (Sales)
├── [$(ETL_Framework)] (Copy - read-only)
```

### Schema Organization

#### DW_Developer Schema

**Purpose:** Core audit, metadata, and framework procedures

**Objects:**

```sql
Tables:
├── AuditLog              -- Procedure execution and data modification logs
├── TableDictionary       -- Metadata and SLA tracking
├── PerformanceLog        -- Query execution time tracking

Stored Procedures:
├── usp_LogAuditEntry     -- Insert audit entry
├── usp_UpdateTableMetadata -- Update table metadata and SLA
├── usp_CurateData_SCD2   -- Slowly Changing Dimension Type 2 logic
├── usp_CurateData_Incremental -- Incremental load logic
├── usp_CurateData_Deduplicate -- Deduplication logic
├── usp_CheckSLACompliance  -- Verify SLA status
└── usp_ArchiveAuditLogs  -- Archive old audit entries

Functions:
├── fn_GetDate            -- Return CSTDateValue for consistent timing
└── fn_IsSLAMet           -- Check if table meets SLA
```

#### Performance_Logs Schema

**Purpose:** Track query performance and optimization opportunities

**Objects:**
```sql
Tables:
├── QueryPerformance      -- Query execution metrics
├── IndexUtilization      -- Index usage statistics
└── SlowQueries           -- Queries exceeding threshold

Views:
├── v_AverageQueryTime    -- Average execution time by stored procedure
├── v_TopSlowQueries      -- Top 10 slowest queries
└── v_UnusedIndexes       -- Indexes not being used
```

#### SecurityAccess Schema

**Purpose:** Row-level security and access control policies

**Objects:**
```sql
Tables:
├── UserRoles             -- User and role assignments
├── DataAccessRules       -- RLS policy definitions

Policies:
├── SecurityPolicy_AuditLog    -- Restrict audit log visibility
└── SecurityPolicy_Sensitive   -- Restrict sensitive data access
```

---

## Core Tables

### AuditLog Table

**Purpose:** Track every procedure execution, data modification, and process status

**Full Schema:**
```sql
CREATE TABLE [DW_Developer].[AuditLog] (
    AuditLogID BIGINT PRIMARY KEY IDENTITY(1,1),
    
    -- Process Identification
    ProcedureName NVARCHAR(255) NOT NULL,  -- Format: 'DatabaseName.SchemaName.ProcedureName'
    ExecutedBy NVARCHAR(255) NOT NULL,     -- SYSTEM_USER
    
    -- Timing
    ExecutionStart DATETIME NOT NULL,      -- Process start timestamp
    ExecutionEnd DATETIME,                 -- Process end timestamp (NULL if in progress)
    
    -- Execution Details
    Status NVARCHAR(50) NOT NULL,          -- 'Process Start', 'Process Complete', 'Error', 'In Progress'
    RecordsAffected INT,                   -- Rows inserted/updated/deleted
    ErrorMessage NVARCHAR(MAX),            -- Full error details if failed
    ExecutionDurationSeconds AS 
        DATEDIFF(SECOND, ExecutionStart, ExecutionEnd),  -- Computed column
    
    -- Source/Target Information
    SourceTable NVARCHAR(255),             -- Source table for load
    TargetTable NVARCHAR(255),             -- Target table for load
    
    -- Metadata
    CreatedDate DATETIME DEFAULT GETDATE(),
    ModifiedDate DATETIME DEFAULT GETDATE()
);
```

**Indexes:**
```sql
CREATE CLUSTERED INDEX IX_AuditLog_ExecutionStart 
    ON [DW_Developer].[AuditLog](ExecutionStart DESC);

CREATE NONCLUSTERED INDEX IX_AuditLog_ProcedureName 
    ON [DW_Developer].[AuditLog](ProcedureName, ExecutionStart DESC);

CREATE NONCLUSTERED INDEX IX_AuditLog_Status 
    ON [DW_Developer].[AuditLog](Status, ExecutionStart DESC);
```

### TableDictionary Table

**Purpose:** Single source of truth for table metadata, ownership, and SLA

**Full Schema:**
```sql
CREATE TABLE [DW_Developer].[TableDictionary] (
    TableDictionaryID INT PRIMARY KEY IDENTITY(1,1),
    
    -- Table Identification
    DatabaseName NVARCHAR(255) NOT NULL,       -- Database containing table
    SchemaName NVARCHAR(255) NOT NULL,         -- Schema name
    TableName NVARCHAR(255) NOT NULL,          -- Table name
    FullQualifiedName AS CONCAT(DatabaseName, '.', SchemaName, '.', TableName),
    
    -- Classification
    TableType NVARCHAR(50),                    -- 'Fact', 'Dimension', 'Bridge', 'Staging'
    Layer NVARCHAR(50),                        -- 'Bronze', 'Silver', 'Gold'
    SourceSystem NVARCHAR(255),                -- Source system (e.g., 'SAP', 'Salesforce')
    BusinessDomain NVARCHAR(255),              -- Business domain owner
    
    -- SLA Definition
    SLARefreshInterval NVARCHAR(100),          -- 'Real-time', 'Hourly', 'Daily', 'Weekly'
    SLAThresholdMinutes INT,                   -- Max minutes allowed since last refresh
    SLAOwner NVARCHAR(255),                    -- Person responsible for SLA
    
    -- Tracking
    LastModifiedDate DATETIME,                 -- Last update timestamp
    LastModifiedBy NVARCHAR(255),              -- User who last modified
    LastModifiedProcedure NVARCHAR(255),       -- Procedure that last updated table
    RowCount BIGINT,                           -- Current row count
    DataSize BIGINT,                           -- Table size in bytes
    
    -- Quality
    DataQualityScore DECIMAL(5,2),             -- Quality percentage (0-100)
    DataQualityRules NVARCHAR(MAX),            -- CSV of quality rules applied
    LastQualityCheckDate DATETIME,             -- Last quality check timestamp
    
    -- Governance
    Owner NVARCHAR(255),                       -- Data owner/business sponsor
    Steward NVARCHAR(255),                     -- Technical steward
    IsArchived BIT DEFAULT 0,                  -- Soft delete flag
    
    -- Documentation
    Description NVARCHAR(MAX),                 -- Business description
    BusinessRules NVARCHAR(MAX),               -- Key business rules
    DownstreamDependencies NVARCHAR(MAX),      -- Comma-separated list of dependent tables
    
    -- Audit
    CreatedDate DATETIME DEFAULT GETDATE(),
    CreatedBy NVARCHAR(255),
    ModifiedDate DATETIME DEFAULT GETDATE()
);
```

**Indexes:**
```sql
CREATE UNIQUE CLUSTERED INDEX IX_TableDictionary_Key 
    ON [DW_Developer].[TableDictionary](DatabaseName, SchemaName, TableName);

CREATE NONCLUSTERED INDEX IX_TableDictionary_Layer 
    ON [DW_Developer].[TableDictionary](Layer, BusinessDomain);

CREATE NONCLUSTERED INDEX IX_TableDictionary_LastModified 
    ON [DW_Developer].[TableDictionary](LastModifiedDate DESC);
```

---

## Core Procedures

### usp_LogAuditEntry

**Purpose:** Standardized audit log insertion for all procedures

**Signature:**
```sql
CREATE PROC [DW_Developer].[usp_LogAuditEntry]
    @ProcedureName NVARCHAR(255),
    @ExecutionStart DATETIME = NULL,
    @ExecutionEnd DATETIME = NULL,
    @Status NVARCHAR(50),
    @RecordsAffected INT = NULL,
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @SourceTable NVARCHAR(255) = NULL,
    @TargetTable NVARCHAR(255) = NULL
AS
```

**Usage in Your Procedures:**
```sql
DECLARE @AuditStart DATETIME = GETDATE();

INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
    (ProcedureName, ExecutionStart, Status, ExecutedBy, SourceTable, TargetTable)
VALUES 
    ('Retail_DW.dbo.usp_Refresh_DimCustomer', @AuditStart, 'Process Start', 
     SYSTEM_USER, 'Source_Data.Customers', 'Retail_DW.DimCustomer');

BEGIN TRY
    -- Your data curation logic
    INSERT INTO [dbo].[DimCustomer] (...)
    SELECT ... FROM [$(Source_Data)].[...];
    
    UPDATE [$(ETL_Framework)].[DW_Developer].[AuditLog]
    SET ExecutionEnd = GETDATE(),
        Status = 'Process Complete',
        RecordsAffected = @@ROWCOUNT
    WHERE ProcedureName = 'Retail_DW.dbo.usp_Refresh_DimCustomer'
      AND ExecutionStart = @AuditStart;
      
END TRY
BEGIN CATCH
    UPDATE [$(ETL_Framework)].[DW_Developer].[AuditLog]
    SET ExecutionEnd = GETDATE(),
        Status = 'Error',
        ErrorMessage = ERROR_MESSAGE()
    WHERE ProcedureName = 'Retail_DW.dbo.usp_Refresh_DimCustomer'
      AND ExecutionStart = @AuditStart;
      
    THROW;
END CATCH;
```

### usp_UpdateTableMetadata

**Purpose:** Update table dictionary after successful data loads

**Signature:**
```sql
CREATE PROC [DW_Developer].[usp_UpdateTableMetadata]
    @DatabaseName NVARCHAR(255),
    @SchemaName NVARCHAR(255),
    @TableName NVARCHAR(255),
    @RowCount BIGINT = NULL,
    @DataQualityScore DECIMAL(5,2) = NULL,
    @LastModifiedBy NVARCHAR(255) = NULL,
    @LastModifiedProcedure NVARCHAR(255) = NULL
AS
```

**Usage in Your Procedures:**
```sql
-- After successful load
EXEC [$(ETL_Framework)].[DW_Developer].[usp_UpdateTableMetadata]
    @DatabaseName = 'Retail_DW',
    @SchemaName = 'dbo',
    @TableName = 'DimCustomer',
    @RowCount = (SELECT COUNT(*) FROM [dbo].[DimCustomer]),
    @DataQualityScore = 99.5,
    @LastModifiedBy = SYSTEM_USER,
    @LastModifiedProcedure = 'Retail_DW.dbo.usp_Refresh_DimCustomer';
```

### usp_CurateData_SCD2

**Purpose:** Slowly Changing Dimension Type 2 implementation (track history)

**Pattern Usage:**
```sql
-- Load new/changed dimensional data with effective date tracking
EXEC [$(ETL_Framework)].[DW_Developer].[usp_CurateData_SCD2]
    @TargetTableName = 'DimProduct',
    @BusinessKeyColumns = 'ProductID',
    @EffectiveDate = CAST(GETDATE() AS DATE),
    @ExpiryDate = '9999-12-31';
```

### usp_CurateData_Incremental

**Purpose:** Load only changed data since last run (incremental pattern)

**Pattern Usage:**
```sql
-- Load only records modified since last run
DECLARE @LastRunDate DATETIME;
SELECT @LastRunDate = MAX(LastModifiedDate) 
FROM [$(ETL_Framework)].[DW_Developer].[TableDictionary]
WHERE TableName = 'FactSales';

INSERT INTO [dbo].[FactSales]
SELECT *
FROM [$(Retail_Warehouse)].[dbo].[FactSalesStaging] fs
WHERE fs.ModifiedDate > @LastRunDate;
```

---

## Core Functions

### fn_GetDate

**Purpose:** Return consistent CST date/time for all procedures

**Usage:**
```sql
DECLARE @DateValue DATETIME = GETDATE();
SELECT @DateValue = CSTDateValue 
FROM [$(ETL_Framework)].[DW_Developer].[fn_GetDate](@DateValue);

-- Use @DateValue for all timestamps to ensure consistency across processes
```

### fn_IsSLAMet

**Purpose:** Check if table meets its SLA requirement

**Usage:**
```sql
DECLARE @IsSLAMet BIT;
SELECT @IsSLAMet = [dbo].[fn_IsSLAMet]('Retail_DW', 'dbo', 'DimCustomer');

IF @IsSLAMet = 0
    THROW 50001, 'SLA not met for DimCustomer - refresh overdue', 1;
```

---

## Standard Procedure Template

Use this template for all new stored procedures:

```sql
CREATE PROC [Schema].[usp_Refresh_ObjectName]
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE 
        @ProcName VARCHAR(500),
        @DateValue DATETIME,
        @User VARCHAR(500),
        @RecordCount INT,
        @AuditStart DATETIME;
    
    -- Initialize variables
    SET @ProcName = '[Schema].[usp_Refresh_ObjectName]';
    SET @User = SYSTEM_USER;
    SET @DateValue = GETDATE();
    SET @AuditStart = @DateValue;
    
    -- Get consistent date value
    SELECT @DateValue = CSTDateValue 
    FROM [$(ETL_Framework)].[DW_Developer].[fn_GetDate](@DateValue);
    
    -- Log process start
    INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
        (ProcedureName, ExecutionStart, Status, ExecutedBy, SourceTable, TargetTable)
    VALUES 
        (@ProcName, @AuditStart, 'Process Start', @User, 
         'SourceTable', '[Schema].[TargetTable]');
    
    BEGIN TRY
        -- Your data transformation logic here
        INSERT INTO [Schema].[TargetTable] (...)
        SELECT ...
        FROM [$(Source_Data)].[...]
        WHERE ...;
        
        SET @RecordCount = @@ROWCOUNT;
        
        -- Log successful completion
        UPDATE [$(ETL_Framework)].[DW_Developer].[AuditLog]
        SET ExecutionEnd = GETDATE(),
            Status = 'Process Complete',
            RecordsAffected = @RecordCount
        WHERE ProcedureName = @ProcName
          AND ExecutionStart = @AuditStart;
        
        -- Update table metadata
        EXEC [$(ETL_Framework)].[DW_Developer].[usp_UpdateTableMetadata]
            @DatabaseName = 'YourDatabase',
            @SchemaName = 'Schema',
            @TableName = 'TargetTable',
            @RowCount = (SELECT COUNT(*) FROM [Schema].[TargetTable]),
            @DataQualityScore = 99.0,
            @LastModifiedBy = @User,
            @LastModifiedProcedure = @ProcName;
        
        IF @DebugMode = 1
            PRINT @ProcName + ' completed successfully. Rows affected: ' + CAST(@RecordCount AS VARCHAR);
            
    END TRY
    BEGIN CATCH
        -- Log error
        UPDATE [$(ETL_Framework)].[DW_Developer].[AuditLog]
        SET ExecutionEnd = GETDATE(),
            Status = 'Error',
            ErrorMessage = ERROR_MESSAGE()
        WHERE ProcedureName = @ProcName
          AND ExecutionStart = @AuditStart;
        
        IF @DebugMode = 1
            PRINT 'Error in ' + @ProcName + ': ' + ERROR_MESSAGE();
            
        THROW;
    END CATCH;
END;
```

---

## Monitoring and Reporting

### Key Queries for Monitoring

**View Recent Procedure Executions:**
```sql
SELECT TOP 20 
    ProcedureName,
    ExecutionStart,
    ExecutionDurationSeconds,
    Status,
    RecordsAffected,
    ExecutedBy
FROM [$(ETL_Framework)].[DW_Developer].[AuditLog]
ORDER BY ExecutionStart DESC;
```

**Check SLA Compliance:**
```sql
SELECT 
    TableName,
    SLARefreshInterval,
    SLAThresholdMinutes,
    LastModifiedDate,
    DATEDIFF(minute, LastModifiedDate, GETDATE()) AS MinutesSinceRefresh,
    CASE 
        WHEN DATEDIFF(minute, LastModifiedDate, GETDATE()) > SLAThresholdMinutes 
        THEN 'VIOLATED'
        ELSE 'MET'
    END AS SLAStatus
FROM [$(ETL_Framework)].[DW_Developer].[TableDictionary]
WHERE Layer IN ('Silver', 'Gold')
ORDER BY MinutesSinceRefresh DESC;
```

**View Slow Queries:**
```sql
SELECT TOP 10 
    ProcedureName,
    AVG(ExecutionDurationSeconds) AS AvgDurationSeconds,
    COUNT(*) AS ExecutionCount
FROM [$(ETL_Framework)].[DW_Developer].[AuditLog]
WHERE Status = 'Process Complete'
  AND ExecutionDurationSeconds > 300  -- > 5 minutes
GROUP BY ProcedureName
ORDER BY AvgDurationSeconds DESC;
```

---

## Best Practices

1. **Always use usp_LogAuditEntry** - Never skip audit logging
2. **Update TableDictionary** - Keep metadata current for SLA tracking
3. **Use fn_GetDate** - Ensures timestamp consistency across procedures
4. **Check SLA before loading** - Prevent cascading SLA violations
5. **Document procedures** - Include data flow comments
6. **Archive old logs** - Call usp_ArchiveAuditLogs monthly
7. **Monitor performance** - Review slow queries regularly
8. **Test SCD logic** - Validate dimension type 2 changes
9. **Validate data quality** - Set appropriate quality scores
10. **Communicate SLA changes** - Update documentation when SLA changes

---

## Troubleshooting

### Audit Log Not Updating

**Check:**
- Framework database accessible? `SELECT * FROM [$(ETL_Framework)].[DW_Developer].[AuditLog]`
- Permissions to insert? Check database user roles
- Correct procedure name format? Should be: `Database.Schema.Procedure`

### SLA Violation Alerts

**Response:**
1. Check audit logs for failures
2. Verify data source is available
3. Check for performance degradation
4. Increase threshold if appropriate
5. Notify SLA owner

---

## Related Documentation

- [FABRIC_ARCHITECTURE_AND_STANDARDS.md](./FABRIC_ARCHITECTURE_AND_STANDARDS.md)
- [SQLPROJ_BEST_PRACTICES.md](./SQLPROJ_BEST_PRACTICES.md)


