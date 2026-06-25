-- Source: SupplyChain_Warehouse.meta.vw_run_history_tz
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[vw_run_history_tz] (
    [run_id] varchar(36) NOT NULL,
    [pipeline_run_id] varchar(36) NULL,
    [sp_name] varchar(200) NOT NULL,
    [status] varchar(20) NOT NULL,
    [rows_affected] bigint NULL,
    [load_type] varchar(20) NULL,
    [duration_seconds] int NULL,
    [error_message] varchar(4000) NULL,
    [start_utc] datetime2(6) NOT NULL,
    [end_utc] datetime2(6) NULL,
    [start_cst] datetime2(6) NULL,
    [end_cst] datetime2(6) NULL,
    [start_vn] datetime2(6) NULL,
    [end_vn] datetime2(6) NULL
);
