"""Generate Bob-alignment SQL scripts from existing v10 ETL DDLs.

Reads:
    Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/staging_ddl.sql
    Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/silver_views.sql
    Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/gold_views.sql
    Enterprise_SupplyChain_Dev_architect/projects/forecast/etl/meta_sps.sql

Writes scripts/01..13 in this folder.

Transformations applied:
    _ENH        -> _Enh
    _WRK        -> _Wrk
    Staging_WRK -> Staging_Wrk
    vw_         -> v_
    (column refs and join refs are kept unchanged — only object/schema names are renamed)

Run:  python3 generate_scripts.py
"""
from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
ETL_DIR = REPO_ROOT / "Enterprise_SupplyChain_Dev_architect" / "projects" / "forecast" / "etl"
OUT_DIR = Path(__file__).resolve().parent / "sql_scripts"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# --- Naming map ---
SCHEMA_RENAMES = {
    "Staging_WRK": "Staging_Wrk",
    "ReferenceMaster_ENH": "ReferenceMaster_Enh",
    "SalesHistory_ENH": "SalesHistory_Enh",
    "ForecastHistory_ENH": "ForecastHistory_Enh",
    "OpenOrderHistory_ENH": "OpenOrderHistory_Enh",
}

# Tables in each old schema (from existing ctas_tables.sql + meta_sps + observation)
TABLES_PER_SCHEMA = {
    "Staging_WRK": [
        "InvoiceDetailEdw", "InvoiceHeaderEdw", "ProductEdw",
        "DemandForecastSnapshotDailyEdw",
    ],
    "ReferenceMaster_ENH": [
        "Calendar", "CustomerAccount", "CustomerAccountGroup", "CustomerGrouping",
        "CustomerShippingLocation", "ForecastCycle", "ForecastHorizon",
        "ItemMaster", "OrderType", "Product", "Warehouse",
    ],
    "SalesHistory_ENH": [
        "ActualDemandMonthly", "ActualDemandWeekly", "InvoiceDetailLineLevel",
        "InvoiceWeekly",
    ],
    "ForecastHistory_ENH": [
        "ForecastDemandMonthly", "NaiveForecastMonthly",
    ],
    "OpenOrderHistory_ENH": [
        "OpenOrderLineLevel", "OpenOrderMonthly",
    ],
}

# Views in each old schema (vw_*)
VIEWS_PER_SCHEMA = {
    "Staging_WRK": ["vw_Codatan", "vw_Comast", "vw_Extord", "vw_Extorit"],
    "ReferenceMaster_ENH": [
        "vw_Calendar", "vw_CustomerAccount", "vw_CustomerAccountGroup",
        "vw_CustomerGrouping", "vw_CustomerShippingLocation", "vw_ForecastCycle",
        "vw_ForecastHorizon", "vw_ItemMaster", "vw_OrderType", "vw_Product",
        "vw_Warehouse",
    ],
    "SalesHistory_ENH": [
        "vw_ActualDemandMonthly", "vw_ActualDemandWeekly",
        "vw_InvoiceDetailLineLevel", "vw_InvoiceWeekly",
    ],
    "ForecastHistory_ENH": [
        "vw_ForecastDemandMonthly", "vw_NaiveForecastMonthly",
    ],
    "OpenOrderHistory_ENH": [
        "vw_OpenOrderLineLevel", "vw_OpenOrderMonthly",
    ],
}

GOLD_VIEWS = [
    "vw_DimCalendar", "vw_DimCustomerGrouping", "vw_DimForecastHorizon",
    "vw_DimProduct", "vw_DimWarehouse", "vw_FactForecastActual",
    "vw_FactForecastKpi",
]


def transform_sql(text: str) -> str:
    """Apply naming map to a SQL blob."""
    out = text
    for old, new in SCHEMA_RENAMES.items():
        # Match standalone schema name (with bracketed or dotted forms)
        out = re.sub(rf"\b{re.escape(old)}\b", new, out)
    # View prefix vw_X -> v_X (only when preceded by a dot or whitespace + word boundary)
    out = re.sub(r"\bvw_", "v_", out)
    return out


# ---------- Step 1: Create new schemas ----------
def gen_01_create_schemas() -> None:
    lines = ["-- 01_create_new_schemas.sql",
             "-- Create renamed schemas. Idempotent.",
             ""]
    for new in SCHEMA_RENAMES.values():
        lines.append(
            f"IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '{new}') "
            f"EXEC('CREATE SCHEMA {new}');"
        )
    (OUT_DIR / "01_create_new_schemas.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 2: Transfer tables ----------
def gen_02_transfer_tables() -> None:
    lines = ["-- 02_transfer_tables.sql",
             "-- ALTER SCHEMA TRANSFER for all v10 tables. Non-destructive — preserves data.",
             ""]
    for old, new in SCHEMA_RENAMES.items():
        lines.append(f"-- {old} -> {new}")
        for table in TABLES_PER_SCHEMA.get(old, []):
            lines.append(f"ALTER SCHEMA {new} TRANSFER {old}.{table};")
        lines.append("")
    (OUT_DIR / "02_transfer_tables.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 3: Drop old views (Processing) ----------
def gen_03_drop_old_views() -> None:
    lines = ["-- 03_drop_old_views.sql",
             "-- Drop all old vw_* views in old _ENH/_WRK schemas. Logic preserved in step 04.",
             ""]
    for old, views in VIEWS_PER_SCHEMA.items():
        lines.append(f"-- {old}")
        for v in views:
            lines.append(f"DROP VIEW IF EXISTS {old}.{v};")
        lines.append("")
    (OUT_DIR / "03_drop_old_views.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 4: Create renamed views (Processing) ----------
def gen_04_create_renamed_views() -> None:
    staging_sql = (ETL_DIR / "staging_ddl.sql").read_text()
    silver_sql = (ETL_DIR / "silver_views.sql").read_text()

    out_text = (
        "-- 04_create_renamed_views_processing.sql\n"
        "-- 28 Processing views recreated with new schema (_Enh/_Wrk) and v_ prefix.\n"
        "-- Source: etl/staging_ddl.sql + etl/silver_views.sql, transformed.\n\n"
        "-- ============== Staging views ==============\n"
        + transform_sql(staging_sql)
        + "\n\n-- ============== Silver views ==============\n"
        + transform_sql(silver_sql)
    )
    (OUT_DIR / "04_create_renamed_views_processing.sql").write_text(out_text)


# ---------- Step 5: Drop old Gold views ----------
def gen_05_drop_old_gold_views() -> None:
    lines = ["-- 05_drop_old_gold_views.sql",
             "-- Drop 7 old Gold views (vw_*) in ForecastAccuracy_DW schema.",
             "-- Note: Gold schema name (_DW) is NOT changed — only view prefix.",
             ""]
    for v in GOLD_VIEWS:
        lines.append(f"DROP VIEW IF EXISTS ForecastAccuracy_DW.{v};")
    (OUT_DIR / "05_drop_old_gold_views.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 6: Create renamed Gold views ----------
def gen_06_create_renamed_gold_views() -> None:
    gold_sql = (ETL_DIR / "gold_views.sql").read_text()
    out_text = (
        "-- 06_create_renamed_views_gold.sql\n"
        "-- 7 Gold views recreated with v_ prefix. 3-part-name refs to Processing schemas updated.\n"
        "-- Source: etl/gold_views.sql, transformed.\n\n"
        + transform_sql(gold_sql)
    )
    (OUT_DIR / "06_create_renamed_views_gold.sql").write_text(out_text)


# ---------- Step 7: Drop + recreate SPs ----------
def gen_07_drop_recreate_sps() -> None:
    sps_sql = (ETL_DIR / "meta_sps.sql").read_text()
    transformed = transform_sql(sps_sql)
    # Wrap with DROP-IF-EXISTS preamble
    drop_lines = [
        "-- 07_drop_recreate_sps.sql",
        "-- DROP + CREATE all Meta SPs (refs to old schema names removed). Logic unchanged.",
        "",
    ]
    sp_names = re.findall(r"CREATE PROCEDURE\s+(Meta\.[A-Za-z_]+)", sps_sql)
    for sp in sp_names:
        drop_lines.append(f"DROP PROCEDURE IF EXISTS {sp};")
        drop_lines.append("GO")
    drop_lines.append("")
    drop_lines.append("-- Recreate (transformed):")
    drop_lines.append("")
    out_text = "\n".join(drop_lines) + transformed
    (OUT_DIR / "07_drop_recreate_sps.sql").write_text(out_text)


# ---------- Step 8: Update AssetRegistry / DQRule ----------
def gen_08_update_asset_registry() -> None:
    lines = ["-- 08_update_asset_registry.sql",
             "-- Update Meta.AssetRegistry, DQRule, LineageEdge with new schema names.",
             ""]
    for old, new in SCHEMA_RENAMES.items():
        lines.append(
            f"UPDATE Meta.AssetRegistry SET physical_schema = '{new}' "
            f"WHERE physical_schema = '{old}';"
        )
    lines.append("")
    for old, new in SCHEMA_RENAMES.items():
        lines.append(
            f"UPDATE Meta.DQRule SET target_schema = '{new}' "
            f"WHERE target_schema = '{old}';"
        )
    lines.append("")
    # LineageEdge — both source/target schema columns
    for old, new in SCHEMA_RENAMES.items():
        lines.append(
            f"UPDATE Meta.LineageEdge SET source_schema = '{new}' "
            f"WHERE source_schema = '{old}';"
        )
        lines.append(
            f"UPDATE Meta.LineageEdge SET target_schema = '{new}' "
            f"WHERE target_schema = '{old}';"
        )
    lines.append("")
    # SourceContract — referenced by physical_schema in many places
    for old, new in SCHEMA_RENAMES.items():
        lines.append(
            f"UPDATE Meta.SourceContract SET target_schema = '{new}' "
            f"WHERE target_schema = '{old}';"
        )
    (OUT_DIR / "08_update_asset_registry.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 9: Drop empty old schemas ----------
def gen_09_drop_empty_schemas() -> None:
    lines = ["-- 09_drop_empty_old_schemas.sql",
             "-- Drop the 5 old schemas after verifying they are empty.",
             "-- WARNING: Run only after Step 02 transfer + Step 03 view drop succeed.",
             ""]
    for old in SCHEMA_RENAMES.keys():
        lines.append(
            f"-- Pre-check {old} is empty:")
        lines.append(
            f"-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id "
            f"WHERE s.name='{old}';  -- expected 0")
        lines.append(f"DROP SCHEMA IF EXISTS {old};")
        lines.append("")
    (OUT_DIR / "09_drop_empty_old_schemas.sql").write_text("\n".join(lines) + "\n")


# ---------- Step 10: Extend Meta.vw_TableDictionary ----------
def gen_10_extend_table_dictionary() -> None:
    """Extend Meta.vw_TableDictionary to match Bob's 65-col ETL_Framework schema."""
    sql = """-- 10_extend_table_dictionary.sql
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
"""
    (OUT_DIR / "10_extend_table_dictionary.sql").write_text(sql)


# ---------- Step 11: Create AuditLog ----------
def gen_11_create_audit_log() -> None:
    sql = """-- 11_create_audit_log.sql
-- Create Meta.AuditLog matching Bob's ETL_Framework.DW_Developer.AuditLog schema.
-- Observed cols (from EnterpriseData-Dev scan): Description, DateTime, [User], Command.
-- Plus VN-specific: error_message, asset_id (for cross-ref to AssetRegistry).
--
-- Phase 1: local-only writes from usp_LogRun.
-- Phase 2 (after Bob Q1 unblocks): cross-DB INSERT into ETL_Framework.DW_Developer.AuditLog.

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = 'Meta' AND t.name = 'AuditLog')
BEGIN
    EXEC('
    CREATE TABLE Meta.AuditLog (
        AuditID         BIGINT          NOT NULL,
        AuditDateTime   DATETIME2(6)    NOT NULL,
        UserName        VARCHAR(200)    NULL,
        Command         VARCHAR(8000)   NULL,
        Description     VARCHAR(8000)   NULL,
        ErrorMessage    VARCHAR(8000)   NULL,
        AssetID         VARCHAR(128)    NULL,
        RunID           VARCHAR(128)    NULL,
        Severity        VARCHAR(20)     NULL,
        LoadDT          DATETIME2(6)    NULL
    );
    ');
END
GO
"""
    (OUT_DIR / "11_create_audit_log.sql").write_text(sql)


# ---------- Step 12: Enhance usp_LogRun ----------
def gen_12_enhance_usp_logrun() -> None:
    sql = """-- 12_enhance_usp_logrun.sql
-- Enhanced Meta.usp_LogRun:
--   * On 'running' status -> still writes RunLog (unchanged)
--   * On final status (success/failed/skipped):
--       - UPDATE RunLog (unchanged)
--       - UPDATE AssetRegistry last_load_date + rows_loaded + next_run_time (unchanged)
--       - INSERT into Meta.AuditLog (NEW — local clone of Bob's AuditLog pattern)
--   * On 'failed' status: also INSERT detailed error record into AuditLog
-- Phase 2: after Bob grants ETL_Framework write, also INSERT into
--          EnterpriseData-Dev.ETL_Framework.DW_Developer.AuditLog (cross-DB).

DROP PROCEDURE IF EXISTS Meta.usp_LogRun;
GO

CREATE PROCEDURE Meta.usp_LogRun
    @run_id VARCHAR(128),
    @asset_id VARCHAR(128),
    @status VARCHAR(80),
    @rows_loaded BIGINT = NULL,
    @error_message VARCHAR(4000) = NULL,
    @pipeline_run_id VARCHAR(128) = NULL,
    @load_type VARCHAR(80) = NULL
AS
BEGIN
    DECLARE @retry INT = 0, @done INT = 0;
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    DECLARE @now_cst DATETIME2(6) = Meta.ufn_utc_to_cst(@now);
    DECLARE @user VARCHAR(200) = SYSTEM_USER;
    DECLARE @audit_id BIGINT = CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', @now) AS BIGINT);

    WHILE @retry < 3 AND @done = 0
    BEGIN
        BEGIN TRY
            IF @status = 'running'
            BEGIN
                INSERT INTO Meta.RunLog (run_id, asset_id, object_name, layer_name,
                                          status, start_time_utc, start_time_cst, load_type)
                SELECT @run_id, @asset_id,
                       CONCAT(physical_schema, '.', physical_object),
                       canonical_layer, 'running', @now, @now_cst,
                       COALESCE(@load_type, load_type)
                FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
            END
            ELSE
            BEGIN
                UPDATE Meta.RunLog
                SET end_time_utc = @now,
                    end_time_cst = @now_cst,
                    rows_loaded = @rows_loaded,
                    status = @status,
                    error_message = @error_message
                WHERE run_id = @run_id;

                UPDATE Meta.AssetRegistry
                SET last_load_date = @now,
                    rows_loaded = @rows_loaded,
                    next_run_time = CASE
                        WHEN frequency = 'daily'   THEN DATEADD(DAY, 1, CAST(@now AS DATE))
                        WHEN frequency = 'hourly'  THEN DATEADD(HOUR, 1, @now)
                        WHEN frequency = 'weekly'  THEN DATEADD(WEEK, 1, CAST(@now AS DATE))
                        WHEN frequency = 'monthly' THEN DATEADD(MONTH, 1, CAST(@now AS DATE))
                        ELSE DATEADD(DAY, 1, CAST(@now AS DATE))
                    END
                WHERE asset_id = @asset_id;

                -- NEW: Audit log entry (local Meta.AuditLog clone of Bob's pattern)
                INSERT INTO Meta.AuditLog (AuditID, AuditDateTime, UserName, Command,
                                            Description, ErrorMessage, AssetID, RunID,
                                            Severity, LoadDT)
                SELECT @audit_id, @now, @user,
                       CONCAT('LoadAsset:', physical_schema, '.', physical_object),
                       CASE
                           WHEN @status = 'failed'
                               THEN CONCAT('FAILED loading ', physical_schema, '.', physical_object)
                           ELSE CONCAT('Loaded ', physical_schema, '.', physical_object,
                                       ' rows=', COALESCE(CAST(@rows_loaded AS VARCHAR(20)), 'NULL'))
                       END,
                       @error_message,
                       @asset_id, @run_id,
                       CASE WHEN @status = 'failed' THEN 'ERROR' ELSE 'INFO' END,
                       @now
                FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
            END
            SET @done = 1;
        END TRY
        BEGIN CATCH
            SET @retry = @retry + 1;
            IF @retry >= 3
            BEGIN
                DECLARE @err_msg VARCHAR(4000) = ERROR_MESSAGE();
                RAISERROR('usp_LogRun failed after 3 retries: %s', 10, 1, @err_msg);
            END
            WAITFOR DELAY '00:00:02';
        END CATCH
    END
END
GO
"""
    (OUT_DIR / "12_enhance_usp_logrun.sql").write_text(sql)


# ---------- Step 13: Update pipeline SQL refs (manual checklist) ----------
def gen_13_update_pipeline_refs() -> None:
    md = """-- 13_update_pipeline_sql_refs.md
-- (NOT a SQL script — this is a manual checklist for updating Fabric pipeline activity SQL.)

# Pipeline activity SQL refs to update

After steps 1-9 are done, the following pipelines have hardcoded schema names that
must be updated via Fabric UI or REST API. Search-and-replace pattern:

| Old | New |
|-----|-----|
| `Staging_WRK` | `Staging_Wrk` |
| `ReferenceMaster_ENH` | `ReferenceMaster_Enh` |
| `SalesHistory_ENH` | `SalesHistory_Enh` |
| `ForecastHistory_ENH` | `ForecastHistory_Enh` |
| `OpenOrderHistory_ENH` | `OpenOrderHistory_Enh` |
| `vw_` | `v_` |

## Pipelines to inspect (per memory project_v10_architecture.md):

| Pipeline | ID | Likely refs |
|----------|----|-----------:|
| pl_sc_master   | f36f56b8-5668-4a0c-b991-2c28302f1710 | orchestrator — InvokeFabricPipeline only, low risk |
| pl_sc_mart     | 20db5725-80e3-4081-9ef5-01700acdf3b3 | ForEach DISTINCT project — registry-driven, low risk |
| pl_sc_staging  | 10221fb2-6e30-4911-9d95-d8dd67440d84 | Lookup `Staging_WRK` — must update |
| pl_sc_silver   | 7dc6ecda-56cc-4797-893c-1c502863323f | Lookup `*_ENH` schemas — must update |
| pl_sc_silver_wave | 797b1a02-f973-4584-bd27-bb0151549d4b | DAG wave Lookup — must update |
| pl_sc_gold     | 50ff6263-659d-4b09-9e45-b42a3434e093 | 3-part name from Processing — must update |
| pl_dq_check    | 3c7c61f6-c184-41e5-8309-f9ac3260d38d | DQ rule SQL — must update |

Use Fabric REST API:
```
GET  https://api.fabric.microsoft.com/v1/workspaces/{wsId}/items/{pipelineId}/getDefinition
PATCH (post update) → POST /updateDefinition
```

Or use the existing `05_tools/` helpers in `Enterprise_SupplyChain_Dev_architect/05_tools/`.
"""
    (OUT_DIR / "13_update_pipeline_sql_refs.md").write_text(md)


def main() -> None:
    print(f"Reading from: {ETL_DIR}")
    print(f"Writing to:   {OUT_DIR}")
    gen_01_create_schemas()
    gen_02_transfer_tables()
    gen_03_drop_old_views()
    gen_04_create_renamed_views()
    gen_05_drop_old_gold_views()
    gen_06_create_renamed_gold_views()
    gen_07_drop_recreate_sps()
    gen_08_update_asset_registry()
    gen_09_drop_empty_schemas()
    gen_10_extend_table_dictionary()
    gen_11_create_audit_log()
    gen_12_enhance_usp_logrun()
    gen_13_update_pipeline_refs()
    print("Done. Review scripts in:", OUT_DIR)


if __name__ == "__main__":
    main()
