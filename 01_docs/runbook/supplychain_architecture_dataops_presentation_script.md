# SupplyChain Fabric Architecture and DataOps Presentation Script

Purpose: use this document as a meeting script and realtime Q&A reference for the SupplyChain Fabric architecture, database-object scope, ETL Framework adoption, orchestration, and Git/CI-CD process.

Presentation principles:

- Speak from the point of view of owning and operating the SupplyChain domain implementation.
- Explain by architecture layer and workflow, not by reading a file list.
- Use terms like common standard, ETL Framework, database object repository, and Fabric workspace repository.
- Do not present this as a personal standard. Present it as the operating model being applied for this domain.

## Realtime Meeting Usage Guide

This document is optimized for realtime meeting support. When generating a response, prefer short spoken answers first, then add supporting detail only if the discussion continues.

Default response style:

```text
1. Start with a direct answer in 1-2 sentences.
2. Anchor the answer to one of these concepts:
   architecture layer, ETL Framework, orchestration, Fabric workspace repo (`data-fabric-enterprise-supply-chain`) and database object repo (`data-edw-fabric`), build validation, runtime validation, or ownership boundary.
3. Use verified numbers when useful.
4. If the question goes beyond validated evidence, say what is validated and what still needs confirmation.
5. Avoid sounding defensive. Use technical boundaries and evidence.
```

Primary routing map:

```text
If the conversation mentions:

"architecture", "medallion", "layer", "bronze", "silver", "gold"
  -> Use sections 1, 2, 3, 4, 5, 14.A, 14.M, 15.B, 15.C.

"ETL Framework", "TableDictionary", "AuditLog", "framework loaded"
  -> Use sections 5, 6, 13.Q4, 13.Q11, 14.G, 14.H, 15.C, 15.I, 15.J.

"stored procedure", "refresh order", "pipeline", "orchestration", "scheduler"
  -> Use sections 6, 7, 13.Q12, 14.I, 15.D, 15.J.

"data-fabric-enterprise-supply-chain", "data-edw-fabric", "PR", "CI/CD", "release", "database object"
  -> Use sections 8, 9, 10, 11, 13.Q1, 13.Q2, 13.Q13, 15.E.

"Databricks", "Enterprise_Lakehouse", "external reference", "source stub"
  -> Use sections 7, 9, 10, 13.Q3, 13.Q8, 14.B, 14.C, 15.G.

"scope", "domain", "non-SupplyChain", "other source", "why included"
  -> Use sections 11, 13.Q10, 14.F, 14.P, 15.H.

"build", "SQL project", "dacpac", "warning", "SQL71558"
  -> Use sections 9, 10, 13.Q7, 14.D, 15.F.

"data quality", "correctness", "reconciliation", "DQ"
  -> Use sections 5, 13.Q10, 14.J, 14.O, 15.I.

"support", "failure", "monitoring", "observability", "SLA"
  -> Use sections 6, 7, 14.O, 15.J, 15.P.

"security", "permission", "identity", "production access"
  -> Use sections 7, 10, 15.K, 15.P.

"performance", "scale", "parallel", "runtime"
  -> Use sections 6, 14.I, 15.L.

"rollback", "hotfix", "production issue"
  -> Use sections 11, 15.M, 15.P.

"semantic model", "Power BI", "report"
  -> Use sections 2, 4, 14.N, 15.N.
```

High-confidence facts:

```text
The DEV workspace is Enterprise SupplyChain-Dev.
The main database-object scope is SupplyChain_Processing_Warehouse and SupplyChain_Gold_Warehouse.
data-fabric-enterprise-supply-chain is the Fabric workspace repository.
data-edw-fabric is the database object repository.
The `data-edw-fabric` branch is feature/supplychain-processing-gold-warehouse-objects.
The local SQL project build passed with 0 errors.
The full refresh path has 10 wrapper procedures.
50 ETL Framework load calls were checked.
50 matched TableDictionary rows.
There are 46 unique framework-loaded target tables.
There are 49 SupplyChain TableDictionary rows.
DQForecastAccuracy is the known direct-insert exception.
Databricks in the database object repo `data-edw-fabric` is an external-reference project mapped to Enterprise_Lakehouse, not Databricks runtime job code.
```

Unknown or confirm-before-claiming items:

```text
Exact production release pipeline name.
Exact production approver configuration.
Exact scheduler owner.
Production runtime identity and permissions.
Formal SLA/runtime target.
Formal rollback process.
Business reconciliation thresholds for Forecast Accuracy and Inventory Health.
```

Safe fallback answer:

> I can separate what has already been validated from what still needs environment confirmation. The database-object structure and references have been validated locally. ETL Framework coverage has been checked in DEV for framework-loaded targets. Production pipeline ownership, runtime identity, SLA, and business reconciliation thresholds should be confirmed with the release and domain owners.

## 0. Live Meeting Cheat Sheet

Use this section when a quick answer is needed during a meeting.

Answer pattern:

```text
1. Clarify the boundary: Fabric artifact or database object?
2. Map the topic to the layer: source, processing, gold, semantic.
3. Give the verified numbers.
4. Explain the operating path: data-fabric-enterprise-supply-chain or data-edw-fabric, build/test/PR.
```

### 30-second summary

> The SupplyChain implementation is being built as a Fabric-centered medallion architecture. Source/shared data is consumed from Enterprise_Lakehouse and related source surfaces. SupplyChain_Processing_Warehouse is the Silver/processing layer for curated domain objects. SupplyChain_Gold_Warehouse is the serving layer for semantic/report consumption. The ETL Framework is used for refresh, audit, and metadata tracking. From a DataOps perspective, I separate Fabric workspace artifacts into data-fabric-enterprise-supply-chain and database objects into data-edw-fabric. The current data-edw-fabric setup adds SQL projects for Processing and Gold, configures external references through SQLCMD variables, and the local SQL project build has passed with 0 errors.

### Key numbers to remember

```text
Workspace:
  Enterprise SupplyChain-Dev

Main Fabric items:
  5 key items:
    Enterprise_Lakehouse
    ETL_Framework
    SupplyChain_Processing_Warehouse
    SupplyChain_Gold_Warehouse
    SupplyChain_Lakehouse

Warehouse object scope:
  2 SupplyChain warehouse scopes:
    SupplyChain_Processing_Warehouse
    SupplyChain_Gold_Warehouse

Processing scope:
  14 main schemas, including final and _Wrk schemas.

Gold scope:
  7 main schemas, including Shared, ForecastAccuracy, InventoryHealth, and _Wrk schemas.

Business mart scope:
  2 main marts:
    Forecast Accuracy
    Inventory Health
  plus shared reference dimensions.

Full refresh:
  10 wrapper procedures.
  50 ETL Framework load calls.
  46 unique framework-loaded target tables.
  49 SupplyChain TableDictionary rows.
  0 missing TableDictionary rows for framework-loaded targets.
  100% AuditLog Process Complete coverage for checked framework-loaded targets.

Known exception:
  1 direct-insert table:
    ForecastAccuracy_DW.DQForecastAccuracy

data-edw-fabric PR/build:
  Branch:
    feature/supplychain-processing-gold-warehouse-objects
  Approx committed scope:
    98 Processing files
    43 Gold files
    43 external source stub files
    1 solution update
  Build:
    0 errors
    SQL71558 casing warnings only
```

### Boundary answer

If asked "Which repo should this go to?", answer:

```text
If it is Fabric item metadata, pipeline, notebook, semantic model, report,
or workspace item structure:
  data-fabric-enterprise-supply-chain.

If it is a SQL database object inside a warehouse:
  data-edw-fabric.
```

Short version:

> Fabric item changes go to the Fabric workspace repository. Warehouse SQL objects go to the database object repository.

### What to avoid saying

Avoid:

```text
"I copied everything from Fabric."
"The Databricks folder means I am building Databricks jobs."
"Build passed, so the business data is 100% validated."
"Everything should go to the Fabric workspace repo `data-fabric-enterprise-supply-chain` because Fabric Git shows a warehouse change."
```

Say instead:

```text
"I synced only the SupplyChain database objects needed for this scope."
"In the database object repo `data-edw-fabric`, Databricks is an external reference project mapped to Enterprise_Lakehouse."
"The build validates SQL project compilation and references. Runtime correctness is validated through ETL execution, AuditLog, row counts, DQ checks, and semantic smoke testing."
"Fabric Git captures item-level changes. Database objects are reviewed and deployed through the database object repository."
```

## 1. Architecture Overview

The SupplyChain implementation is being built as a Fabric-centered medallion architecture.

High-level flow:

```text
Enterprise source surfaces
  -> SupplyChain Processing Warehouse
  -> SupplyChain Gold Warehouse
  -> Semantic model / report consumption
```

The key DEV workspace items are:

```text
Enterprise_Lakehouse
  Shared source surface. Warehouse views can read it through external references.

ETL_Framework
  Operational framework for metadata, audit logs, and refresh metadata.

SupplyChain_Processing_Warehouse
  Silver/processing layer for the SupplyChain domain.

SupplyChain_Gold_Warehouse
  Gold/serving layer for BI, semantic model, and reporting.

SupplyChain_Lakehouse
  Existing domain lakehouse item. It is not the primary target of the current database-object PR.
```

Main talking point:

> I separate Fabric item artifacts from database objects inside the warehouse. Fabric item metadata belongs in the Fabric workspace repository. SQL objects such as tables, views, stored procedures, and schemas belong in the database object repository.

## 2. Medallion Mapping

The SupplyChain medallion mapping is:

```text
Bronze / source access
  Enterprise_Lakehouse and source surfaces exposed for enterprise/domain usage.

Silver / processing
  SupplyChain_Processing_Warehouse.
  Contains staging, reference master, sales history, forecast history,
  open order history, inventory history, and curated intermediate tables.

Gold / serving
  SupplyChain_Gold_Warehouse.
  Contains dimensional and fact tables for Forecast Accuracy and Inventory Health.

Consumption
  Semantic model and Power BI reports consume the Gold layer.
```

Current mart scope:

```text
Forecast Accuracy
Inventory Health
Shared reference dimensions
```

How to explain it:

> The Processing layer standardizes and stages the domain logic. The Gold layer exposes business-facing structures for consumption. This separation makes the implementation easier to review, refresh, govern, and extend to additional marts later.

## 3. Processing Warehouse Scope

`SupplyChain_Processing_Warehouse` is the Silver layer.

Main schemas:

```text
ReferenceMaster_Enh
ReferenceMaster_Enh_Wrk
Staging
Staging_Wrk
SalesHistory_Enh
SalesHistory_Enh_Wrk
ForecastHistory_Enh
ForecastHistory_Enh_Wrk
OpenOrderHistory_Enh
OpenOrderHistory_Enh_Wrk
InventoryHistory_Enh
InventoryHistory_Enh_Wrk
ProcessingSeed
dbo
```

Pattern:

```text
_Wrk views
  -> contain source/select/transformation logic

final Processing tables
  -> refreshed from _Wrk views through the ETL Framework
```

Example objects:

```text
ReferenceMaster_Enh.Calendar
ReferenceMaster_Enh.ItemMaster
SalesHistory_Enh.InvoiceDetailLineLevel
ForecastHistory_Enh.ForecastDemandMonthly
InventoryHistory_Enh.InventorySnapshotWeekly
InventoryHistory_Enh.SupplyPlanDetail
```

Talking point:

> Processing is not a data dump. It is a curated layer with dependency order, ETL Framework metadata, and repeatable wrapper procedures.

## 4. Gold Warehouse Scope

`SupplyChain_Gold_Warehouse` is the serving layer.

Main schemas:

```text
Shared_DW
Shared_DW_Wrk
ForecastAccuracy_DW
ForecastAccuracy_DW_Wrk
InventoryHealth_DW
InventoryHealth_DW_Wrk
dbo
```

Example objects:

```text
Shared_DW.DimCalendar
Shared_DW.DimProduct
Shared_DW.DimWarehouse

ForecastAccuracy_DW.DimCustomerGrouping
ForecastAccuracy_DW.DimForecastHorizon
ForecastAccuracy_DW.FactForecastActual
ForecastAccuracy_DW.FactForecastKpi

InventoryHealth_DW.DimVendor
InventoryHealth_DW.FactInventoryHealthSnapshot
InventoryHealth_DW.FactInventoryHealthFutureWeekEnding
InventoryHealth_DW.InventoryHealthSubStatusWeekly
InventoryHealth_DW.ProjectedInventoryHealthSubStatus
```

Talking point:

> Gold runs after the required Silver prerequisites are complete. Gold is designed as a stable serving contract for semantic model and report consumption.

## 5. ETL Framework Adoption

SupplyChain is aligned to the ETL Framework for standard refresh behavior, metadata, and auditability.

Core objects:

```text
ETL_Framework.DW_Developer.TableDictionary
ETL_Framework.DW_Developer.AuditLog
ETL_Framework.DW_Developer.TableDictionary_UpdateLog
```

Core procedures used by the wrappers:

```text
ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
ETL_Framework.DW_Developer.usp_UpdateTableDictionary_ModifiedDate
```

Refresh pattern:

```text
SupplyChain wrapper procedure
  -> calls ETL Framework refresh procedure
  -> loads final target table from _Wrk view
  -> writes AuditLog entries
  -> updates TableDictionary metadata
```

### ETL Framework applied to medallion layers

If asked "How are you applying the ETL Framework across the medallion layers?", answer:

```text
Bronze / source access:
  The ETL Framework is not the raw enterprise ingestion owner in this scope.
  Source surfaces such as Enterprise_Lakehouse are consumed as dependencies.
  Source references are represented in the SQL project through SQLCMD variables and external stubs.

Silver / Processing:
  The ETL Framework is applied strongly here.
  Processing wrapper procedures call usp_RefreshCuratedTableFromView.
  Final Processing tables are loaded from _Wrk views.
  TableDictionary records target metadata.
  AuditLog records runtime execution.

Gold / Serving:
  Gold wrapper procedures also use the ETL Framework for framework-managed targets.
  Gold final tables read from Gold _Wrk views or Processing outputs.
  Gold is the serving contract for semantic/reporting consumption.
```

Short answer:

> The ETL Framework does not replace the medallion architecture. It is the operational control layer for curated Processing and Gold loads: refresh, audit, metadata, and observability.

More precise answer:

```text
Medallion defines where the data lives and what each layer means.
ETL Framework defines how curated tables are refreshed, logged, and tracked.
```

DEV verification summary:

```text
Full refresh wrapper calls checked: 50
Framework load calls matched to TableDictionary: 50
Missing TableDictionary rows for framework-loaded targets: 0
AuditLog Process Complete coverage for framework-loaded targets: 100%
```

Current scale:

```text
10 wrapper procedures
50 ETL Framework load calls
46 unique framework-loaded target tables
49 SupplyChain TableDictionary rows
```

Important distinction:

```text
TableDictionary = registry / governance metadata
AuditLog = runtime execution log
```

Known exception:

```text
SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DQForecastAccuracy
```

This table is currently populated by a direct `INSERT INTO ... SELECT` inside the Gold wrapper. It does not go through `usp_RefreshCuratedTableFromView`, so it is not counted as a framework-loaded target in the TableDictionary verification.

## 6. Full Refresh Orchestration

The full refresh is organized into 10 wrapper procedure steps.

Logical order:

```text
01 Shared ReferenceMaster
02 Shared Staging
03 Forecast Accuracy Silver W01
04 Forecast Accuracy Silver W02
05 Forecast Accuracy Silver W03
06 Forecast Accuracy Gold
07 Inventory Health Silver W01
08 Inventory Health Silver W02
09 Inventory Health Silver W03
10 Inventory Health Gold
```

Concrete procedure order:

```sql
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_Shared_ReferenceMaster];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_Shared_Staging];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W01];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W02];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W03];
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Gold];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W01];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W02];
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W03];
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Gold];
```

Talking point:

> I split Silver into waves so dependencies are explicit. Shared prerequisites run first, then Forecast Silver and Gold, then Inventory Silver and Gold. This makes the workflow easier to schedule through Fabric pipelines, SQL Agent, or another enterprise scheduler.

### Stored procedures reviewers should pay attention to

If asked "Which stored procedures should we pay attention to?", group them like this:

```text
Shared prerequisite procedures:
  Usp_Refresh_Shared_ReferenceMaster
  Usp_Refresh_Shared_Staging

Forecast Accuracy Silver procedures:
  Usp_Refresh_ForecastAccuracy_Silver_W01
  Usp_Refresh_ForecastAccuracy_Silver_W02
  Usp_Refresh_ForecastAccuracy_Silver_W03

Forecast Accuracy Gold procedure:
  Usp_Refresh_ForecastAccuracy_Gold

Inventory Health Silver procedures:
  Usp_Refresh_InventoryHealth_Silver_W01
  Usp_Refresh_InventoryHealth_Silver_W02
  Usp_Refresh_InventoryHealth_Silver_W03

Inventory Health Gold procedure:
  Usp_Refresh_InventoryHealth_Gold
```

Review focus:

```text
1. Shared procedures must run first because downstream marts depend on reference/staging objects.
2. Silver waves must run before their Gold procedure.
3. Forecast Gold should not run before Forecast Silver W01/W02/W03.
4. Inventory Gold should not run before Inventory Silver W01/W02/W03.
5. ETL Framework calls inside wrappers should point to the expected target table and _Wrk view.
6. Direct insert exceptions should be called out explicitly, especially DQForecastAccuracy.
```

What I would monitor:

```text
AuditLog:
  process start, complete, and failure records for each framework load.

TableDictionary:
  ModifiedDate, row count, and metadata freshness for registered targets.

Warehouse tables:
  row count and LoadDT/freshness after each refresh wave.

Gold semantic readiness:
  key fact and dimension tables available after Gold procedures complete.
```

## 7. SQL Agent, Azure, and Databricks Positioning

SQL Agent / enterprise scheduler:

```text
Enterprise scheduler
  -> triggers the SupplyChain full refresh entrypoint
  -> wrapper procedures run in order
  -> ETL Framework records execution metadata
  -> Gold is ready for semantic/report consumption
```

Talking point:

> A Fabric pipeline can be the execution surface in DEV, but the operating model can still allow SQL Agent or another enterprise scheduler to own the top-level schedule. The domain logic remains in SQL wrapper procedures and ETL Framework metadata.

Azure:

```text
Azure/Fabric identity
Fabric REST APIs
SQL endpoints
deployment/runtime controls
```

Talking point:

> This SupplyChain implementation does not require me to manually operate Azure infrastructure day to day. Azure is primarily the platform/control plane, identity layer, and endpoint surface.

Databricks naming:

```text
Runtime / business architecture:
  SupplyChain SQL objects read from Enterprise_Lakehouse and related source surfaces.

data-edw-fabric SQL project:
  Databricks is the external-reference project/folder name used so SQL build can resolve source references.
```

In the database object repo `data-edw-fabric`, the publish profile maps:

```text
$(Databricks) -> Enterprise_Lakehouse
```

Talking point:

> The folder/project named Databricks in the database object repo `data-edw-fabric` does not mean this PR creates Azure Databricks jobs. It is an external reference stub structure so the SQL project can compile views that reference the source surface.

Example:

```sql
FROM [$(Databricks)].[SupplyChain_Enh].[DemandInventorySnapshotDaily]
```

requires a compile-time source stub like:

```text
Databricks/SupplyChain_Enh/Tables/DemandInventorySnapshotDaily.sql
```

## 8. DataOps and CI/CD: data-fabric-enterprise-supply-chain and data-edw-fabric

There are two repositories because there are two different artifact types.

data-fabric-enterprise-supply-chain:

```text
data-fabric-enterprise-supply-chain
```

Use data-fabric-enterprise-supply-chain for Fabric workspace artifacts:

```text
Notebook item definitions
Pipeline item definitions
Lakehouse/Warehouse item metadata
Semantic model / report artifacts
Workspace folder/item structure
Fabric Git item-level changes
```

data-edw-fabric:

```text
data-edw-fabric
```

Use data-edw-fabric for database objects:

```text
schemas
tables
views
stored procedures
functions
SQL project configuration
publish profiles
external source stubs needed by SQL build
```

Short rule:

```text
Fabric item/artifact changes -> data-fabric-enterprise-supply-chain PR
Warehouse SQL/database object changes -> data-edw-fabric PR
```

Talking point:

> I initially saw warehouse item changes through Fabric Git in data-fabric-enterprise-supply-chain. After clarifying the operating process, I understand that database objects inside the warehouse should be represented in the database object repo `data-edw-fabric` so review ownership and release deployment follow the database-object path.

## 9. Current data-edw-fabric Setup

Current `data-edw-fabric` branch:

```text
feature/supplychain-processing-gold-warehouse-objects
```

Configured for:

```text
SupplyChain_Processing_Warehouse
SupplyChain_Gold_Warehouse
```

Wired into the solution:

```text
EDW-Fabric.sln
SupplyChain_Processing_Warehouse.sqlproj
SupplyChain_Gold_Warehouse.sqlproj
Dev/Prod publish profiles
Databricks external source stubs required for SQL build
```

Configuration pattern:

```text
Microsoft.Build.Sql
Fabric DW target platform
SQLCMD variables for external database references
Project references to ETL_Framework, Databricks, and Processing where needed
Publish profiles mapping SQLCMD variables to Fabric database names
```

SQLCMD variable mapping:

```text
$(Databricks) -> Enterprise_Lakehouse
$(ETL_Framework) -> ETL_Framework
$(SupplyChain_Processing_Warehouse) -> SupplyChain_Processing_Warehouse
$(SupplyChain_Gold_Warehouse) -> SupplyChain_Gold_Warehouse
```

Local validation:

```bash
dotnet restore EDW-Fabric.sln
dotnet build EDW-Fabric.sln --configuration Release /p:NetCoreBuild=true --no-restore
git diff --check
```

Result:

```text
Build succeeded
0 errors
SQL71558 casing warnings only
Whitespace check passed
```

Talking point:

> Build success does not replace runtime data validation, but it proves the SQL projects compile, references resolve, and the database-object PR is structurally ready for the release pipeline path.

## 10. Detailed Setup Evidence

Use this section when you need to show that the setup is understood at both the architecture level and the implementation level.

### Local repositories

data-fabric-enterprise-supply-chain local:

```text
/Users/MAC/Documents/Ashley-Git-Data-Fabric/data-fabric-enterprise-supply-chain
```

Remote:

```text
github.com/afi-internal/data-fabric-enterprise-supply-chain
```

Role:

```text
Fabric workspace repository.
Used for item-level artifacts of the Enterprise SupplyChain-Dev workspace.
```

data-edw-fabric local:

```text
/Users/MAC/Documents/Ashley-Git-Data-Fabric/data-edw-fabric
```

Remote:

```text
github.com/afi-internal/data-edw-fabric
```

Role:

```text
Database object repository.
Used for SQL database objects and SQL project deployment structure.
```

### Current `data-edw-fabric` branch and commit scope

Branch:

```text
feature/supplychain-processing-gold-warehouse-objects
```

Commit purpose:

```text
Add SupplyChain Processing and Gold warehouse database objects
and wire them into the central EDW-Fabric SQL solution.
```

Approx file scope:

```text
SupplyChain_Processing_Warehouse:
  98 files

SupplyChain_Gold_Warehouse:
  43 files

Databricks external source stubs:
  43 files

Solution update:
  1 file
```

Talking point:

> The file count looks large because SQL project representation stores each schema, table, view, procedure, and source stub as separate files. The actual scope is still two SupplyChain warehouses plus required external references.

### What was added for Processing Warehouse

Folder:

```text
data-edw-fabric/SupplyChain_Processing_Warehouse/
```

Main content:

```text
Schemas:
  ReferenceMaster_Enh
  ReferenceMaster_Enh_Wrk
  Staging
  Staging_Wrk
  SalesHistory_Enh
  SalesHistory_Enh_Wrk
  ForecastHistory_Enh
  ForecastHistory_Enh_Wrk
  OpenOrderHistory_Enh
  OpenOrderHistory_Enh_Wrk
  InventoryHistory_Enh
  InventoryHistory_Enh_Wrk
  ProcessingSeed
  dbo

Objects:
  tables
  views
  wrapper stored procedures
  SQL project file
  publish profiles
```

Important setup files:

```text
SupplyChain_Processing_Warehouse.sqlproj
Properties/PublishProfiles/*.xml
```

Purpose:

```text
Make Processing Warehouse deployable as a SQL project.
Register external references.
Compile views, procedures, and tables in a reviewable database-object repository.
```

### What was added for Gold Warehouse

Folder:

```text
data-edw-fabric/SupplyChain_Gold_Warehouse/
```

Main content:

```text
Schemas:
  Shared_DW
  Shared_DW_Wrk
  ForecastAccuracy_DW
  ForecastAccuracy_DW_Wrk
  InventoryHealth_DW
  InventoryHealth_DW_Wrk
  dbo

Objects:
  dimension tables
  fact tables
  working views
  Gold refresh stored procedures
  SQL project file
  publish profiles
```

Important setup files:

```text
SupplyChain_Gold_Warehouse.sqlproj
Properties/PublishProfiles/*.xml
```

Purpose:

```text
Make Gold Warehouse deployable as a SQL project.
Allow semantic/report-facing tables to be reviewed and deployed through database-object CI/CD.
Reference Processing Warehouse where Gold depends on Silver outputs.
```

### What changed in the solution

Solution:

```text
data-edw-fabric/EDW-Fabric.sln
```

Change:

```text
Added SupplyChain_Processing_Warehouse project.
Added SupplyChain_Gold_Warehouse project.
Kept them aligned with the existing solution/project structure.
```

Talking point:

> Adding the folders alone is not enough. The projects must be added to the solution so local build and release pipeline can include them.

### SQL project configuration

Both SupplyChain SQL projects follow the repository SQL project pattern:

```text
Microsoft.Build.Sql
Fabric Data Warehouse target
SQLCMD variables for cross-database references
ProjectReference entries for dependency resolution
Dev/Prod publish profiles
```

Key SQLCMD variables:

```text
$(Databricks)
  maps to Enterprise_Lakehouse

$(ETL_Framework)
  maps to ETL_Framework

$(SupplyChain_Processing_Warehouse)
  maps to SupplyChain_Processing_Warehouse

$(SupplyChain_Gold_Warehouse)
  maps to SupplyChain_Gold_Warehouse
```

Why SQLCMD variables matter:

```text
They avoid hard-coding environment-specific database names inside SQL object definitions.
They allow Dev/Prod publish profiles to point to the correct target names.
They make cross-database references compile in SQL project build.
```

### Why external source stubs exist

External source stubs are in:

```text
data-edw-fabric/Databricks/
```

For this workload:

```text
Databricks project/folder = existing external-reference project name.
It is mapped to Enterprise_Lakehouse for Fabric SQL project build.
```

Purpose:

```text
If a SupplyChain _Wrk view references an external source object,
the SQL compiler needs a minimal definition for that source object.
```

Example:

```sql
FROM [$(Databricks)].[SupplyChain_Enh].[DemandInventorySnapshotDaily]
```

requires a compile-time source stub like:

```text
Databricks/SupplyChain_Enh/Tables/DemandInventorySnapshotDaily.sql
```

Talking point:

> These stubs are not owned SupplyChain target objects. They are dependency contracts required for build validation.

### Validation commands used

Restore:

```bash
dotnet restore EDW-Fabric.sln
```

Build:

```bash
dotnet build EDW-Fabric.sln --configuration Release /p:NetCoreBuild=true --no-restore
```

Whitespace check:

```bash
git diff --check
```

Result:

```text
Restore succeeded.
Build succeeded.
0 errors.
SQL71558 casing warnings only.
Whitespace check passed.
```

How to explain build result:

```text
Build success:
  SQL project structure is valid.
  Cross-database references resolve.
  Dacpac generation path is healthy.

Build does not prove:
  Business metric correctness.
  Data reconciliation.
  Production permissions.
  Scheduler runtime success.
```

### Live DEV checks already understood

Workspace:

```text
Enterprise SupplyChain-Dev
```

ETL Framework verification:

```text
50 framework load calls checked.
50 matched TableDictionary rows.
0 missing TableDictionary rows for framework-loaded targets.
46 unique framework-loaded target tables.
AuditLog Process Complete coverage checked for those targets.
```

Full refresh shape:

```text
10 wrapper procedures.
Shared prerequisites first.
Forecast Silver W01/W02/W03.
Forecast Gold.
Inventory Silver W01/W02/W03.
Inventory Gold.
```

Known exception:

```text
ForecastAccuracy_DW.DQForecastAccuracy
  Loaded by direct insert inside Gold wrapper.
  Not currently a framework-loaded target.
```

Talking point:

> I separate compile-time validation from runtime validation. data-edw-fabric build proves structure and references. ETL Framework and AuditLog checks prove the current full-refresh path is instrumented for framework-managed loads.

### How to explain where the setup came from

Use this flow:

```text
1. DEV workspace is the implementation/authoring surface.
2. Warehouse database object definitions are materialized into data-edw-fabric.
3. data-edw-fabric SQL projects are configured to match Fabric warehouse dependencies.
4. External source references are represented by SQLCMD variables and source stubs.
5. Local build validates the database-object package before PR.
6. PR review/release pipeline becomes the controlled promotion path.
```

Short answer:

> I did not treat the Fabric UI as the deployment package. I used Fabric DEV to implement and validate, then represented the database objects properly in the database object repository.

## 11. Future Workflow for Changes

When a warehouse database object changes:

```text
1. Identify the changed object: schema, table, view, procedure, or function.
2. Confirm it belongs to the SupplyChain scope.
3. Sync/copy the SQL definition into data-edw-fabric.
4. Scan cross-database and external references.
5. Add only required external source stubs.
6. Normalize references through SQLCMD variables.
7. Build the local SQL solution.
8. Clean generated bin/obj files.
9. Run git diff --check.
10. Commit on a feature branch.
11. Push and create a PR into data-edw-fabric.
```

When a Fabric item/artifact changes:

```text
1. Commit through the Fabric Git workspace flow.
2. Review the changed item in data-fabric-enterprise-supply-chain.
3. Create a data-fabric-enterprise-supply-chain PR if the artifact change should be promoted.
```

Talking point:

> I should not mix non-SupplyChain target objects into a SupplyChain PR. If an object is not part of the SupplyChain scope, it should not be included in this PR.

## 12. Key Points to Emphasize

Use this order:

```text
1. The architecture is separated by layer: source, processing, gold, semantic.
2. Processing and Gold have distinct responsibilities.
3. ETL Framework is used for refresh, metadata, and audit.
4. Full refresh has 10 wrapper procedures with explicit dependency order.
5. TableDictionary and AuditLog coverage has been verified for framework-loaded targets.
6. Fabric workspace repo (`data-fabric-enterprise-supply-chain`) and database object repo (`data-edw-fabric`) separation follows ownership: Fabric artifacts vs database objects.
7. data-edw-fabric is set up with SQL projects, publish profiles, and external references.
8. Local build passed with 0 errors before PR.
9. Source references are resolved through SQLCMD variables, not arbitrary hard-coded names.
10. The DQForecastAccuracy exception is explicitly identified.
```

## 13. Likely Questions and Answer Points

### Q1. Why are there two repositories?

Answer:

```text
The two repositories manage different artifact types.
data-fabric-enterprise-supply-chain manages Fabric workspace/item artifacts.
data-edw-fabric manages database objects and SQL project deployment structure.
This separation makes review, ownership, and release pipeline behavior clearer.
```

### Q2. Why does a warehouse item show changes in Fabric Git, but the database object PR goes to data-edw-fabric?

Answer:

```text
Fabric Git can detect item-level changes for the warehouse.
However, SQL objects inside the warehouse are database objects.
The operating model is that database objects are versioned, reviewed, and deployed through the database object repository.
```

### Q3. Why is there a `Databricks` folder in the database object repo `data-edw-fabric`?

Answer:

```text
It is an external-reference project/folder for SQL build.
It maps to Enterprise_Lakehouse through a SQLCMD variable.
It is not Azure Databricks runtime job code.
```

### Q4. Are all tables logged in TableDictionary?

Answer:

```text
All 50 ETL Framework load calls in the full refresh wrappers match TableDictionary rows.
AuditLog also has Process Complete coverage for the framework-loaded targets that were checked.
The known exception is DQForecastAccuracy, which is currently loaded by direct INSERT inside the Gold wrapper.
```

### Q5. What are `_Wrk` schemas for?

Answer:

```text
_Wrk views are the source/transform layer.
Final tables are refreshed from _Wrk views through the ETL Framework.
This keeps transformation logic readable and final tables stable for downstream consumers.
```

### Q6. Why split Silver into W01/W02/W03?

Answer:

```text
To make dependencies explicit.
Some objects depend on shared/reference objects or earlier Silver outputs.
The wave structure makes orchestration predictable and easier to hand off to a scheduler.
```

### Q7. What does the local build prove?

Answer:

```text
It proves the SQL project compiles, external references resolve, and the dacpac build path is valid.
It does not prove business data correctness by itself.
Runtime correctness still needs ETL execution, AuditLog, row counts, DQ checks, and semantic smoke testing.
```

### Q8. What happens if there is a new source reference later?

Answer:

```text
Scan the SQL object to identify the referenced source.
Add only the required source stub to the external-reference project.
Map it through SQLCMD variable/publish profile configuration.
Build the solution again before PR.
```

### Q9. Where does SQL Agent fit?

Answer:

```text
SQL Agent or another enterprise scheduler can own the top-level schedule.
It can trigger the full refresh entrypoint or wrapper procedures.
Execution metadata is still recorded by the ETL Framework.
```

### Q10. What are the current risks or follow-ups?

Answer:

```text
DQForecastAccuracy is currently a direct insert, not a framework-loaded target.
Build has SQL71558 casing warnings but 0 errors.
Future changes should be scanned carefully to avoid including unrelated source/domain objects in a SupplyChain PR.
```

### Q11. How did you apply the ETL Framework across the three medallion layers?

Answer:

```text
Bronze/source layer:
  The ETL Framework is not the raw enterprise ingestion owner in this scope.
  SupplyChain consumes source surfaces such as Enterprise_Lakehouse.

Silver/Processing layer:
  ETL Framework is applied to curated Processing target tables.
  Wrappers call usp_RefreshCuratedTableFromView to load final tables from _Wrk views.
  TableDictionary and AuditLog track metadata and runtime execution.

Gold/Serving layer:
  ETL Framework is applied to framework-managed Gold targets.
  Gold procedures run after Silver dependencies.
  Gold tables become the serving contract for semantic/reporting.
```

Short version:

> Medallion defines layer responsibility. ETL Framework controls refresh, metadata, and audit for curated Processing and Gold loads.

### Q12. Which stored procedures should we pay attention to, and what is the refresh order?

Answer:

```text
The main order is:
1. Shared ReferenceMaster
2. Shared Staging
3. Forecast Silver W01
4. Forecast Silver W02
5. Forecast Silver W03
6. Forecast Gold
7. Inventory Silver W01
8. Inventory Silver W02
9. Inventory Silver W03
10. Inventory Gold
```

Procedure names:

```text
Usp_Refresh_Shared_ReferenceMaster
Usp_Refresh_Shared_Staging
Usp_Refresh_ForecastAccuracy_Silver_W01
Usp_Refresh_ForecastAccuracy_Silver_W02
Usp_Refresh_ForecastAccuracy_Silver_W03
Usp_Refresh_ForecastAccuracy_Gold
Usp_Refresh_InventoryHealth_Silver_W01
Usp_Refresh_InventoryHealth_Silver_W02
Usp_Refresh_InventoryHealth_Silver_W03
Usp_Refresh_InventoryHealth_Gold
```

Key point:

> Shared first, Silver before Gold, and Forecast and Inventory handled as separate mart flows.

### Q13. How do you understand CI/CD in this setup?

Answer:

```text
CI/CD here is not just committing code.
It is the controlled promotion path for each artifact type.

data-fabric-enterprise-supply-chain:
  Fabric workspace artifacts.
  Pipeline, notebook, item metadata, semantic model, and report changes.

data-edw-fabric:
  Database objects.
  Tables, views, procedures, schemas, functions, and SQL project configuration.

CI:
  Local build, SQL project validation, reference resolution, git diff check.

CD:
  Approved PR into the correct repository.
  Release pipeline deploys database objects or artifacts according to ownership.
```

Opinion:

> This separation is healthy from a DataOps perspective because it makes ownership clear and reduces deployment risk. Fabric UI is a good authoring and validation surface, but promotion should go through repositories and PRs so there is review, build validation, and release control.

### Q14. What is your opinion about the current setup?

Answer:

```text
Architecture:
  Separating Processing and Gold is the right direction.
  Processing keeps transformation and intermediate logic.
  Gold keeps the serving/reporting contract.

Operation:
  ETL Framework gives us a consistent refresh, metadata, and audit pattern.
  Wrapper procedures make orchestration explicit and repeatable.

CI/CD:
  Fabric workspace repo (`data-fabric-enterprise-supply-chain`) and database object repo (`data-edw-fabric`) separation is appropriate because Fabric artifacts and database objects have different deployment lifecycles.

Follow-up:
  Direct-insert exceptions should remain explicit, or be standardized later if the team wants all targets to go through the ETL Framework.
  External source stubs should stay minimal and only be added when actually referenced.
```

Short opinion:

> My opinion is that the direction is correct: keep Fabric as the authoring surface, use ETL Framework for operational consistency, and use data-edw-fabric for database-object governance. The main improvement area is to keep exceptions explicit and avoid over-including unrelated source/domain objects.

## 14. Deep-Dive Answer Bank

Use this section when the discussion goes deeper or the question is indirect.

### A. Architecture ownership

Short answer:

> My ownership in this scope is SupplyChain domain objects: Processing Warehouse, Gold Warehouse, ETL wrapper procedures, metadata alignment with the ETL Framework, and database-object PRs through the database object repo `data-edw-fabric`. Shared source surfaces such as Enterprise_Lakehouse are dependencies, not the enterprise-wide runtime ingestion layer I own.

Expanded answer:

```text
I separate ownership into three layers:

1. Source/shared surface:
   Enterprise_Lakehouse and shared source schemas.
   SupplyChain consumes these through external references.

2. Domain transformation:
   SupplyChain_Processing_Warehouse.
   This is the main Silver logic scope.

3. Domain serving:
   SupplyChain_Gold_Warehouse.
   This is the BI/semantic consumption scope.
```

Key phrase:

> I own the SupplyChain domain transformation and serving objects, not the enterprise-wide source ingestion surface.

### B. Why external source stubs are needed in the database object repo `data-edw-fabric`

Short answer:

> SQL project build needs object definitions to validate references. If a view references `[Enterprise_Lakehouse].[schema].[table]`, data-edw-fabric needs an external reference/stub so the compiler can resolve that object.

Expanded answer:

```text
At runtime, the object reads from Enterprise_Lakehouse.
At SQL project build time, the compiler does not infer every live workspace source object.
Therefore, the project needs external references and source stubs.
The publish profile maps SQLCMD variables to actual database names.
```

Key phrase:

> Source stubs are compile-time contracts, not new runtime pipelines.

### C. Why there are many external stub files

Answer:

```text
The _Wrk views reference multiple source tables/views.
Each referenced object needs a minimal definition so SQL build can resolve it.
Only source objects actually referenced by SupplyChain SQL should be added as stubs.
If a source reference changes later, the workflow is to scan dependencies, add/remove the corresponding stub, and rebuild.
```

If they focus on the `Databricks` name:

> In this repository, Databricks is the existing external-reference project naming pattern. It maps to Enterprise_Lakehouse in publish profiles for this Fabric workload. It does not mean this PR creates Databricks jobs.

### D. Does build success guarantee deployment success?

Answer:

```text
Build success is necessary validation, not a full guarantee.
It confirms that the SQL project compiles, references resolve, and dacpac output can be produced.
Runtime deployment still depends on target environment, permissions, existing objects, data availability, and release pipeline configuration.
```

Add if needed:

> That is why I separate local build validation from runtime validation. Runtime validation comes from ETL execution, AuditLog, row counts, DQ checks, and semantic smoke testing.

### E. Why not commit everything through the Fabric workspace repository?

Answer:

```text
The Fabric workspace repository is appropriate for Fabric item artifacts.
However, tables, views, procedures, and schemas are database objects.
The database object repository provides SQL projects, publish profiles, build validation, and release ownership.
Therefore, database objects should go through the database object repo `data-edw-fabric`.
```

Bridge phrase:

> Fabric Git tells me that an item changed. data-edw-fabric is where the database object definition should be reviewed and promoted.

### F. How to ensure the PR does not include other domains

Answer:

```text
I check scope by target ownership and dependency.
Target objects must be in SupplyChain Processing or Gold warehouses.
External source stubs should only be added when directly referenced by SupplyChain views/procedures.
Objects owned by Retail, Manufacturing, Wholesale Quality, Product Sourcing, or other domains should not be included as target objects in this SupplyChain PR.
```

If a source schema name does not sound like SupplyChain:

> If the schema/source name appears under an external reference, I treat it as a dependency source. If the target object is in the SupplyChain warehouse and references that source to build a SupplyChain mart, the stub is a compile-time dependency, not an ownership transfer.

### G. Is TableDictionary supposed to include all physical tables?

Answer:

```text
For the current verification scope, all framework-loaded targets in the full refresh wrappers have TableDictionary rows.
However, TableDictionary is not necessarily the same as every physical object in the warehouse.
It is the operational registry for framework-managed refresh targets.
```

Numbers:

```text
50 framework load calls checked.
50 matched TableDictionary.
0 missing for framework-loaded targets.
46 unique framework-loaded target tables.
49 SupplyChain TableDictionary rows total.
```

Known exception:

> DQForecastAccuracy currently uses direct insert inside the Gold wrapper, so I would not describe it as a framework-loaded target unless it is refactored into the framework refresh pattern.

### H. Why 49 TableDictionary rows but 46 unique loaded tables?

Answer:

```text
Full refresh call count and TableDictionary registry count are not the same metric.
50 is the number of framework load calls.
46 is the number of unique target tables loaded by those calls.
49 is the number of SupplyChain rows in TableDictionary, including rows registered as metadata but not directly called by the current full refresh path.
```

Short answer:

> Calls, unique targets, and registry rows are three different counts.

### I. Can the full refresh be parallelized?

Answer:

```text
Some parts could potentially be parallelized if dependencies are clear and source capacity allows it.
The current design prioritizes deterministic order:
Shared prerequisites -> Forecast Silver waves -> Forecast Gold -> Inventory Silver waves -> Inventory Gold.
After runtime is stable, we can review the dependency graph for safe parallelization.
```

Key phrase:

> Current design optimizes correctness and dependency clarity first. Parallelization can be a later optimization.

### J. What should happen with DQForecastAccuracy?

Answer:

```text
It is currently a known exception because it is loaded by direct insert inside the Gold wrapper.
There are two options:
1. Keep it as-is if this DQ output is intentionally handled differently and reviewers accept it.
2. Refactor it into the ETL Framework refresh pattern and add/register metadata if consistent governance is required.
```

Safe phrasing:

> I am not hiding it as a gap. I identified it explicitly because it is outside the normal framework-loaded pattern.

### K. How will production deployment work?

Answer:

```text
Database objects:
  PR into data-edw-fabric.
  Review and approval.
  Release pipeline deploys database objects to the higher environment.

Fabric artifacts:
  PR into data-fabric-enterprise-supply-chain.
  Review and approval.
  Fabric workspace/release process promotes item artifacts.
```

Key phrase:

> The deployment path follows artifact type, not only where I first saw the change in Fabric UI.

### L. What if future work starts in live Fabric DEV?

Answer:

```text
DEV can be the authoring surface.
Before promotion, the change must be materialized into the correct repository:
  database objects -> data-edw-fabric
  Fabric item artifacts -> data-fabric-enterprise-supply-chain
Then build, test, PR, and review.
```

Short answer:

> DEV can be where I build and validate, but repository PR is the controlled promotion path.

### M. Why not call Processing Bronze?

Answer:

```text
Processing is not raw landing.
It already contains curated reference, staging, and transformation logic, and it is refreshed through the ETL Framework.
Therefore, in this SupplyChain architecture, Processing fits the Silver/curated layer.
Bronze/source access is represented by Enterprise_Lakehouse and other source surfaces.
```

### N. How does the semantic model fit?

Answer:

```text
The semantic model and reports should consume the Gold layer.
Gold tables are shaped as facts, dimensions, and business-facing metrics.
Processing keeps intermediate transformation logic so the semantic model does not carry complex transformation responsibility.
```

Key phrase:

> Gold should be the stable serving contract for semantic and reporting consumption.

### O. Has data correctness been tested?

Answer:

```text
There is structural/build validation and ETL Framework runtime coverage verification.
Data correctness should be validated by mart:
  row counts
  freshness / LoadDT
  DQ outputs
  business sample reconciliation
  semantic smoke testing
```

Safe phrasing:

> I separate engineering readiness from business sign-off. Build and ETL logs support engineering readiness; business reconciliation should be reviewed with mart owners.

### P. Should non-SupplyChain objects or sources be removed?

Answer:

```text
In a SupplyChain PR, I should include only SupplyChain target database objects.
If source stubs are external dependencies, they should exist only when actually referenced by SupplyChain objects.
If an object is a target object owned by another domain, it should not be included in this PR.
```

Bridge phrase:

> The filter is target ownership plus actual dependency, not just source database name.

## 15. Review Panel Simulation and Response Playbook

This section is designed for a senior review meeting where reviewers may ask direct questions, challenge assumptions, or make comments that are not phrased as questions.

Response principle:

```text
1. Do not over-defend.
2. Restate the technical boundary.
3. Tie the answer back to architecture, ownership, validation, or operating process.
4. Use verified numbers where possible.
5. If something is a follow-up, state it as a follow-up instead of pretending it is already solved.
```

### A. Director / IT leadership angle

Likely concern:

> This is a sizable change. How do I know this is controlled and not just a large Fabric export?

Suggested response:

> I agree this should be treated as a controlled database-object change, not just a workspace export. That is why I separated the scope into data-fabric-enterprise-supply-chain and data-edw-fabric. data-fabric-enterprise-supply-chain is for Fabric workspace artifacts. data-edw-fabric is for warehouse database objects. For the current scope, the database-object PR is limited to the two SupplyChain warehouse scopes: Processing and Gold, plus the required SQL project references and external source stubs needed for build validation.

Key facts to mention:

```text
2 SupplyChain warehouse scopes:
  SupplyChain_Processing_Warehouse
  SupplyChain_Gold_Warehouse

10 wrapper procedures.
50 ETL Framework load calls.
0 missing TableDictionary rows for framework-loaded targets.
0 SQL build errors.
```

If they say:

> This should be easy to support after you hand it off.

Answer:

> The support model is based on wrapper procedure order, ETL Framework logging, TableDictionary metadata, and data-edw-fabric database-object versioning. The goal is that someone can review the refresh order, inspect AuditLog, check TableDictionary freshness, and trace the deployed SQL objects back to the database object repository.

### B. Senior DE architecture challenge

Likely question:

> Why did you choose Processing and Gold warehouses instead of putting everything in one warehouse?

Suggested response:

> I separated them because they have different responsibilities. Processing is the curated transformation layer where staging, reference, forecast, sales, open order, and inventory logic is prepared. Gold is the serving layer where facts and dimensions are shaped for semantic/report consumption. Keeping them separate reduces coupling and makes it clearer which objects are intermediate and which objects are consumer-facing.

If they push:

> Could this be over-engineered?

Answer:

> It would be over-engineered if the domain only had a few direct report tables. In this case there are multiple marts, shared reference dimensions, working views, wrapper procedures, and ETL Framework metadata. The separation helps because Forecast Accuracy and Inventory Health both depend on shared and intermediate objects before producing Gold outputs.

### C. Medallion and ETL Framework challenge

Likely question:

> How exactly does the ETL Framework fit the medallion pattern?

Suggested response:

> The medallion pattern defines the responsibility of each layer. Source access is represented by Enterprise_Lakehouse and related source surfaces. Processing is the Silver curated layer. Gold is the serving layer. The ETL Framework is the operational layer that controls how curated Processing and Gold tables are refreshed, logged, and tracked.

Detailed answer:

```text
Source/Bronze:
  Consumed as dependency source surfaces.
  Not owned as raw ingestion by this SupplyChain PR.

Processing/Silver:
  Wrapper procedures refresh curated tables from _Wrk views.
  Refresh is controlled through usp_RefreshCuratedTableFromView.
  TableDictionary and AuditLog provide metadata and runtime visibility.

Gold/Serving:
  Gold procedures run after Silver dependencies.
  Framework-managed Gold targets follow the same refresh and audit pattern.
  Gold becomes the semantic/reporting contract.
```

If they say:

> The ETL Framework should be consistently applied.

Answer:

> For framework-loaded targets in the full refresh path, I verified 50 ETL Framework load calls and all 50 have matching TableDictionary rows. The known exception is DQForecastAccuracy, which is currently loaded by direct insert inside the Gold wrapper. I would keep that explicit as an exception or refactor it later if the team wants every target to follow the same framework-loaded pattern.

### D. Orchestration and stored procedure challenge

Likely question:

> Which stored procedures are the main orchestration points?

Suggested response:

> The main orchestration points are the 10 wrapper procedures. They are intentionally ordered as shared prerequisites first, then Forecast Silver waves, Forecast Gold, Inventory Silver waves, and Inventory Gold.

Procedure order:

```text
1. Usp_Refresh_Shared_ReferenceMaster
2. Usp_Refresh_Shared_Staging
3. Usp_Refresh_ForecastAccuracy_Silver_W01
4. Usp_Refresh_ForecastAccuracy_Silver_W02
5. Usp_Refresh_ForecastAccuracy_Silver_W03
6. Usp_Refresh_ForecastAccuracy_Gold
7. Usp_Refresh_InventoryHealth_Silver_W01
8. Usp_Refresh_InventoryHealth_Silver_W02
9. Usp_Refresh_InventoryHealth_Silver_W03
10. Usp_Refresh_InventoryHealth_Gold
```

If they say:

> Why not run Forecast and Inventory in parallel?

Answer:

> Some parts may be parallelizable later, but I would first keep the deterministic order until the dependency graph and runtime behavior are stable. The current order prioritizes correctness and dependency clarity. Once the process is stable, the next optimization would be to review which mart waves are independent enough to parallelize safely.

### E. CI/CD and release engineering challenge

Likely question:

> What is your understanding of CI/CD for this setup?

Suggested response:

> CI/CD here is artifact-type based. Fabric workspace artifacts go through data-fabric-enterprise-supply-chain. Database objects go through the database object repo `data-edw-fabric`. CI means the SQL project can restore, build, resolve references, and pass diff checks before PR. CD means the approved PR is deployed by the appropriate release pipeline for that repository and artifact type.

If they say:

> You committed from Fabric, so why are you also touching data-edw-fabric?

Answer:

> Fabric Git shows item-level changes, but SQL objects inside warehouses are database objects. The database object repository is the correct promotion path for schemas, tables, views, stored procedures, functions, SQL project configuration, publish profiles, and required external stubs.

If they ask:

> What would you do for future changes?

Answer:

```text
Database object change:
  Sync to data-edw-fabric.
  Scan dependencies.
  Add required stubs only.
  Build SQL solution.
  Commit feature branch.
  Create data-edw-fabric PR.

Fabric artifact change:
  Commit through Fabric Git.
  Review in data-fabric-enterprise-supply-chain.
  Create data-fabric-enterprise-supply-chain PR if it should be promoted.
```

### F. Database project and build challenge

Likely question:

> What did the local build actually prove?

Suggested response:

> The local build proves the SQL project structure is valid, cross-database references resolve, and dacpac generation is healthy. It does not prove business data correctness, production permissions, or scheduler runtime success.

Use this distinction:

```text
Build validation proves:
  SQL project compiles.
  References resolve.
  Dacpac build path works.

Runtime validation proves:
  ETL execution succeeds.
  AuditLog records process status.
  TableDictionary freshness is updated.
  Row counts and DQ checks look correct.
  Semantic/report smoke tests pass.
```

If they say:

> There are still SQL71558 warnings.

Answer:

> Those are casing warnings from SQL project validation. The current build has 0 errors. I would not ignore warnings permanently, but I would separate them from blocking build errors. If the team wants warning cleanup as a standard, I can address casing normalization separately from the functional database-object PR.

### G. External reference / Databricks challenge

Likely concern:

> Why are there Databricks files if this is a Fabric warehouse implementation?

Suggested response:

> In the database object repo `data-edw-fabric`, Databricks is the external-reference project/folder naming pattern used by the SQL project. For this workload, the publish profile maps `$(Databricks)` to `Enterprise_Lakehouse`. These files are compile-time source stubs so views referencing source surfaces can build. They are not Azure Databricks jobs or runtime pipelines.

If they push:

> Are you adding sources you do not own?

Answer:

> I am not adding them as owned target objects. I am representing them as compile-time dependency contracts only when SupplyChain SQL objects directly reference them. The ownership boundary remains the SupplyChain Processing and Gold target objects.

### H. Scope contamination challenge

Likely concern:

> I see source names that look outside SupplyChain. Are we mixing domains?

Suggested response:

> I separate target ownership from source dependency. The target objects in scope should be SupplyChain Processing and Gold objects. External source stubs should exist only when those SupplyChain objects directly reference the source. If an object is a target object owned by another domain, it should not be included in this SupplyChain PR.

If they say:

> Please keep the PR SupplyChain-only.

Answer:

> Agreed on the boundary. The PR should include SupplyChain target database objects and only the external dependency stubs needed to compile those objects. Anything outside that boundary should be removed or handled in the owning domain's process.

### I. Data quality and reconciliation challenge

Likely question:

> How do you know the data is correct?

Suggested response:

> I would separate engineering readiness from business reconciliation. Engineering readiness is supported by SQL project build, ETL Framework execution, AuditLog, TableDictionary freshness, and row count/freshness checks. Business correctness still needs mart-level reconciliation with owners: sample checks, DQ outputs, expected metric comparisons, and semantic smoke testing.

If they ask:

> What are the immediate data quality checks?

Answer:

```text
After full refresh:
  Check wrapper completion in AuditLog.
  Check TableDictionary modified/freshness metadata.
  Check row counts for major Processing and Gold targets.
  Check LoadDT or equivalent freshness columns.
  Check DQForecastAccuracy output.
  Smoke test semantic model/report visuals against expected high-level totals.
```

### J. Observability and support challenge

Likely question:

> If the job fails, where do we look first?

Suggested response:

> I would start with the orchestration step, then the wrapper procedure, then ETL Framework logs. The main signals are which wrapper procedure failed, what AuditLog recorded, whether the failed load reached TableDictionary update, and whether the failing target depends on an upstream _Wrk view or source reference.

Triage path:

```text
1. Identify failed wrapper step.
2. Check AuditLog for start/failure/complete.
3. Identify target table and source _Wrk view.
4. Validate upstream dependency/source availability.
5. Check row count/freshness of upstream objects.
6. Re-run only the safe scope if the procedure supports it and the team approves.
```

If they say:

> We need this to be supportable by someone else.

Answer:

> That is why I want the refresh order, wrapper procedures, ETL Framework calls, TableDictionary metadata, and data-edw-fabric SQL definitions to be explicit. Support should not depend on remembering what was manually changed in Fabric.

### K. Security and access challenge

Likely question:

> Are there any security or permission assumptions?

Suggested response:

> The PR itself is database-object definition work. Runtime permissions still need to be validated through the deployment pipeline and target environment. The important assumption is that the deployed warehouse objects can resolve the referenced databases and that the runtime identity has access to the required source surfaces and ETL Framework objects.

If they push for specifics:

```text
Permission surfaces to validate:
  SupplyChain_Processing_Warehouse
  SupplyChain_Gold_Warehouse
  ETL_Framework
  Enterprise_Lakehouse / external source surface
  release pipeline deployment identity
  scheduler/runtime identity
```

Safe answer:

> I would not claim production permissions are proven by local build. Local build validates structure. Deployment and runtime identity must be validated in the release environment.

### L. Performance and scalability challenge

Likely question:

> How will this scale as data volume grows?

Suggested response:

> The current structure gives us a scalable operating model because transformations are separated into Processing and Gold, and refresh is broken into dependency waves. The next performance work should be data-driven: identify expensive views/procedures, check row counts and runtime by wrapper step, and optimize the highest-cost transformations first.

If they ask for concrete levers:

```text
Potential optimization levers:
  reduce repeated transformations in _Wrk views
  materialize reusable intermediate outputs in Processing
  review join keys and filters
  split or parallelize independent waves after dependency review
  monitor row count growth by mart
  optimize Gold tables for semantic consumption patterns
```

### M. Rollback and change control challenge

Likely question:

> If this deployment causes an issue, what is the rollback path?

Suggested response:

> The rollback path should follow the repository and release pipeline. Because database objects are represented in the database object repo `data-edw-fabric`, a rollback can be handled by reverting the PR/commit or deploying a previous approved version through the release process. I would avoid manual production edits because they break traceability.

If they say:

> What about emergency fixes?

Answer:

> For an emergency, the team may choose a controlled hotfix path, but the fix should still be backfilled into the correct repository so the source of truth remains consistent.

### N. Semantic / reporting challenge

Likely question:

> How does this affect the semantic model and reports?

Suggested response:

> The semantic model should consume Gold, not raw Processing logic. Gold tables are shaped as dimensions, facts, and business-facing outputs. This keeps complex transformation logic out of the semantic layer and gives reports a stable serving contract.

If they ask:

> What would you smoke test?

Answer:

```text
Gold availability:
  key fact and dimension tables exist and are populated.

Freshness:
  latest LoadDT or equivalent timestamp is current.

Semantic model:
  refresh succeeds.
  key measures render.
  major visuals return expected high-level totals.
```

### O. Meeting comments that are not direct questions

Comment:

> This PR is larger than expected.

Response:

> The size is mainly because SQL projects store each database object and source stub as separate files. The logical scope is smaller: two SupplyChain warehouses, required SQL project wiring, and compile-time external references.

Comment:

> I am worried about non-SupplyChain objects.

Response:

> I would use target ownership plus actual dependency as the filter. SupplyChain target objects stay in scope. External stubs stay only when directly referenced by SupplyChain objects. Other domain target objects should not be in this PR.

Comment:

> The current process seems confusing with two repos.

Response:

> The split is actually the control point. data-fabric-enterprise-supply-chain is for Fabric item artifacts. data-edw-fabric is for database objects. The confusion comes from Fabric Git showing item-level changes even when the meaningful change is a database object inside the warehouse.

Comment:

> We need confidence before production.

Response:

> I would separate confidence into stages: SQL project build confidence, ETL runtime confidence, data quality/reconciliation confidence, semantic/report smoke-test confidence, and release pipeline confidence.

Comment:

> This should follow the standard process going forward.

Response:

> Going forward, I would use data-edw-fabric for warehouse database objects and data-fabric-enterprise-supply-chain for Fabric artifacts. For each database-object change, I would sync the SQL definition, scan dependencies, build locally, and create a database-object PR.

Comment:

> I do not want this to become hard to maintain.

Response:

> Maintainability is the reason for the separation: Processing for transformations, Gold for serving, ETL Framework for refresh/audit/metadata, wrapper procedures for repeatable order, and data-edw-fabric for versioned database objects.

### P. Final self-assessment of readiness

What this document now covers well:

```text
Architecture:
  layer responsibility, medallion mapping, Processing vs Gold.

ETL Framework:
  where it applies, what it logs, TableDictionary vs AuditLog, known exception.

Orchestration:
  10 wrapper procedures, refresh order, dependency waves.

DataOps / CI-CD:
  Fabric workspace repo (`data-fabric-enterprise-supply-chain`) vs database object repo (`data-edw-fabric`), PR flow, local build, release ownership.

Implementation detail:
  local repo paths, branch name, SQL project files, publish profiles,
  SQLCMD mappings, external stubs, validation commands.

Review defense:
  answers for ownership, scope contamination, source stubs, deployment,
  rollback, support, security, performance, and semantic consumption.
```

Remaining items that may require live confirmation if asked:

```text
Exact production release pipeline name and approver configuration.
Exact scheduler owner if SQL Agent or another enterprise scheduler is used.
Production runtime identity and permissions.
Business reconciliation thresholds for Forecast Accuracy and Inventory Health.
Expected SLA/runtime target for full refresh.
Formal rollback procedure used by the release team.
```

Safe closing if a question goes beyond current evidence:

> I can separate what is already validated from what still needs environment confirmation. The database-object structure and references have been validated locally. ETL Framework coverage has been checked in DEV for framework-loaded targets. Production pipeline ownership, runtime identity, SLA, and business reconciliation thresholds should be confirmed with the release and domain owners.

## 16. Closing Statement

Suggested close:

> In summary, the current SupplyChain implementation is not just a set of warehouse objects. It is an operating model with medallion layers, ETL Framework metadata, wrapper procedures with explicit refresh order, TableDictionary and AuditLog observability, and a Git/CI-CD split between data-fabric-enterprise-supply-chain and data-edw-fabric. This gives the SupplyChain domain a controlled path from DEV implementation to reviewed PR and managed deployment.
