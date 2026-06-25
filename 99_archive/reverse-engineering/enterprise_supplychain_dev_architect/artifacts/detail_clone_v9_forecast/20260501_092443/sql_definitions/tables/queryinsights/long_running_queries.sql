-- Source: SupplyChain_Warehouse.queryinsights.long_running_queries
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [queryinsights].[long_running_queries] (
    [database_name] varchar(200) NULL,
    [median_total_elapsed_time_ms] float NULL,
    [last_run_total_elapsed_time_ms] bigint NULL,
    [last_run_start_time] datetime2(6) NULL,
    [last_dist_statement_id] uniqueidentifier NULL,
    [last_run_session_id] int NULL,
    [number_of_runs] int NULL,
    [query_hash] varchar(200) NULL,
    [last_run_command] varchar(max) NULL
);
