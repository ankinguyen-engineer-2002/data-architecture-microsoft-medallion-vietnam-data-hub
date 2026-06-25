-- Source: SupplyChain_Warehouse.meta.sp_registry
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[sp_registry] (
    [sp_name] varchar(200) NOT NULL,
    [view_name] varchar(200) NULL,
    [target_schema] varchar(50) NOT NULL,
    [target_table] varchar(200) NOT NULL,
    [layer] varchar(10) NOT NULL,
    [load_type] varchar(20) NOT NULL,
    [frequency] varchar(20) NOT NULL,
    [scheduled_hour] int NULL,
    [execution_order] int NOT NULL,
    [parallel_group] int NULL,
    [depends_on] varchar(500) NULL,
    [source_objects] varchar(2000) NULL,
    [watermark_column] varchar(100) NULL,
    [primary_key] varchar(500) NULL,
    [is_active] int NOT NULL,
    [last_load_date] datetime2(6) NULL,
    [last_watermark_value] varchar(200) NULL,
    [next_run_time] datetime2(6) NULL,
    [rows_loaded] bigint NULL,
    [project] varchar(50) NULL,
    [date_key] varchar(100) NULL,
    [date_range_days] int NULL,
    [cron_expression] varchar(100) NULL
);
