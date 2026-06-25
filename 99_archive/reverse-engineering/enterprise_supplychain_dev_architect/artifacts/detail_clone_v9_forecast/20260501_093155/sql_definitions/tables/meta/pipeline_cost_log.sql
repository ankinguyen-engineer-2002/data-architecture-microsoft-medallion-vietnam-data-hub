-- Source: SupplyChain_Warehouse.meta.pipeline_cost_log
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[pipeline_cost_log] (
    [pipeline_run_id] varchar(36) NULL,
    [pipeline_name] varchar(100) NULL,
    [start_time] datetime2(6) NULL,
    [end_time] datetime2(6) NULL,
    [total_duration_seconds] int NULL,
    [tables_processed] int NULL,
    [total_rows_affected] bigint NULL,
    [estimated_cu] decimal(10,2) NULL,
    [cost_per_table_avg] decimal(10,2) NULL,
    [log_date] datetime2(6) NULL
);
