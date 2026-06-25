-- Source: SupplyChain_Warehouse.meta.performance_baseline
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[performance_baseline] (
    [sp_name] varchar(200) NULL,
    [avg_duration_seconds] int NULL,
    [max_duration_seconds] int NULL,
    [avg_rows_affected] bigint NULL,
    [sample_count] int NULL,
    [baseline_date] datetime2(6) NULL,
    [threshold_multiplier] decimal(5,2) NULL
);
