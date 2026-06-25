-- Source: SupplyChain_Warehouse.meta.sp_run_history
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[sp_run_history] (
    [run_id] varchar(36) NOT NULL,
    [pipeline_run_id] varchar(36) NULL,
    [sp_name] varchar(200) NOT NULL,
    [start_time] datetime2(6) NOT NULL,
    [end_time] datetime2(6) NULL,
    [duration_seconds] int NULL,
    [rows_affected] bigint NULL,
    [status] varchar(20) NOT NULL,
    [error_message] varchar(4000) NULL,
    [load_type] varchar(20) NULL,
    [start_cst] datetime2(6) NULL,
    [end_cst] datetime2(6) NULL
);
