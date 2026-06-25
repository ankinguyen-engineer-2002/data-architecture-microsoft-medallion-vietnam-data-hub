# Bob's ETL Framework — Deep Dive Synthesis

**For:** Aric Nguyen, VN SC Team Lead Data Engineer  
**From:** Analysis of EnterpriseData-Dev (WS ID: 5360a935-1984-4775-895f-f4c90bafa19d)  
**Scope:** 35 stored procs across 10 families, TableDictionary architecture, pipeline orchestration patterns  
**Date:** 2026-05-10

---

## Executive Summary

Bob Horton's ETL framework in `ETL_Framework` warehouse is a **metadata-driven, register-based orchestration engine** that decouples data movement logic from table-specific configuration. The framework powers all Bronze→Silver→Gold transformations across 5 domain warehouses via:

- **35 stored procedures** organized into 10 procedural families (parquet-loaders, refresh, incremental, SCD2, snapshot, audit, alert, cleanup, email, other)
- **TableDictionary** (65-column registry) as the single source of truth for data lineage, update methods, refresh rates, SLA tracking
- **AuditLog** + **TableDictionary_UpdateLog** for real-time execution audit trails
- **Metadata-first pattern:** load configuration drives what & when, not hard-coded ETL specs

The architecture prioritizes **governance by metadata** over code flexibility—a deliberate trade-off that enables domain teams (Retail, Wholesale, MasterData, Distribution) to self-serve register new tables without writing T-SQL.

---

## 1. The Brain: ETL_Framework Warehouse

### Purpose & Ownership

`ETL_Framework` (owner: Bob Horton) serves as the **control plane** for the entire workspace:
- Hosts the **35 procedural workhorses** (all in `DW_Developer` schema)
- Owns **14 views** (mostly metadata query helpers)
- Manages **2 logging tables** (AuditLog, TableDictionary) + **1 utility table** (TableDictionary_UpdateLog)
- Integrates with **3 performance tracking schemas** (Performance_Logs: for alerting, email queues; 2 staging schemas for auto-staging)

### TableDictionary Schema (65 columns)

The master registry. Every table touched by the framework must have a row here. Key columns:

| Column Group | Purpose | Columns |
|---|---|---|
| **Identity** | Locate the table | `ServerName`, `DatabaseName`, `SchemaName`, `TableName`, `ObjectType`, `StorageType` |
| **Update Method** | How to load (critical) | `UpdateMethod` (Upsert/Insert/Append/DateKey/DateRange/Identity/CDC/DelInsert/SCD2) |
| **Primary Keys** | For upsert logic | `PrimaryKey`, `AlternateKey`, `DistributionKey` |
| **Date Handling** | For time-windowed loads | `DateKeySource`, `DateKeyDestination`, `DateRangeDays` |
| **Source Reference** | Where data comes from | `ReplicatedSource` (source table full name), `UpdateQuery` (custom WHERE clause) |
| **Scheduling** | SLA tracking | `RefreshRate` (hours), `JobServer`, `JobName`, `Modified` (last load timestamp) |
| **Metadata** | Discovery & lineage | `ColumnCount`, `CreateDate`, `Description`, `Platform` |
| **Audit Control** | Execution tracking | `AuditMode` (full, summary, none), `Audit_TableName` (comparison target for data quality) |
| **Feature Flags** | Load customization | `IsIncrementallyLoaded`, `IsHandledAsReplicated`, `SkipMetadataLoad` (etc.) |

**Why this design:** Eliminates stored proc parameters. A single call like `EXEC usp_RefreshCuratedTableFromView 'Retail_Warehouse','Customers','AccountMaster'` looks up everything from TableDictionary and adapts the load logic at runtime.

### AuditLog Schema

Every proc start/end logs here:

```sql
CREATE TABLE DW_Developer.AuditLog (
    ID BIGINT IDENTITY PRIMARY KEY,
    Description VARCHAR(5000),      -- Proc+DB.Schema.Table identifier
    DateTime DATETIME,               -- CST-adjusted (via fn_GetDate)
    User VARCHAR(500),               -- SYSTEM_USER
    Command VARCHAR(100)             -- 'Process Start', 'Process End', 'Error', 'Data QC Alert'
);
```

**Retention:** No explicit purge documented (⚠️ risk: indefinite growth).

### TableDictionary_UpdateLog (vs RadarSync variant)

Two variants exist:
1. **TableDictionary_UpdateLog** — Standard log of all updates to TableDictionary (via `usp_UpdateTableDictionary_ModifiedDate`)
2. **TableDictionary_UpdateLog_RadarSync** — Specialized log for Databricks Mirror sync operations (`usp_UpdateTableDictionary_UpdateLog_RadarSync`)

Tracks: which column was updated, old/new value, sync timestamp, operation type.

---

## 2. Procedure Family Map (10 families, 35 procs)

### Family 1: Parquet Loaders (12 variants)

**Purpose:** Load Delta tables from ABFSS parquet files in OneLake.

**Why 12 variants?** Bob experimented with different read patterns (OPENROWSET dialects, cursor-based loops, direct COPY INTO). The family evolved through performance optimization.

| Proc | Pattern | Key Feature | Status |
|---|---|---|---|
| `Usp_CreateTableFromParquet` | Base | Validates inputs, TRUNCATE→INSERT via OPENROWSET | Current |
| `Usp_CreateTableFromParquet_V1` | V1 iteration | Larger body (11K chars), pre-cursor era | Legacy |
| `Usp_CreateTableFromParquet_V2` | V2 refined | HOLDING table pattern (drop, insert, swap) to shrink string cols | Current |
| `Usp_CreateTableFromParquet_Simple_NoCursor` | Optimized | No cursor, direct SELECT INTO from OPENROWSET | Preferred for large loads |
| `Usp_CreateTableFromParquet_Straight` | Direct | Simplified template for new tables | Light-use |
| `Usp_TableFromParquet_CopyInto_TruncateLoad` | COPY INTO | Uses `COPY INTO` statement (newer, fastest) | Best for mass ingestion |
| `Usp_TableFromParquet_OpenRowADF` | ADF variant | Integrates with mounted ADF job context | Legacy |
| `Usp_TableFromParquet_OpenRowADF2` | ADF v2 | Simplified ADF integration | Minimal use |
| `Usp_TableFromParquet_OpenRowADFExternal` | External | External table via ADF | Rare |
| `Usp_TableFromParquet_RowADF` | Row-by-row | Cursor iteration (slower) | Deprecated |

**Common pattern (all variants):**

```sql
CREATE PROCEDURE DW_Developer.Usp_CreateTableFromParquet
    @DestinationDatabase NVARCHAR(128),
    @SchemaName NVARCHAR(128),
    @TableName NVARCHAR(128),
    @ParquetPath NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 1. Audit start
    INSERT INTO DW_Developer.AuditLog 
        VALUES (@String, @DateValue, @User, 'Process Start');
    
    BEGIN TRY
        -- 2. Validate inputs (all 4 params checked for NULL/empty)
        
        -- 3. Build full 3-part name: [DB].[Schema].[Table]
        SET @FullTableName = QUOTENAME(@DestinationDatabase) + '.' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
        
        -- 4. TRUNCATE table if exists
        IF OBJECT_ID(@FullTableName, 'U') IS NOT NULL
            TRUNCATE TABLE [dynamic];
        
        -- 5. INSERT FROM OPENROWSET([BULK path], FORMAT='PARQUET')
        --    OR INSERT FROM [external table]
        --    OR COPY INTO [table] FROM [path]
        
        -- 6. Audit success
        INSERT INTO DW_Developer.AuditLog 
            VALUES (@String, @DateValue, @User, 'Process End');
        
    END TRY
    BEGIN CATCH
        -- 7. Audit error with ERROR_MESSAGE()
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        INSERT INTO DW_Developer.AuditLog 
            VALUES (@String, @DateValue, @User, 'Error: ' + @ErrorMsg);
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH;
END;
```

**Inputs:** TableDictionary (to validate if target exists), `fn_GetDate` (CST-adjusted timestamp).  
**Outputs:** AuditLog (start/end/error), target table (bulk loaded), TableDictionary_UpdateLog (if `usp_UpdateTableDictionary_ModifiedDate` called post-load).

**Dependency chain:** Used by pipelines `EDW2FabricLoader`, `Fabric Migration ADF`, `Load MasterData_AFI`, and domain warehouse refresh procs.

---

### Family 2: Refresh / Curated Table Load (6 procs + 114 domain-specific refresh SPs)

**Purpose:** Populate Silver layer domain warehouse tables from Bronze working views.

#### Core Generic Refreshers

| Proc | Signature | Method | Used by |
|---|---|---|---|
| `usp_RefreshCuratedTableFromView` | `(DB, Schema, Table, CheckForEmpty=0)` | View→Table via work table + swap | All 5 domain WHs |
| `usp_RefreshCuratedTableFromView2` | Same | Variant (differ in error handling) | Fallback |
| `usp_UpdateCuratedTableFromView_DateRange` | `(DB, Schema, Table, DateStart, DateEnd)` | Window-based insert (date filter in WHERE) | Incremental reloads |

**The canonical `usp_RefreshCuratedTableFromView` pattern:**

```sql
CREATE PROC [DW_Developer].[usp_RefreshCuratedTableFromView]
    @DestinationDatabase VARCHAR(150),
    @DestinationSchema   VARCHAR(150),
    @DestinationTable    VARCHAR(150),
    @CheckforEmpty       INT = 0
AS
BEGIN
    -- 1. Audit start
    SET @String = 'usp_RefreshCuratedTableFromView: ' + @DestinationDatabase + '.' + @DestinationSchema + '.' + @DestinationTable;
    INSERT INTO DW_Developer.AuditLog VALUES (@String, @DateValue, @User, 'Process Start');
    
    BEGIN TRY
        -- 2. Drop existing work table (_LOAD suffix)
        SET @WorkTable = @DestinationDatabase + '.' + @DestinationSchema + '.' + @DestinationTable + '_LOAD'
        EXECUTE DW_Developer.usp_DropWorkTable @WorkTable;
        
        -- 3. Check if source view has rows (optional, controlled by @CheckforEmpty)
        IF @CheckforEmpty = 1
            SELECT @RowCount = COUNT(*) FROM [source view];
        ELSE
            SET @RowCount = 1;
        
        -- 4. CREATE TABLE work AS SELECT * FROM [source view]
        IF @RowCount > 0
        BEGIN
            EXECUTE (@CreateTableString);
            INSERT INTO @WorkTable SELECT * FROM [source view];
        END;
        
        -- 5. Rename: _LOAD → final table (atomic swap)
        EXECUTE sp_rename @OldName=@WorkTable, @NewName=@DestinationTable;
        
        -- 6. Update TableDictionary.Modified = now
        EXECUTE DW_Developer.usp_UpdateTableDictionary_ModifiedDate 
            @DestinationDatabase, @DestinationSchema, @DestinationTable;
        
        -- 7. Audit end
        INSERT INTO DW_Developer.AuditLog VALUES (@String, @DateValue, @User, 'Process End');
    END TRY
    BEGIN CATCH ... END CATCH;
END;
```

**Source view discovery logic:**  
Looks for view named: `[DestinationDatabase].[DestinationSchema]_Wrk.v_[DestinationTable]`

**Workflow diagram:**
```
Source_Data.[schema]_Wrk.v_[table]  (Bronze working view)
         ↓
  CREATE TABLE [temp_LOAD] AS SELECT * FROM view
         ↓
  sp_rename [temp_LOAD] → [final table]  (atomic swap)
         ↓
  Retail_Warehouse / Wholesale_Warehouse / MasterData_Warehouse (Silver)
         ↓
  AuditLog + TableDictionary_UpdateLog entries
```

**Domain team usage (Wholesale example):**

Wholesale team owns `Usp_Refresh_Wholesale_Warehouse` — a 15K-char proc that chains 120+ EXEC calls, one per table:

```sql
CREATE PROCEDURE dbo.Usp_Refresh_Wholesale_Warehouse
AS
BEGIN
    -- Customers domain
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
        'Wholesale_Warehouse', 'Customers', 'AccountMaster'
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
        'Wholesale_Warehouse', 'Customers', 'CustomerCredit'
    ... (120 more)
END;
```

This proc orchestrates the entire Wholesale refresh without touching the generic framework—domain-agnostic and repeatable.

#### TableDictionary Update Procs

| Proc | Purpose | Trigger |
|---|---|---|
| `usp_UpdateTableDictionary_ModifiedDate` | Upsert row into TableDictionary; update Modified timestamp | After any table load |
| `usp_UpdateTableDictionaryModified` | Variant (legacy) | Occasionally used |
| `usp_UpdateTableDictionary_UpdateLog_RadarSync` | Log Databricks mirror sync operations | After Databricks Mirror refresh |

**Example: `usp_UpdateTableDictionary_ModifiedDate`**

```sql
CREATE PROCEDURE [DW_Developer].[usp_UpdateTableDictionary_ModifiedDate]
    @DestinationDatabase VARCHAR(150),
    @DestinationSchema VARCHAR(150),
    @DestinationTable VARCHAR(150),
    @UpdateQuery VARCHAR(5000) = NULL,
    @DateValue DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Audit start
    INSERT INTO DW_Developer.AuditLog 
        VALUES (@String, @DateValue, @User, 'Process Start');
    
    BEGIN TRY
        -- Check if row exists
        SET @Exists = (
            SELECT COUNT(*)
            FROM DW_Developer.TableDictionary
            WHERE DatabaseName = @DestinationDatabase 
            AND SchemaName = @DestinationSchema   
            AND TableName = @DestinationTable
        );
        
        -- INSERT if new
        IF @Exists = 0 
        BEGIN
            INSERT INTO DW_Developer.TableDictionary
            ( 
                ServerName, DatabaseName, SchemaName, TableName,
                ObjectType, StorageType, UpdateQuery, Modified
            )
            VALUES 
            (
                'EDW-Fabric',
                @DestinationDatabase, @DestinationSchema, @DestinationTable,
                'Table', 'Delta', @UpdateQuery, @DateValue
            );
        END
        
        -- UPDATE Modified date (or MERGE if you prefer)
        -- UPDATE DW_Developer.TableDictionary
        -- SET Modified = @DateValue
        -- WHERE DatabaseName = @DestinationDatabase 
        -- AND SchemaName = @DestinationSchema   
        -- AND TableName = @DestinationTable;
        
        -- Log the update
        INSERT INTO DW_Developer.TableDictionary_UpdateLog (...)
            VALUES (...);
        
    END TRY
    BEGIN CATCH ... END CATCH;
END;
```

**Key insight:** This proc **tolerates missing rows** (creates them if needed) vs. raising errors. Enables resilient orchestration where domain teams can self-register tables.

---

### Family 3: Incremental Table Load (3 procs, 34K+ code)

**Purpose:** Upsert/CDC patterns for tables with natural keys and change tracking.

| Proc | Update Method Support | Use Case |
|---|---|---|
| `usp_IncrementalTableLoad` | Upsert, Insert, Append, DateKey, DateRange, Identity, DelInsert | General-purpose incremental |
| `usp_IncrementalTableLoad_CDC` | CDC (DB2 journals only) | Legacy DB2 change capture |
| `usp_IncrementalTableLoad_Backup` | Upsert, Insert (simplified) | Fallback/legacy version |

**The big one: `usp_IncrementalTableLoad` (34,475 chars)**

Reads from TableDictionary to determine operation:

```sql
-- From TableDictionary row, extract:
@UpdateMethod = 'Upsert'                    -- or Insert, DateKey, Identity, etc.
@DestinationPrimaryKey = 'CustID,OrderID'   -- from PrimaryKey column
@SourceTable = 'Source_Data.Retail_AFI.Order_Raw'  -- from ReplicatedSource column
@DateKeySource = 'LoadDate'                 -- from DateKeySource column
@DateKeyDestination = 'DataAsOfDate'        -- from DateKeyDestination column

-- Switch on UpdateMethod and execute the appropriate pattern:
CASE @UpdateMethod
    WHEN 'Upsert' THEN
        -- Primary key join, update existing, insert missing
        BEGIN TRANSACTION;
        DELETE T FROM @Destination T
        INNER JOIN @Source S ON T.CustID = S.CustID AND T.OrderID = S.OrderID;
        INSERT INTO @Destination SELECT * FROM @Source;
        COMMIT;
    
    WHEN 'Insert' THEN
        -- Insert only missing (by PK)
        INSERT INTO @Destination
        SELECT S.* FROM @Source S
        LEFT JOIN @Destination D ON ...
        WHERE D.PK IS NULL;
    
    WHEN 'DateKey' THEN
        -- Delete rows with OLD DateKey value, insert new
        DELETE FROM @Destination WHERE DataAsOfDate < MAX(LoadDate);
        INSERT INTO @Destination SELECT * FROM @Source;
    
    WHEN 'DateRange' THEN
        -- Use DateRangeDays from TableDictionary
        DECLARE @CutoffDate = DATEADD(DAY, -@DateRangeDays, GETDATE());
        DELETE FROM @Destination WHERE LoadDate >= @CutoffDate;
        INSERT INTO @Destination SELECT * FROM @Source WHERE LoadDate >= @CutoffDate;
    
    WHEN 'Identity' THEN
        -- Append rows with PK > current MAX(PK)
        DECLARE @MaxIdentity = (SELECT MAX(IdentityCol) FROM @Destination);
        INSERT INTO @Destination
        SELECT * FROM @Source WHERE IdentityCol > @MaxIdentity;
    
    -- ... CDC, DelInsert, Append follow same pattern
END CASE;
```

**Error handling:** Explicit transaction + ROLLBACK on error. All operations logged to AuditLog.

---

### Family 4: SCD2 / Slowly Changing Dimension Type 2 (1 proc, 18K chars)

**Purpose:** Track dimension history (e.g., customer profile changes over time).

**Requirements in TableDictionary:**
- `UpdateMethod = 'SCD2'`
- Destination table must have: `EffectiveStartDate`, `EffectiveEndDate`, `IsCurrent` (BIT), `RowVersion` (optional)
- `PrimaryKey` = business key (e.g., CustomerID, not the row ID)

**Logic:**

```sql
-- 1. Load source and destination into temp tables
SELECT [...] INTO #SourceCur FROM [source];
SELECT [...] INTO #DestCurrent FROM [destination] WHERE IsCurrent = 1;

-- 2. Find changed rows (column-by-column comparison)
SELECT S.* INTO #Changed
FROM #SourceCur S
JOIN #DestCurrent D ON S.CustomerID = D.CustomerID
WHERE S.Name != D.Name OR S.Address != D.Address ... (any column differs);

-- 3. Close old rows
UPDATE [destination] 
SET IsCurrent = 0, EffectiveEndDate = GETDATE()
WHERE CustomerID IN (SELECT CustomerID FROM #Changed);

-- 4. Insert new versions of changed rows
INSERT INTO [destination] (CustomerID, Name, Address, ..., EffectiveStartDate, EffectiveEndDate, IsCurrent, RowVersion)
SELECT S.CustomerID, S.Name, S.Address, ..., GETDATE(), '9999-12-31', 1, 1
FROM #Changed S;

-- 5. Insert completely new rows (not in destination)
INSERT INTO [destination] (...)
SELECT ... FROM #SourceCur S
WHERE NOT EXISTS (SELECT 1 FROM #DestCurrent D WHERE D.CustomerID = S.CustomerID);
```

**Audit:** Logged as 'SCD2 Process Start'. Updates AuditLog + TableDictionary.

---

### Family 5: Snapshot Load (1 proc)

**Purpose:** Full table snapshot at a point-in-time (immutable time-series).

```sql
CREATE PROCEDURE DW_Developer.Usp_SnapshotLoad
    @DestinationDatabase NVARCHAR(128),
    @SchemaName          NVARCHAR(128),
    @TableName           NVARCHAR(128),
    @Columns             NVARCHAR(MAX),        -- Column schema for OPENROWSET
    @RelativePath        NVARCHAR(2000),       -- Path in OneLake
    @StageTableName      NVARCHAR(128) = NULL, -- Staging table (if not provided, uses @TableName + '_stage')
    @FileFormat          NVARCHAR(20) = N'PARQUET'
AS
BEGIN
    -- 1. Prepend ABFSS prefix to relative path
    DECLARE @AbfssPrefix NVARCHAR(1000) =
        N'abfss://5360a935-1984-4775-895f-f4c90bafa19d@onelake.dfs.fabric.microsoft.com/ddadbe2e-c2e2-4949-8e84-81eed6a81c9e/Files/';
    
    -- 2. CREATE or TRUNCATE staging table
    -- 3. INSERT INTO staging FROM OPENROWSET (parquet folder)
    -- 4. TRUNCATE target table
    -- 5. INSERT INTO target SELECT * FROM staging
    -- 6. DROP staging
    
    -- Audit logged to AuditLog
END;
```

**Use case:** Time-series immutable landing for point-in-time snapshots (e.g., daily customer account balance).

---

### Family 6: Audit / Data Quality (3 procs)

**Purpose:** Compare tables across environments or validate row counts.

| Proc | Purpose | Compares |
|---|---|---|
| `usp_Audit_ADW_Tables` | Deprecated v1 | ADW (legacy) vs Fabric |
| `usp_Audit_ADW_Tables_V1` | Same as above | ADW vs Fabric |
| `usp_Audit_Fabric_Tables` | Auto-discovery | Fabric `Source_Data_sys` (system views) vs TableDictionary |

**Example: `usp_Audit_Fabric_Tables`**

```sql
CREATE PROCEDURE [DW_Developer].[usp_Audit_Fabric_Tables]
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- 1. Query Fabric system catalog
        SELECT DISTINCT 
            'Source_Data' as DatabaseName,
            SCHEMA_NAME as SchemaName,
            table_name,
            'DELTA' as StorageType,
            COUNT(column_id) as ColumnCount
        INTO #Temp_t
        FROM Centralized_Warehouse.Source_Data_sys.tables T
        JOIN Centralized_Warehouse.Source_Data_sys.Schemas S ON T.schema_id = S.schema_id 
        JOIN Centralized_Warehouse.Source_Data_sys.columns C ON T.object_id = C.object_id
        WHERE SCHEMA_NAME NOT LIKE '%xbk' 
        AND SCHEMA_NAME NOT LIKE '%_aggs'
        AND table_name NOT LIKE '%_Stage' ...;
        
        -- 2. Find new tables (not in TableDictionary yet)
        SELECT A.* INTO #NewRecords
        FROM #Temp_t A
        LEFT JOIN ETL_Framework.[DW_Developer].TableDictionary B 
            ON A.DatabaseName = B.DatabaseName 
            AND A.table_name = B.TableName 
            AND A.SchemaName = B.SchemaName 
        WHERE B.DatabaseName IS NULL;
        
        -- 3. INSERT new rows into TableDictionary
        INSERT INTO DW_Developer.TableDictionary
            (ServerName, DatabaseName, SchemaName, TableName, ObjectType, StorageType, ColumnCount, CreateDate)
        SELECT 'EDW-Fabric', DatabaseName, SchemaName, name, 'Table', StorageType, ColumnCount, create_date
        FROM #NewRecords;
    
    END TRY
    BEGIN CATCH ... END CATCH;
END;
```

**Utility:** Auto-registers newly discovered Bronze tables. Runs once, then manual config takes over.

---

### Family 7: Alert / SLA Monitoring (2 procs)

**Purpose:** Detect stale tables (behind refresh SLA) and send alerts.

| Proc | Metric | Alert Target |
|---|---|---|
| `usp_DataWarehouseDataFeedAlert_Fabric` | Tables behind schedule (RefreshRate) | Performance_Logs.EmailQueue |
| `usp_DataWarehouseSLAAlert_Fabric` | SLA breaches (hardcoded DLs) | Office365Outlook direct email |

**Example: `usp_DataWarehouseDataFeedAlert_Fabric`**

```sql
CREATE PROC [DW_Developer].[usp_DataWarehouseDataFeedAlert_Fabric]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @msgTitle       NVARCHAR(400) = N'FABRIC Table Dictionary Objects that are behind schedule',
        @Recipients     NVARCHAR(MAX) = N'RSteinke@Ashleyfurniture.com;DL_AFI_Data_WarehouseGCC@Ashleyfurniture.com';
    
    -- 1. Count monitored tables (RefreshRate > 0)
    SELECT @TotalTables = COUNT(*)
    FROM DW_Developer.TableDictionary
    WHERE SchemaName NOT LIKE '%Wrk'
    AND ISNULL(RefreshRate,0) > 0;
    
    -- 2. Find tables behind (HoursLate > RefreshRate)
    SELECT
        HoursLate = DATEDIFF(HOUR, Modified, SYSUTCDATETIME()) - ISNULL(RefreshRate,0),
        SchemaName, TableName, LastUpdated, RefreshRate, JobServer, JobName
    INTO #behind
    FROM DW_Developer.TableDictionary
    WHERE SchemaName NOT LIKE '%Wrk'
    AND ISNULL(RefreshRate,0) > 0
    AND DATEDIFF(HOUR, Modified, SYSUTCDATETIME()) > ISNULL(RefreshRate,0);
    
    -- 3. Build HTML email table
    DECLARE @tableHTML NVARCHAR(MAX) = ...;
    
    -- 4. Insert into Performance_Logs.EmailQueue
    INSERT INTO Performance_Logs.EmailQueue (Subject, Body, Recipients, Status)
    VALUES (@msgSubject, @tableHTML, @Recipients, 'Pending');
    
    -- 5. Audit
    INSERT INTO Performance_Logs.tblFabricDataFeedAlertLog (TablesBehind, TotalTables, PercentBehind)
    VALUES (@TablesBehind, @TotalTables, @PercentBehind);
END;
```

**Dependency:** TableDictionary columns `RefreshRate`, `Modified`, `JobServer`, `JobName` must be populated.

---

### Family 8: Cleanup (2 procs)

**Purpose:** Housekeeping—drop constraints, drop working tables.

| Proc | Action | Usage |
|---|---|---|
| `usp_DropConstraints` | Drop all FKs on a table | Before bulk deletes (avoid lock contention) |
| `usp_DropWorkTable` | DROP TABLE if exists | Clean up before refresh work tables |

---

### Family 9: Email / Notification (3 procs)

**Purpose:** Generate HTML email bodies for alerts.

| Proc | Email Type | Template |
|---|---|---|
| `usp_GenerateEmailHTML_DimCountDifference` | Row count mismatch | Compare source vs destination row counts |
| `usp_GenerateEmailHTML_DimAggregateDifference` | Aggregate mismatch | Compare aggregate functions (SUM, MAX, etc.) |
| `usp_EmailQueue_MarkSent` | Notification | Mark a queued email as sent |

**Output:** Formatted HTML table → Performance_Logs.EmailQueue → Office365 Logic App.

---

### Family 10: Other (9 procs)

| Proc | Purpose |
|---|---|
| `usp_GrantSchemaSecurity` | Bulk-grant RBAC on schemas to principals |
| `Usp_WriteTableToParquet` | Export table to parquet file in OneLake (reverse direction) |
| `usp_Buckets_Insert`, `usp_InventoryDetail`, etc. (6 domain-specific) | Retail OOM, WFM timesheet transforms |

---

## 3. TableDictionary Lifecycle — End-to-End

### Phase 1: Initial Seed

**How tables enter TableDictionary:**

| Seed Method | Trigger | Proc |
|---|---|---|
| **Manual registration** (most common) | Domain team adds new table to domain WH | DBA/domain owner inserts row manually |
| **Auto-discovery via pipeline** | `Source_EDW_Check_Test` copies on-prem + runs `usp_Audit_Fabric_Tables` | `usp_Audit_Fabric_Tables` (one-time discovery) |
| **Load-time upsert** | Refresh proc called on new table | `usp_UpdateTableDictionary_ModifiedDate` (auto-creates if missing) |

**Example: Manual registration (typical Wholesale domain onboarding)**

Wholesale team wants to add `Wholesale_Warehouse.Customers.NewCustProfile`:

```sql
-- Step 1: Create table in Wholesale_Warehouse (DDL managed separately, not by ETL_Framework)
CREATE TABLE Wholesale_Warehouse.Customers.NewCustProfile (
    CustID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Address NVARCHAR(500),
    LoadDate DATETIME
);

-- Step 2: Create working view in Source_Data (bridges Bronze → Silver)
CREATE VIEW Source_Data.Customers_Wrk.v_NewCustProfile AS
SELECT CustID, Name, Address, GETDATE() AS LoadDate
FROM Source_Data.Customers_AFI.CustProfile_Raw;

-- Step 3: Insert row into TableDictionary
INSERT INTO ETL_Framework.DW_Developer.TableDictionary (
    ServerName, DatabaseName, SchemaName, TableName,
    ObjectType, StorageType,
    UpdateMethod, PrimaryKey,
    ReplicatedSource, UpdateQuery,
    RefreshRate, JobServer, JobName,
    Modified, ColumnCount
)
VALUES (
    'EDW-Fabric',
    'Wholesale_Warehouse', 'Customers', 'NewCustProfile',
    'Table', 'Delta',
    'Upsert', 'CustID',
    'Source_Data.Customers_AFI.CustProfile_Raw', 'WHERE LoadDate >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))',
    24, 'Fabric', 'Wholesale_Refresh_Daily',
    GETDATE(), 4
);

-- Step 4: Add proc call to Wholesale domain refresh
-- In Usp_Refresh_Wholesale_Warehouse:
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
    'Wholesale_Warehouse', 'Customers', 'NewCustProfile'
```

### Phase 2: Per-Load Updates

Every time a table loads, TableDictionary is updated by `usp_UpdateTableDictionary_ModifiedDate`:

```sql
EXEC [ETL_Framework].[DW_Developer].[usp_UpdateTableDictionary_ModifiedDate]
    @DestinationDatabase = 'Wholesale_Warehouse',
    @DestinationSchema = 'Customers',
    @DestinationTable = 'NewCustProfile',
    @UpdateQuery = 'WHERE LoadDate >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))',
    @DateValue = GETDATE();  -- Sets TableDictionary.Modified = now
```

This proc:
1. Checks if row exists (by DB+Schema+Table composite key)
2. If missing → **inserts** with all defaults
3. If exists → **updates** `Modified` timestamp only (currently commented out in code, potential bug)
4. Logs transaction to `TableDictionary_UpdateLog`

### Phase 3: Deferred vs Realtime Sync

**Standard flow (realtime):**
```
Load completes → usp_UpdateTableDictionary_ModifiedDate runs inline → TableDictionary.Modified = now
```

**RadarSync flow (deferred, Databricks-specific):**
```
Databricks Mirror fetches new data → usp_UpdateTableDictionary_UpdateLog_RadarSync logs sync metadata
→ [deferred] TableDictionary.Modified updated by separate sync job
```

Enables asynchronous metadata when mirror lag is acceptable.

### The 65 Columns — Grouped by Populate Method

| Group | Columns | Who Populates | Sync Model |
|---|---|---|---|
| **Identity (7)** | ServerName, DatabaseName, SchemaName, TableName, ObjectType, StorageType, ID | Initial insert + never change | Manual |
| **Update Logic (8)** | UpdateMethod, PrimaryKey, AlternateKey, DistributionKey, ReplicatedSource, UpdateQuery, RefreshRate, Platform | Manual + occasional tuning | Manual |
| **Date Handling (4)** | DateKeySource, DateKeyDestination, DateRangeDays, LoadDateColumn | Manual (if using date-based updates) | Manual |
| **Audit Config (3)** | AuditMode, Audit_TableName, SampleSize | Manual | Manual |
| **Refresh Tracking (4)** | Modified, JobServer, JobName, SourceType | Realtime (usp_UpdateTableDictionary_ModifiedDate) | Realtime |
| **Feature Flags (12+)** | IsIncrementallyLoaded, IsHandledAsReplicated, SkipMetadataLoad, CreateDate, ColumnCount, Description, ... | Mixed (some manual, some auto-discovered) | Mixed |

---

## 4. Generic Loader Patterns — Bob's Equivalent of usp_GenericLoad

The framework supports **two main modes:**

### Mode 1: Metadata-Driven Single-Table Load

```sql
-- One-liner that loads any table configured in TableDictionary
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
    @DestinationDatabase = 'Retail_Warehouse',
    @DestinationSchema = 'Sales',
    @DestinationTable = 'SalesOrder';

-- The proc looks up everything from TableDictionary:
-- - Source view: Source_Data.Sales_Wrk.v_SalesOrder
-- - Update method: (read from TableDictionary.UpdateMethod, e.g., 'Upsert')
-- - Audit behavior: (read from TableDictionary.AuditMode)
```

**Source-of-config:** TableDictionary (single registry for all 1,000+ tables).

### Mode 2: Registry-Driven Orchestrated Loop

Domain teams build a **wrapper proc** that calls the generic refresher in a loop:

```sql
CREATE PROCEDURE dbo.Usp_Refresh_Retail_Warehouse
AS
BEGIN
    -- Reads from manual hardcoded list of table names
    -- Could alternatively read from TableDictionary if schema matches across all domains
    
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
        'Retail_Warehouse', 'Sales', 'SalesOrder'
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
        'Retail_Warehouse', 'Sales', 'SalesLineDetail'
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
        'Retail_Warehouse', 'Sales', 'SalesOrderHeader'
    ... (120+ procs)
END;
```

**Parameter pattern:** 3 params per call (database, schema, table). No per-table concurrency control within this wrapper.

**Failure handling:**
- If one EXEC fails, the whole wrapper stops (no continue-on-error unless wrapped in TRY/CATCH).
- Audit trail: every start/end is logged.
- No retry built in; pipelines/scheduler must retry.

### Concurrency Model

**Sequential by default** (within a domain refresh):
```
Retail_Warehouse.Sales.SalesOrder → wait → complete
→ Retail_Warehouse.Sales.SalesLineDetail → wait → complete
→ ... (120+ sequential)
```

**Why:** Avoids lock contention on Bronze source views. Domain warehouses are isolated (no cross-domain locks).

**Parallel possible:** Run separate domain warehouse refreshes in parallel (e.g., `Usp_Refresh_Retail_Warehouse` + `Usp_Refresh_Wholesale_Warehouse` in parallel pipelines).

---

## 5. Pipeline Orchestration Patterns

### Active Pipelines (3 of 22)

Only **3 pipelines have run history**:

| Pipeline | Cadence | Purpose | Status |
|---|---|---|---|
| **Source_EDW_Check_Test** | Daily 03:50 UTC | Copy on-prem ASHLEY_EDW per metadata → run SPA checks → email results | ✅ 64 runs, 100% success since 2026-04-21 |
| **Retail_Prod_To_Dev_DataBackFill** | Ad-hoc incremental | PROD on-prem SQL → DEV Source_Data. Snapshot block (33 tables) inactive; incremental active. | ✅ 58 runs, ⚠️ failures since 2026-04-29 |
| (Unnamed mirror job) | Auto (Databricks) | Databricks Unity Catalog `edw_dev` → Fabric OneLake (full sync + autoSync) | ✅ Last success 2026-05-08 |

### Dormant (19 of 22)

Most pipelines never ran or are older than API window (~90 days). Examples:

- **EDW2FabricLoader**: Metadata-driven Copy (Lookup FabricMapping → ForEach Copy activity)
- **Fabric Migration ADF**: Synapse → Fabric port
- **Load Retail_DW**, **Load MasterData_AFI**: Single Copy activities
- **Alert_FabricTables_EnterpriseData**: Proc → lookup EmailQueue → send (dormant, no runs)

### Design Pattern: Metadata-Driven ForEach Loop

Used by active pipelines like `Source_EDW_Check_Test`:

```
Lookup activity
  ↓
  Query: SELECT * FROM metadata
  ↓
  Output: JSON array [{ table: 'Customer', rows: 100K }, { table: 'Order', rows: 500K }, ...]

ForEach activity
  ↓
  Items: @activity('Lookup').output.value
  
  Inside ForEach:
    ├─ Copy activity
    │   Source: ASHLEY_EDW_DEV.dbo.[table name from item]
    │   Sink: Fabric.Source_Data.[table name]
    │   Pre-copy: TRUNCATE Sink
    │
    ├─ Execute Stored Procedure: usp_Audit_Fabric_Tables
    │
    └─ Send email (Office365Outlook): Row count + status

After ForEach:
  Execute Stored Procedure: usp_DataWarehouseDataFeedAlert_Fabric
  (Check if any tables behind SLA, send summary email if needed)
```

**Error handling:** If one table Copy fails, ForEach continues (Continue On Error = true). Pipeline logs each activity result.

---

## 6. Domain Team Workflow — Adding a New Silver Table

**Scenario:** Retail team wants to add a new curated table `Retail_Warehouse.Sales.InventorySnapshot`.

### Step 1: Design & Deploy Bronze Working View

Retail team creates a view in Source_Data Bronze layer:

```sql
-- In Source_Data warehouse
CREATE VIEW Source_Data.Sales_Wrk.v_InventorySnapshot AS
SELECT
    StoreID,
    ItemID,
    OnHandQty,
    LoadDate = CAST(GETDATE() AS DATE)
FROM Source_Data.Sales_AFI.InventorySnapshot_Raw  -- Bronze raw table
WHERE LoadDate >= CAST(GETDATE() - 1 AS DATE);    -- Last 1 day
```

### Step 2: Create Target Table in Domain Warehouse

```sql
-- In Retail_Warehouse
CREATE TABLE Sales.InventorySnapshot (
    StoreID INT,
    ItemID INT,
    OnHandQty INT,
    LoadDate DATETIME,
    PRIMARY KEY (StoreID, ItemID, LoadDate)
);
```

### Step 3: Register in TableDictionary

```sql
INSERT INTO ETL_Framework.DW_Developer.TableDictionary (
    ServerName, DatabaseName, SchemaName, TableName,
    ObjectType, StorageType,
    UpdateMethod, PrimaryKey,
    ReplicatedSource, UpdateQuery,
    RefreshRate, JobServer, JobName,
    Modified, ColumnCount
)
VALUES (
    'EDW-Fabric',
    'Retail_Warehouse', 'Sales', 'InventorySnapshot',
    'Table', 'Delta',
    'Upsert', 'StoreID,ItemID,LoadDate',
    'Source_Data.Sales_AFI.InventorySnapshot_Raw', 'WHERE LoadDate >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))',
    6,                   -- Refresh every 6 hours
    'Fabric',
    'Retail_Refresh_Daily',
    GETDATE(), 4
);
```

### Step 4: Add Proc Call to Domain Refresh

In `Retail_Warehouse.dbo.Usp_Refresh_Retail_Warehouse`:

```sql
-- Add this line (in correct alphabetical position in the 150+ calls):
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
    'Retail_Warehouse', 'Sales', 'InventorySnapshot'
```

### Step 5: Schedule (Optional)

If not already scheduled, add to a pipeline or scheduler:

```sql
-- Example: Within a pipeline's Execute Stored Procedure activity:
EXEC [Retail_Warehouse].[dbo].[Usp_Refresh_Retail_Warehouse]

-- Or a manual scheduled run:
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 
    'Retail_Warehouse', 'Sales', 'InventorySnapshot'
```

### Step 6: Validate & Monitor

Post-load checks:
1. **Check AuditLog** for errors:
   ```sql
   SELECT * FROM ETL_Framework.DW_Developer.AuditLog
   WHERE Description LIKE '%InventorySnapshot%'
   ORDER BY DateTime DESC;
   ```

2. **Check row count:** Does it match source?
   ```sql
   SELECT COUNT(*) FROM Retail_Warehouse.Sales.InventorySnapshot;
   ```

3. **Check TableDictionary.Modified:** Should be recent.
   ```sql
   SELECT Modified FROM ETL_Framework.DW_Developer.TableDictionary
   WHERE DatabaseName = 'Retail_Warehouse' AND TableName = 'InventorySnapshot';
   ```

4. **If behind SLA:** `usp_DataWarehouseDataFeedAlert_Fabric` will email if `Modified` is older than `RefreshRate` hours.

---

## 7. Audit + Alerting + SLA Architecture

### Audit Trail Model

**All writes flow through a single bottleneck: `AuditLog`**

```
Every proc start/end inserts:
  ↓
INSERT INTO DW_Developer.AuditLog (Description, DateTime, User, Command)
VALUES (
    'usp_RefreshCuratedTableFromView: Retail_Warehouse.Sales.InventorySnapshot',
    '2026-05-10 12:34:56.789',
    'fabric_service@ashleyfurniture.com',
    'Process Start'
);

-- Then, at proc end:
INSERT INTO DW_Developer.AuditLog (...)
VALUES (..., 'Process End');

-- Or on error:
INSERT INTO DW_Developer.AuditLog (...)
VALUES (..., 'Error: Column mismatch at offset 12');
```

**Schema:**
- `ID` (BIGINT IDENTITY)
- `Description` (VARCHAR 5000) — proc identifier + params
- `DateTime` (DATETIME) — CST via `fn_GetDate()`
- `User` (VARCHAR 500) — SYSTEM_USER
- `Command` (VARCHAR 100) — Process Start | End | Error | [message]

**Retention:** No purge documented; indefinite growth (⚠️ risk).

### SLA Tracking

**RefreshRate column in TableDictionary:**

```sql
SELECT SchemaName, TableName, Modified, RefreshRate,
       HoursLate = DATEDIFF(HOUR, Modified, GETDATE()) - RefreshRate
FROM ETL_Framework.DW_Developer.TableDictionary
WHERE RefreshRate > 0
ORDER BY HoursLate DESC;

-- Result:
-- SchemaName        | TableName         | Modified           | RefreshRate | HoursLate
-- Sales             | SalesOrder        | 2026-05-10 11:00   | 4           | 1 (behind)
-- Sales             | SalesLineDetail   | 2026-05-10 12:00   | 6           | -2 (on time)
```

### Alert Pipeline: Data Feed Behind Schedule

**Proc: `usp_DataWarehouseDataFeedAlert_Fabric`**

Runs on a schedule (dormant, but logic is ready):

```
IF (count of behind tables) > 0 THEN
    1. Create #behind temp table with all late tables
    2. Build HTML email showing:
       - % behind (TablesBehind / TotalTables * 100)
       - Each late table: Name, HoursLate, LastUpdated, RefreshRate, JobName
    3. INSERT into Performance_Logs.EmailQueue
    4. Log summary to Performance_Logs.tblFabricDataFeedAlertLog
ELSE
    Skip email (no alerts needed today)
```

**Recipients:** Hardcoded in proc (⚠️ risk: not configurable without code change):
- `RSteinke@Ashleyfurniture.com`
- `DL_AFI_Data_WarehouseGCC@Ashleyfurniture.com`

### Alert Pipeline: SLA Breach

**Proc: `usp_DataWarehouseSLAAlert_Fabric`** (17K chars, more complex)

Tracks SLA thresholds per table (separate from RefreshRate). Sends escalation emails:
- Red-alert: Critical tables > 24 hours late
- Yellow-alert: Tables > 12 hours late

**Recipients:** Hardcoded DLs (again, code-change required to modify).

### Email Delivery

**Flow:**

```
Proc builds HTML email
  ↓
INSERT into Performance_Logs.EmailQueue (Subject, Body, Recipients, Status='Pending')
  ↓
Office365 Logic App polls EmailQueue
  ↓
Calls Office365Outlook Send Email action
  ↓
usp_EmailQueue_MarkSent updates Status = 'Sent'
```

**Pros:** Decouples proc execution from SMTP. Resilient to email outages.  
**Cons:** Logic App is external infrastructure (not in Fabric); failure doesn't loop back to AuditLog.

---

## 8. Cross-Workspace Integration

### OneLake Shortcuts to PROD

**18 shortcuts** from `Centralized_Lakehouse` DEV point to `EnterpriseData` PROD (WS ID `ce4e6503-...`):

- **12 shortcuts** → PROD Source_Data WH (Bronze raw tables)
- **6 shortcuts** → PROD Retail_Warehouse (Silver curated tables)
- **Total:** 501 tables, 5.92 billion rows (not actually stored in DEV)

**Risk:** ⚠️ Queries against these shortcuts read from PROD. DEV tables may show stale PROD state.

### Mounted Azure Data Factory

**ashleyv2datafactory** (RG: IoT_Hub) — legacy ADF that feeds Bronze:

- Ingests SaaS data (UKG payroll, AFI orders, Maximo assets, AshleyServiceNow tickets)
- Lands in `Source_Data` WH via Copy activities
- Notebooks `Vers5_*` also write to `Centralized_Lakehouse` directly

**Integration:** Fabric notebooks call ADF via Logic App or REST API (no native orchestration).

### Databricks Mirror (edw_dev)

**Unity Catalog `edw_dev`** syncs to Fabric OneLake:

- **Mode:** Full + autoSync (mirrors all tables + auto-refresh on changes)
- **Last sync:** 2026-05-08 05:57 Success
- **Latency:** Minutes behind source Databricks (not real-time)

**Usage:** Notebooks query via Fabric SQL endpoint (shortcuts to OneLake surface).

### Cross-WS Dependencies (Inaccessible)

Several workspaces referenced but **not accessible** (403 errors or by name only):

- WS `13eefa5e-...` (403 Forbidden)
- WS `sg_DHalama` (by name; inaccessible)
- Lakehouses: `CostAccounting_LH`, `Wholesale_LH`, `Retail_LH`, `Enterprise_LH` (referenced in notebooks; unresolvable)

Indicates **incomplete cross-workspace inventory** — some data flows remain opaque.

---

## 9. Key Insights for VN Team Alignment

### Insight 1: Metadata Registry >> Code Flexibility

**Bob's bet:** Store update logic in **TableDictionary columns** (UpdateMethod, PrimaryKey, RefreshRate, etc.) rather than procedure parameters.

**Advantage:** Domain teams self-register tables (no proc re-parameterization).  
**Tradeoff:** Limited flexibility. New load patterns require new procs (Upsert, CDC, SCD2, etc. are pre-coded, not composable).

**VN alignment:** If VN team needs **ad-hoc load patterns**, pre-code them as new procs (e.g., `usp_IncrementalTableLoad_Custom_VN`). Don't try to parameterize logic post-deployment.

---

### Insight 2: Domain Warehouses = Isolated Refresh Domains

**Each domain warehouse (Retail, Wholesale, MasterData, Distribution) owns its refresh proc:**

```
Retail_Warehouse.dbo.Usp_Refresh_Retail_Warehouse          [150+ calls]
Wholesale_Warehouse.dbo.Usp_Refresh_Wholesale_Warehouse    [120+ calls]
MasterData_Warehouse.dbo.Usp_Refresh_MasterData_Warehouse  [external]
Distribution_Warehouse.dbo.Usp_Refresh_Distribution_Warehouse [external]
```

**Advantage:** Domain teams can schedule independently; no cross-domain blocking.  
**Tradeoff:** No shared orchestration; each domain is a silo.

**VN alignment:** If VN team builds a new domain (Supply Chain, Quality), create its own warehouse + refresh wrapper. Don't try to merge into Retail's proc.

---

### Insight 3: Parquet Loaders Are a Mess — Pick One and Stick

**12 variants** evolved from experimentation. Bob never settled on a single pattern.

**Which to use?**
- **`Usp_CreateTableFromParquet_V2`** (latest, HOLDING pattern) — safest
- **`Usp_TableFromParquet_CopyInto_TruncateLoad`** (COPY INTO syntax) — fastest for bulk
- **`Usp_CreateTableFromParquet_Simple_NoCursor`** (no cursor, direct SELECT INTO) — moderate

**VN alignment:** Standardize on ONE variant. Refactor all parquet loads to use it. Don't maintain multiple branches—technical debt.

---

### Insight 4: TableDictionary Is the Bottleneck

**65 columns, 1000+ rows** (across all warehouses). Every refresh touches it.

**Risks:**
- No purge of old entries → indefinite growth
- Manual registration required → errors (typos in schema names, missing PK specs)
- Updates deferred (current code has UPDATE commented out; might not be saving RefreshRate changes)

**VN alignment:** Plan for **TableDictionary governance:**
1. Document all 65 columns + valid values per column
2. Create a UI or Excel import to validate before INSERT
3. Implement retention policy (archive rows for closed tables)
4. Monitor for stale entries (RefreshRate = NULL or 0)

---

### Insight 5: Audit Trail Is Linear, Not Hierarchical

**All audit goes to AunitLog; no proc call stack captured.**

```
EXEC usp_RefreshCuratedTableFromView → INSERT AuditLog Start
  → EXEC usp_DropWorkTable          [no inner proc logging]
  → EXEC usp_UpdateTableDictionary_ModifiedDate [no inner proc logging]
→ INSERT AuditLog End
```

You see **only outer proc**, not nested procs. Debugging slow loads is harder.

**VN alignment:** If you need **nested audit trails**, enhance AuditLog schema to include:
- `ParentProcName` (caller)
- `NestedLevel` (depth)
- `CallStack` (JSON array of proc names)

Or use **Application Insights** to trace at the query level (not Fabric-native; requires external tool).

---

## 10. Risks & Governance Observations

### Critical Risks

1. **⚠️ MetaData-Pull notebook stores plaintext Service Principal secret** (Cell 1). Rotate immediately.
2. **⚠️ 5.92 B rows in Centralized_Lakehouse are shortcut-backed**, not real DEV data. Queries may return PROD state.
3. **⚠️ Quality_Warehouse is empty** (PROD tier). Either populate it or remove it.

### High Risks

4. **RadarSync_Test mounts entire ashleydevlake ADLS zones** (trusted + raw). Overly broad; restrict scopes.
5. **Pipeline names `test`, `pipeline1` are misleading.** They perform cross-WS PROD copies to Commissions_Prototype. Rename to `CommissionsProto_*.`
6. **Hardcoded email recipients** in alert procs. If DL changes, code must be re-deployed.

### Operational Risks

7. **AuditLog has no retention policy.** Will grow indefinitely; no purge job.
8. **19 of 22 pipelines are dormant.** Unused infrastructure accumulates technical debt.
9. **TableDictionary.Modified update is commented out** in `usp_UpdateTableDictionary_ModifiedDate`. SLA alerts may not trigger correctly.

### Code Quality

10. **Proc bodies are copy-pasted** (e.g., 12 parquet loaders with minor variations). Refactoring needed.
11. **No error retry logic** in procs. If TRUNCATE fails, INSERT still executes (orphans data).
12. **No concurrency control** within domain refreshes. Sequential by design, but lock timeouts aren't handled.

---

## Conclusion: VN Team Integration Strategy

### Alignment Approach

1. **Adopt the metadata-registry model** (`TableDictionary` as single source of truth).
2. **Create VN domain warehouse(s)** following Retail/Wholesale pattern (isolated refresh wrapper procs).
3. **Standardize parquet loaders** on one variant; refactor all loads.
4. **Enhance TableDictionary governance** (validation, retention, monitoring).
5. **Inherit the audit trail pattern** but plan for enhanced nested call tracing.
6. **Participate in cross-domain SLA tracking** (add VN tables to `RefreshRate` monitoring).

### Architectural Fit

Bob's framework prioritizes **simplicity + metadata-driven self-service** over **flexibility + composability**. VN team should:
- **Embrace** the fixed set of update methods (Upsert, CDC, SCD2, etc.). Use them as-is.
- **Extend cautiously** with new procs only when existing methods don't fit.
- **Standardize naming** early (schema prefixes, proc naming conventions, domain warehouse ownership).
- **Monitor**, don't augment. Use the audit trail to understand behavior, not to add instrumentation.

---

**End of synthesis document**

---

