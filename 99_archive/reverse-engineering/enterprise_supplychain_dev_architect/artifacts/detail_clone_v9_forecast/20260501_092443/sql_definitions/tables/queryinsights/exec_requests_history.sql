-- Source: SupplyChain_Warehouse.queryinsights.exec_requests_history
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [queryinsights].[exec_requests_history] (
    [distributed_statement_id] uniqueidentifier NULL,
    [database_name] varchar(200) NULL,
    [submit_time] datetime2(6) NULL,
    [start_time] datetime2(6) NULL,
    [end_time] datetime2(6) NULL,
    [is_distributed] int NOT NULL,
    [statement_type] varchar(128) NULL,
    [total_elapsed_time_ms] bigint NULL,
    [login_name] varchar(200) NULL,
    [row_count] bigint NULL,
    [status] varchar(200) NULL,
    [session_id] int NULL,
    [connection_id] uniqueidentifier NULL,
    [program_name] varchar(128) NULL,
    [batch_id] uniqueidentifier NULL,
    [root_batch_id] uniqueidentifier NULL,
    [query_hash] varchar(200) NULL,
    [label] varchar(8000) NULL,
    [result_cache_hit] int NULL,
    [sql_pool_name] varchar(128) NULL,
    [error_code] int NULL,
    [error_severity] int NULL,
    [error_state] int NULL,
    [allocated_cpu_time_ms] bigint NULL,
    [data_scanned_remote_storage_mb] decimal(18,3) NULL,
    [data_scanned_memory_mb] decimal(18,3) NULL,
    [data_scanned_disk_mb] decimal(18,3) NULL,
    [command] varchar(max) NULL
);
