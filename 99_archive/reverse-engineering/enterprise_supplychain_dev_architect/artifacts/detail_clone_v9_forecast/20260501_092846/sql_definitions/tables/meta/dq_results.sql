-- Source: SupplyChain_Warehouse.meta.dq_results
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[dq_results] (
    [result_id] int NOT NULL,
    [pipeline_run_id] varchar(36) NULL,
    [rule_id] int NOT NULL,
    [check_time] datetime2(6) NOT NULL,
    [status] varchar(10) NOT NULL,
    [actual_value] varchar(500) NULL,
    [expected_value] varchar(500) NULL,
    [error_detail] varchar(4000) NULL
);
