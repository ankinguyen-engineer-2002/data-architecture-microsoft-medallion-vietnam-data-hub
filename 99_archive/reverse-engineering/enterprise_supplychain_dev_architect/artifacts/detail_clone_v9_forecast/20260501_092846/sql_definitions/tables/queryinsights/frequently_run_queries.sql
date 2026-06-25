-- Source: SupplyChain_Warehouse.queryinsights.frequently_run_queries
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [queryinsights].[frequently_run_queries] (
    [database_name] varchar(200) NULL,
    [number_of_runs] int NULL,
    [min_run_total_elapsed_time_ms] bigint NULL,
    [max_run_total_elapsed_time_ms] bigint NULL,
    [avg_total_elapsed_time_ms] bigint NULL,
    [number_of_successful_runs] int NULL,
    [number_of_failed_runs] int NULL,
    [number_of_canceled_runs] int NULL,
    [last_run_total_elapsed_time_ms] bigint NULL,
    [last_run_start_time] datetime2(6) NULL,
    [last_dist_statement_id] uniqueidentifier NULL,
    [query_hash] varchar(200) NULL,
    [last_run_command] varchar(max) NULL
);
