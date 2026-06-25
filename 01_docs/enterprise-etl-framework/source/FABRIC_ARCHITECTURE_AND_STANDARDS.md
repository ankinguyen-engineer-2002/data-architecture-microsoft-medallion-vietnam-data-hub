# Microsoft Fabric EDW Architecture & Development Standards Guide

## Overview

This guide defines the standards and best practices for developing data warehouse solutions in Microsoft Fabric using a three-tier medallion architecture with centralized framework deployment.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Layer Strategy](#data-layer-strategy)
3. [Workspace Organization](#workspace-organization)
4. [Naming Conventions](#naming-conventions)
5. [SQL Development Standards](#sql-development-standards)
6. [ETL_Framework Integration](#etl_framework-integration)
7. [Project Structure and Deployment](#project-structure-and-deployment)
8. [Shortcuts and Cross-Workspace References](#shortcuts-and-cross-workspace-references)
9. [Quality Assurance and Testing](#quality-assurance-and-testing)
10. [Change Management](#change-management)

---

## Architecture Overview

### Three-Tier Medallion Architecture

The Fabric EDW implements a medallion architecture across Microsoft Fabric workspaces:

```
┌─────────────────────────────────────────────────────────────┐
│                   ENTERPRISE_DATA WORKSPACE                 │
├─────────────────────────────────────────────────────────────┤
│  BRONZE LAYER (Raw Data)       │  SILVER LAYER (Optimized)  │
│  • Databricks                  │  • MasterData_Warehouse    │
│  • Source_Data                 │  • Distribution_Warehouse  │
│  • ETL_Framework (Shared)      │  • Manufacturing_Warehouse │
│                                │  • Marketing_Warehouse     │
│                                │  • SupplyChain_Warehouse   │
│                                │  • Wholesale_Warehouse     │
│                                │  • Quality_Warehouse       │
│                                │  • Retail_Warehouse        │
└─────────────────────────────────────────────────────────────┘
                           ↓
              Fabric Shortcuts (Bronze & Silver Data)
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              BUSINESS UNIT WORKSPACES                        │
├─────────────────────────────────────────────────────────────┤
│  GOLD LAYER (Business Ready)   │  ANALYTICS LAYER           │
│  • Retail_Warehouse_Gold       │  • Semantic Models         │
│  • Finance_Warehouse_Gold      │  • Power BI Reports        │
│  • AFISales_Warehouse_Gold     │  • Dashboards              │
│  • Quality_Warehouse_Gold      │  • Analysis                │
│  • Retail_Commissions_Gold     │                            │
│  (Co-owned with Business Teams) │                            │
└─────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Purpose | Ownership | Location |
|-------|---------|-----------|----------|
| **Bronze** | Raw, ingested data from source systems | Enterprise Data | Enterprise_Data Workspace |
| **Silver** | Cleansed, transformed, optimized data | Enterprise Data | Enterprise_Data Workspace |
| **Gold** | Business-ready, curated data | Centralized + Business Unit | Business Unit Workspaces |
| **Analytics** | Semantic models, reports, dashboards | Business Unit | Business Unit Workspaces |

---

## Data Layer Strategy

### Bronze Layer

**Characteristics:**
- Raw data exactly as extracted from source systems
- Minimal transformation
- Deployed to: **Enterprise_Data Workspace**
- Projects: `Databricks`, `Source_Data`

**Responsibilities:**
- Load data from operational systems
- Maintain data lineage
- Track SLA compliance
- Record ingestion timestamps

**Key ETL_Framework Integration:**
```sql
-- Log to DW_Developer.AuditLog
INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
VALUES (@ProcName, @DateValue, @User, 'Bronze Load Complete');

-- Update table metadata
UPDATE [$(ETL_Framework)].[DW_Developer].[TableDictionary]
SET LastModifiedDate = GETDATE(),
    LastModifiedBy = @User
WHERE TableName = 'Databricks.source_catalog.table_name';
```

### Silver Layer

**Characteristics:**
- Cleaned, deduplicated, conformed data
- Business logic applied
- Deployed to: **Enterprise_Data Workspace**
- Projects: `MasterData_Warehouse`, `Retail_Warehouse`, `Wholesale_Warehouse`, etc.

**Responsibilities:**
- Apply business rules and transformations
- Enforce data quality standards
- Create conformed dimensions
- Maintain audit trails

**Typical Projects:**
- `MasterData_Warehouse` - Master data dimensions
- `Retail_Warehouse` - Retail operational data
- `Wholesale_Warehouse` - Wholesale operational data
- `Manufacturing_Warehouse` - Manufacturing data
- `Distribution_Warehouse` - Distribution data
- `SupplyChain_Warehouse` - Supply chain data
- `Marketing_Warehouse` - Marketing data
- `Quality_Warehouse` - Quality data

### Gold Layer

**Characteristics:**
- Business-ready, curated data
- Optimized for analytics and reporting
- Deployed to: **Business Unit Workspaces**
- Projects: `*_Warehouse_Gold` (e.g., `Retail_Warehouse_Gold`, `Finance_Warehouse_Gold`)

**Ownership Model:**
- **Primary Owner:** Business Unit (e.g., Retail, Finance, Sales)
- **Secondary Owner:** Centralized Data Analytics Team
- **Collaboration:** Co-development and maintenance

**Responsibilities:**
- Curate business-specific datasets
- Aggregate and summarize data
- Create fact and dimension tables for analytics
- Support semantic models and BI tools

**Typical Gold Projects:**
- `Retail_Warehouse_Gold` - Retail analytics
- `Finance_Warehouse_Gold` - Financial analytics
- `AFISales_Warehouse_Gold` - Sales analytics
- `Quality_Warehouse_Gold` - Quality analytics
- `Retail_Commissions_Gold` - Commission calculations

### Analytics Layer

**Characteristics:**
- Power BI semantic models
- Reports and dashboards
- Deployed to: **Business Unit Workspaces**

**Responsibilities:**
- Define KPIs and metrics
- Create user-facing analytics
- Maintain data security and RLS
- Enable self-service analytics

---

## Workspace Organization

### Enterprise_Data Workspace

**Purpose:** Central hub for Bronze and Silver data layers

**Contains:**
- **Bronze Projects:**
  - `Databricks` - Databricks catalog references
  - `Source_Data` - Source system extracts
  - `ETL_Framework` - Shared ETL framework (deployed to all workspaces)

- **Silver Projects:**
  - `MasterData_Warehouse` - Master data dimensions
  - `Retail_Warehouse` - Retail Silver layer
  - `Wholesale_Warehouse` - Wholesale Silver layer
  - `Manufacturing_Warehouse` - Manufacturing Silver layer
  - `Distribution_Warehouse` - Distribution Silver layer
  - `SupplyChain_Warehouse` - Supply chain Silver layer
  - `Marketing_Warehouse` - Marketing Silver layer
  - `Quality_Warehouse` - Quality Silver layer

**Access Pattern:**
- Exposed via Fabric Shortcuts to Business Unit Workspaces
- Read-only access from Gold layers

**Development Approach:**
- Single source of truth
- Centralized testing and validation
- Shared semantic definitions

### Business Unit Workspaces

**Purpose:** Domain-specific analytics and business intelligence

**Example: Retail Workspace**
- Gold Layer: `Retail_Warehouse_Gold`
- Gold Layer: `Retail_Commissions_Gold`
- Analytics: Power BI models and reports
- Users: Retail leadership, regional managers, store managers

**Example: Finance Workspace**
- Gold Layer: `Finance_Warehouse_Gold`
- Analytics: Financial reports and dashboards
- Users: CFO, controllers, financial analysts

**Example: Sales Workspace**
- Gold Layer: `AFISales_Warehouse_Gold`
- Analytics: Sales reports and dashboards
- Users: Sales leadership, account managers

**Access Pattern:**
- Shortcuts to Bronze/Silver data in Enterprise_Data
- Local Gold curations
- Semantic models and reports
- RLS-enabled for business units

---

## Naming Conventions

### Project Names

#### Gold Projects (Business Unit Owned)
```
{BusinessDomain}_Warehouse_Gold
Examples:
  - Retail_Warehouse_Gold
  - Finance_Warehouse_Gold
  - AFISales_Warehouse_Gold
  - Quality_Warehouse_Gold
```

#### Silver Projects (Enterprise Owned)
```
{Domain}_Warehouse
Examples:
  - Retail_Warehouse
  - Wholesale_Warehouse
  - MasterData_Warehouse
  - Manufacturing_Warehouse
```

#### Bronze Projects (Enterprise Owned)
```
Source_Data          (Source system data)
Databricks           (Databricks catalog reference)
```

#### Framework Projects (Deployed to All Workspaces)
```
ETL_Framework        (Audit logs, table dictionary, stored procedures)
```

### Database Objects

| Object Type | Prefix | Example | Notes |
|------------|--------|---------|-------|
| Table | None | DimCustomer | PascalCase; no leading underscore |
| View | v_ | v_CustomerSummary | PascalCase after prefix |
| Stored Procedure | usp_ | usp_Refresh_DimCustomer | PascalCase after prefix |
| Function | fn_ | fn_GetCustomerAge | PascalCase after prefix |
| Working Schema | _Wrk | Retail_Sales_Wrk | Suffix; temporary/staging objects |
| Enhancement Schema | _Enh | Retail_Sales_Enh | Suffix; enhanced/curated objects |

### Schema Organization

**Gold Projects:**
```
{DomainAbbrev}_DW          (Core dimensions and facts)
{DomainAbbrev}_DW_Wrk      (Working/staging tables)
{DomainAbbrev}_Enh         (Enhanced/curated views)
dbo                        (System objects)
SecurityAccess             (RLS and security)
```

**Silver Projects:**
```
dbo                        (Core objects)
{Domain}_Wrk               (Working/staging tables)
{Domain}_Enh               (Enhanced/curated views)
SecurityAccess             (RLS and security)
```

**ETL_Framework Project:**
```
DW_Developer               (Audit logs, table dictionary, framework procedures)
Performance_Logs           (Performance monitoring)
SecurityAccess             (Security policies)
```

---

## SQL Development Standards

### Fabric-Specific Syntax

#### ✅ Supported: INSERT INTO ... SELECT Pattern
```sql
-- CORRECT for Fabric Warehouse
CREATE TABLE #TempTable (
    ID INT,
    Name NVARCHAR(100)
);

INSERT INTO #TempTable
SELECT 
    CustomerID,
    CustomerName
FROM [$(Source_Data)].[dbo].[Customers];
```

#### ❌ NOT Supported: CREATE TABLE AS SELECT
```sql
-- WRONG - Fabric doesn't support this syntax
CREATE TABLE #TempTable AS
SELECT 
    CustomerID,
    CustomerName
FROM [$(Source_Data)].[dbo].[Customers];
```

### Common Table Expressions (CTEs)

Fabric fully supports CTEs for SELECT, INSERT, UPDATE, DELETE, and MERGE:

```sql
WITH ActiveCustomers AS (
    SELECT CustomerID, CustomerName
    FROM [$(Source_Data)].[dbo].[Customers]
    WHERE Status = 'Active'
),
CustomerOrders AS (
    SELECT 
        c.CustomerID,
        COUNT(*) AS OrderCount
    FROM ActiveCustomers c
    INNER JOIN [$(Wholesale_Warehouse)].[Sales].[Orders] o
        ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID
)
INSERT INTO DimCustomer
SELECT 
    c.CustomerID,
    c.CustomerName,
    ISNULL(co.OrderCount, 0) AS OrderCount
FROM ActiveCustomers c
LEFT JOIN CustomerOrders co
    ON c.CustomerID = co.CustomerID;
```

### Case Sensitivity Standards

Maintain consistent casing throughout procedures:

```sql
-- ✅ CORRECT - Consistent PascalCase
SELECT
    ItemMaster.ItemSKU,
    ItemClass.ClassName
FROM [$(MasterData_Warehouse)].[ProductKnowledge].[ItemMaster] ItemMaster
LEFT JOIN [$(MasterData_Warehouse)].[ProductKnowledge].[ItemClass] ItemClass
    ON ItemClass.ItemClassCode = ItemMaster.ClassCode;

-- ❌ WRONG - Inconsistent casing
SELECT
    itemMaster.ItemSKU,
    ITEMCLASS.className
FROM [$(MasterData_Warehouse)].[ProductKnowledge].[ItemMaster] itemMaster
LEFT JOIN [$(MasterData_Warehouse)].[ProductKnowledge].[ItemClass] ITEMCLASS
    ON itemclass.ItemClassCode = itemmaster.ClassCode;
```

### Cross-Database References

Always use SqlCmdVariables for database references:

```sql
-- ✅ CORRECT
FROM [$(Source_Data)].[MasterData_OneSource].[OSLocation] Location
JOIN [$(Wholesale_Warehouse)].[Marketing].[ItemMaster] itm
    ON Location.ItemID = itm.ItemSKU
JOIN [$(MasterData_Warehouse)].[ProductKnowledge].[ItemMaster] im
    ON itm.ItemSKU = im.ItemSKU

-- ❌ WRONG - Hard-coded database names
FROM [Source_Data].[MasterData_OneSource].[OSLocation] Location
JOIN [Wholesale_Warehouse].[Marketing].[ItemMaster] itm
    ON Location.ItemID = itm.ItemSKU
```

---

## ETL_Framework Integration

### Overview

The `ETL_Framework` is a shared framework deployed to all workspaces that provides:

1. **Audit Trail System** - Track all data modifications
2. **Table Dictionary** - Metadata and SLA tracking
3. **Generic Procedures** - Reusable data curation logic
4. **Performance Monitoring** - Query execution tracking

### Project Structure

**ETL_Framework Location:**
- Deployed in: **Enterprise_Data Workspace**
- Copied to all workspace-specific deployments
- Projects reference: `[$(ETL_Framework)]`

**Schemas:**
```
DW_Developer/
├── Tables/
│   ├── AuditLog              (Procedure execution history)
│   ├── TableDictionary       (Metadata and SLA)
│   └── PerformanceLog        (Query execution times)
├── Stored Procedures/
│   ├── usp_LogAuditEntry     (Insert audit entry)
│   ├── usp_UpdateTableMetadata (Update SLA tracking)
│   └── usp_CurateData_*      (Generic curation procedures)
└── Functions/
    ├── fn_GetDate            (Consistent date handling)
    └── fn_IsSLAMet           (Check SLA compliance)
```

### AuditLog Table

**Purpose:** Track procedure execution, data modifications, and quality checks

**Schema:**
```sql
CREATE TABLE [DW_Developer].[AuditLog] (
    AuditLogID BIGINT PRIMARY KEY IDENTITY(1,1),
    ProcedureName NVARCHAR(255) NOT NULL,  -- e.g., 'Retail_DW.dbo.usp_Refresh_DimCustomer'
    ExecutionStart DATETIME NOT NULL,       -- GETDATE() at start
    ExecutionEnd DATETIME,                  -- GETDATE() at end
    ExecutedBy NVARCHAR(255) NOT NULL,     -- SYSTEM_USER
    Status NVARCHAR(50),                    -- 'Process Start', 'Process Complete', 'Error'
    RecordsAffected INT,                    -- Rows inserted/updated/deleted
    ErrorMessage NVARCHAR(MAX),             -- Error details
    CreatedDate DATETIME DEFAULT GETDATE()
);
```

**Usage in Procedures:**
```sql
CREATE PROC [Retail_DW].[dbo].[usp_Refresh_DimCustomer]
AS
BEGIN
    DECLARE @String VARCHAR(5000), @DateValue DATETIME, @User VARCHAR(500), @RecordCount INT;
    
    SET @String = 'Retail_DW.dbo.usp_Refresh_DimCustomer';
    SET @User = SYSTEM_USER;
    SET @DateValue = GETDATE();
    
    -- Get CSTDateValue for consistent timing
    SELECT @DateValue = CSTDateValue 
    FROM [$(ETL_Framework)].[DW_Developer].[fn_GetDate](@DateValue);
    
    -- Log process start
    INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
    VALUES (@String, @DateValue, @User, 'Process Start', NULL, NULL);
    
    BEGIN TRY
        -- Your data curation logic here
        INSERT INTO [Retail_DW].[dbo].[DimCustomer] (...)
        SELECT ... FROM [$(Source_Data)].[...];
        
        SET @RecordCount = @@ROWCOUNT;
        
        -- Log successful completion
        INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
        VALUES (@String, GETDATE(), @User, 'Process Complete', @RecordCount, NULL);
        
    END TRY
    BEGIN CATCH
        -- Log error
        INSERT INTO [$(ETL_Framework)].[DW_Developer].[AuditLog]
        VALUES (@String, GETDATE(), @User, 'Error', NULL, ERROR_MESSAGE());
        
        THROW;
    END CATCH;
END;
```

### TableDictionary Table

**Purpose:** Track metadata, SLA, and last modification dates for all key tables

**Schema:**
```sql
CREATE TABLE [DW_Developer].[TableDictionary] (
    TableDictionaryID INT PRIMARY KEY IDENTITY(1,1),
    DatabaseName NVARCHAR(255) NOT NULL,       -- Database containing table
    SchemaName NVARCHAR(255) NOT NULL,         -- Schema name
    TableName NVARCHAR(255) NOT NULL,          -- Table name
    TableType NVARCHAR(50),                    -- 'Fact', 'Dimension', 'Bridge'
    Layer NVARCHAR(50),                        -- 'Bronze', 'Silver', 'Gold'
    SourceSystem NVARCHAR(255),                -- System of origin
    SLARefreshInterval NVARCHAR(100),          -- 'Daily', 'Hourly', 'Real-time'
    SLAThresholdMinutes INT,                   -- Max time allowed since last refresh
    LastModifiedDate DATETIME,                 -- Last update timestamp
    LastModifiedBy NVARCHAR(255),              -- User who modified
    RowCount BIGINT,                           -- Current row count
    DataQualityScore DECIMAL(5,2),             -- Quality percentage (0-100)
    Owner NVARCHAR(255),                       -- Responsible team
    CreatedDate DATETIME DEFAULT GETDATE()
);
```

**Usage Example:**
```sql
-- After successful load, update table metadata
UPDATE [$(ETL_Framework)].[DW_Developer].[TableDictionary]
SET LastModifiedDate = GETDATE(),
    LastModifiedBy = @User,
    RowCount = (SELECT COUNT(*) FROM DimCustomer),
    DataQualityScore = 99.5
WHERE DatabaseName = 'Retail_DW'
  AND SchemaName = 'dbo'
  AND TableName = 'DimCustomer';
```

### Generic Curation Procedures

**Purpose:** Reusable logic for common data curation patterns

**Common Procedures in ETL_Framework:**

```sql
-- usp_CurateData_SCD2
-- Handles Slowly Changing Dimension Type 2 logic
-- Parameters: @SourceQuery, @TargetTable, @BusinessKey, @EffectiveDate

-- usp_CurateData_Incremental
-- Incremental loads based on modified date
-- Parameters: @LastRunDate, @SourceTable, @TargetTable

-- usp_CurateData_Deduplicate
-- Remove duplicates based on key
-- Parameters: @Table, @KeyColumns

-- usp_UpdateAuditLog
-- Standardized audit entry insertion
-- Parameters: @ProcName, @Status, @RecordsAffected, @ErrorMsg

-- usp_CheckSLACompliance
-- Verify if data refresh meets SLA
-- Returns: @IsSLAMet (1 = compliant, 0 = violated)
```

**Usage Example:**
```sql
EXEC [$(ETL_Framework)].[DW_Developer].[usp_LogAuditEntry]
    @ProcedureName = 'Retail_DW.dbo.usp_Refresh_DimProduct',
    @Status = 'Process Complete',
    @RecordsAffected = 15234,
    @ExecutedBy = @User;

EXEC [$(ETL_Framework)].[DW_Developer].[usp_UpdateTableMetadata]
    @DatabaseName = 'Retail_DW',
    @SchemaName = 'dbo',
    @TableName = 'DimProduct',
    @RowCount = (SELECT COUNT(*) FROM DimProduct),
    @LastModifiedBy = @User;
```

---

## Project Structure and Deployment

### .sqlproj Configuration

All `.sqlproj` files must follow this structure:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003" ToolsVersion="Current">
  
  <!-- Project Properties -->
  <PropertyGroup>
    <Name>Retail_Warehouse_Gold</Name>
    <ProjectGuid>{6A3C30CF-90B0-416A-97AD-385EAA1B2F1C}</ProjectGuid>
    <DSP>Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider</DSP>
    <ModelCollation>1033, CI</ModelCollation>
    <TargetDatabaseSet>True</TargetDatabaseSet>
    <DefaultSchema>dbo</DefaultSchema>
  </PropertyGroup>
  
  <!-- SqlCmd Variables for Database References -->
  <ItemGroup>
    <SqlCmdVariable Include="Source_Data">
      <Value>$(SqlCmdVar__1)</Value>
      <DefaultValue>Source_Data</DefaultValue>
    </SqlCmdVariable>
    <SqlCmdVariable Include="ETL_Framework">
      <Value>$(SqlCmdVar__2)</Value>
      <DefaultValue>ETL_Framework</DefaultValue>
    </SqlCmdVariable>
    <SqlCmdVariable Include="MasterData_Warehouse">
      <Value>$(SqlCmdVar__3)</Value>
      <DefaultValue>MasterData_Warehouse</DefaultValue>
    </SqlCmdVariable>
    <SqlCmdVariable Include="Retail_Warehouse">
      <Value>$(SqlCmdVar__4)</Value>
      <DefaultValue>Retail_Warehouse</DefaultValue>
    </SqlCmdVariable>
  </ItemGroup>
  
  <!-- Project Dependencies -->
  <ItemGroup>
    <ProjectReference Include="..\Source_Data\Source_Data.sqlproj">
      <Name>Source_Data</Name>
      <DatabaseSqlCmdVariable>Source_Data</DatabaseSqlCmdVariable>
    </ProjectReference>
    <ProjectReference Include="..\ETL_Framework\ETL_Framework.sqlproj">
      <Name>ETL_Framework</Name>
      <DatabaseSqlCmdVariable>ETL_Framework</DatabaseSqlCmdVariable>
    </ProjectReference>
    <ProjectReference Include="..\MasterData_Warehouse\MasterData_Warehouse.sqlproj">
      <Name>MasterData_Warehouse</Name>
      <DatabaseSqlCmdVariable>MasterData_Warehouse</DatabaseSqlCmdVariable>
    </ProjectReference>
    <ProjectReference Include="..\Retail_Warehouse\Retail_Warehouse.sqlproj">
      <Name>Retail_Warehouse</Name>
      <DatabaseSqlCmdVariable>Retail_Warehouse</DatabaseSqlCmdVariable>
    </ProjectReference>
  </ItemGroup>
  
</Project>
```

### Publish Profiles

Each project should include Dev and Prod publish profiles:

**Naming Convention:**
```
{ProjectName}_Dev.publish.xml
{ProjectName}_Prod.publish.xml
```

**Location:** Root of project directory

**Usage:**
```bash
dotnet publish /p:PublishProfile=Retail_Warehouse_Gold_Dev
dotnet publish /p:PublishProfile=Retail_Warehouse_Gold_Prod
```

### CI/CD Integration

All projects integrate with Azure Pipelines:
- **Path:** `/azure-pipelines/azure-pipelines.yml`
- **Triggers:** Commits to main branch
- **Process:**
  1. Restore dependencies
  2. Build all projects
  3. Run schema validation
  4. Deploy to Dev environment
  5. Run post-deployment tests
  6. Deploy to Prod (approval required)

---

## Shortcuts and Cross-Workspace References

### Fabric Shortcuts Purpose

**Shortcuts** enable Business Unit workspaces to access Bronze and Silver data from Enterprise_Data:

- Read-only access to shared enterprise data
- No data duplication
- Single source of truth maintained
- Consistent metadata across workspaces

### Shortcut Configuration

**Location:** Business Unit Workspace

**Setup:**
1. In Business Unit workspace, create shortcut pointing to Enterprise_Data
2. Reference shortcut in Gold layer projects
3. Shortcut appears as local warehouse in workspace

**Example Retail Workspace Setup:**
```
Retail Workspace/
├── Bronze Shortcut → Enterprise_Data.Databricks
├── Bronze Shortcut → Enterprise_Data.Source_Data
├── Silver Shortcut → Enterprise_Data.Retail_Warehouse
├── Silver Shortcut → Enterprise_Data.MasterData_Warehouse
├── Silver Shortcut → Enterprise_Data.Wholesale_Warehouse
├── Gold: Retail_Warehouse_Gold (Local)
├── Analytics: Retail_Semantic_Model (Power BI)
└── Reports: Retail Dashboards
```

### Reference Pattern in Gold Projects

**In Gold Project .sqlproj:**
```xml
<SqlCmdVariable Include="Retail_Warehouse">
  <Value>Retail_Warehouse</Value>  <!-- Points to shortcut -->
  <DefaultValue>Retail_Warehouse</DefaultValue>
</SqlCmdVariable>
```

**In SQL Code:**
```sql
-- Bronze access via shortcut
SELECT *
FROM [Databricks].[bronze_catalog].[table_name]

-- Silver access via shortcut
SELECT *
FROM [Retail_Warehouse].[dbo].[DimCustomer]

-- Local Gold tables
INSERT INTO [dbo].[FactSales]
SELECT * FROM [Retail_Warehouse].[dbo].[DimCustomer]
```

### Data Lineage Best Practices

Always document data flow through shortcuts:

```sql
/*
    Data Flow:
    Source System → Bronze (Databricks) 
                 → Silver (Retail_Warehouse via Shortcut)
                 → Gold (Retail_Warehouse_Gold Local)
                 → Analytics (Power BI Semantic Model)
    
    Responsibility:
    - Bronze: Enterprise Data Team
    - Silver: Enterprise Data Team
    - Gold: Business Unit + Centralized Analytics
    - Analytics: Business Unit
*/

CREATE PROCEDURE [dbo].[usp_Refresh_FactSales]
    @DataDate DATE = NULL
AS
BEGIN
    -- Load from Silver (via shortcut) into Gold (local)
    INSERT INTO [dbo].[FactSales]
    SELECT 
        fs.[SalesKey],
        fs.[CustomerKey],
        fs.[ProductKey],
        fs.[SalesAmount],
        fs.[SalesQuantity]
    FROM [Retail_Warehouse].[dbo].[FactSalesStaging] fs  -- Via Shortcut
    WHERE CAST(fs.[SalesDate] AS DATE) = @DataDate;
END;
```

---

## Quality Assurance and Testing

### Pre-Deployment Testing

**1. Schema Validation**
```bash
# Build validates all syntax and references
dotnet build Retail_Warehouse_Gold
```

**2. Stored Procedure Testing**
```sql
-- Test stored procedure with sample data
EXEC [dbo].[usp_Refresh_DimCustomer] 
    @DebugMode = 1;

-- Verify audit log entry
SELECT TOP 1 * FROM [$(ETL_Framework)].[DW_Developer].[AuditLog]
ORDER BY CreatedDate DESC;
```

**3. Data Quality Checks**
```sql
-- Check for NULL values in key columns
SELECT COUNT(*) AS NullCount
FROM [dbo].[DimCustomer]
WHERE CustomerID IS NULL OR CustomerName IS NULL;

-- Check for duplicates
SELECT CustomerID, COUNT(*) AS DupCount
FROM [dbo].[DimCustomer]
GROUP BY CustomerID
HAVING COUNT(*) > 1;

-- Verify SLA compliance
SELECT * FROM [$(ETL_Framework)].[DW_Developer].[TableDictionary]
WHERE DATEDIFF(minute, LastModifiedDate, GETDATE()) > SLAThresholdMinutes;
```

### Post-Deployment Validation

**1. Verify Audit Entries**
```sql
-- Check successful completion
SELECT *
FROM [$(ETL_Framework)].[DW_Developer].[AuditLog]
WHERE ProcedureName = 'Retail_DW.dbo.usp_Refresh_DimCustomer'
  AND Status = 'Process Complete'
ORDER BY CreatedDate DESC;
```

**2. Monitor Table Metadata**
```sql
-- Verify table dictionary is updated
SELECT 
    TableName,
    LastModifiedDate,
    RowCount,
    DataQualityScore
FROM [$(ETL_Framework)].[DW_Developer].[TableDictionary]
WHERE TableName IN ('DimCustomer', 'DimProduct', 'FactSales')
ORDER BY LastModifiedDate DESC;
```

---

## Change Management

### Code Review Process

**Before Committing:**
1. Ensure code builds successfully: `dotnet build`
2. Validate SQL syntax and naming conventions
3. Confirm all cross-database references use SqlCmdVariables
4. Check case consistency in aliases and column references
5. Add audit logging to procedures
6. Document changes in commit message

**Pull Request Checklist:**
- [ ] Code builds without errors or warnings
- [ ] All SqlCmdVariables properly configured
- [ ] Audit logging added to stored procedures
- [ ] Table dictionary entries updated
- [ ] No hard-coded database names
- [ ] Naming conventions followed
- [ ] Case consistency maintained
- [ ] Cross-workspace impact assessed

### Deployment Process

**Development → Staging → Production**

```
1. Commit to feature branch
2. Pull request created → Code review
3. Merge to main branch
4. CI/CD Pipeline:
   - Build all projects
   - Deploy to Dev environment
   - Run validation tests
   - Upon approval: Deploy to Prod
5. Verify audit logs post-deployment
6. Monitor table metrics for 24 hours
```

### Rollback Procedures

**If Critical Issues Found:**
1. Identify affected tables/procedures from audit logs
2. Review TableDictionary for data integrity
3. Restore from backup if data corruption detected
4. Redeploy previous stable version
5. Document issue and root cause

---

## Key Contacts and Escalation

| Role | Responsibility | Escalation |
|------|----------------|-----------|
| **Centralized Data Analytics** | Enterprise architecture, Silver layer maintenance, ETL_Framework | VP Data Engineering |
| **Business Unit Lead** | Gold layer ownership, business rules, Analytics layer | Business VP |
| **Database Administrator** | Workspace management, backups, performance tuning | IT Director |
| **Data Governance** | Metadata standards, data quality, compliance | Chief Data Officer |

---

## Additional Resources

- [Microsoft Fabric Warehouse Documentation](https://learn.microsoft.com/en-us/fabric/data-warehouse/)
- [SQL Project Best Practices](./SQLPROJ_BEST_PRACTICES.md)
- Troubleshooting guide: not included in the current source bundle.
- Quick reference card: not included in the current source bundle.

