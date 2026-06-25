-- Source: SupplyChain_Warehouse.meta.pipeline_run_log
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[pipeline_run_log] (
    [pipeline_run_id] varchar(36) NOT NULL,
    [pipeline_name] varchar(100) NOT NULL,
    [status] varchar(20) NOT NULL,
    [start_time] datetime2(6) NOT NULL,
    [end_time] datetime2(6) NULL,
    [tables_succeeded] int NULL,
    [tables_failed] int NULL,
    [dq_failures_critical] int NULL,
    [notes] varchar(2000) NULL,
    [start_cst] datetime2(6) NULL,
    [end_cst] datetime2(6) NULL
);
