-- Source: SupplyChain_Warehouse.queryinsights.sql_pool_insights
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [queryinsights].[sql_pool_insights] (
    [sql_pool_name] varchar(128) NULL,
    [timestamp] datetime2(6) NULL,
    [max_resource_percentage] int NULL,
    [is_optimized_for_reads] bit NULL,
    [current_workspace_capacity] varchar(16) NULL,
    [is_pool_under_pressure] bit NULL
);
