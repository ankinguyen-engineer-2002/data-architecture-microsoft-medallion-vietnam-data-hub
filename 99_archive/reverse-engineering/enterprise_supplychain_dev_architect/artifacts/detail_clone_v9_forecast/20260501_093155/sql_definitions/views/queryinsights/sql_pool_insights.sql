-- Source: SupplyChain_Warehouse.queryinsights.sql_pool_insights
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE VIEW queryinsights.sql_pool_insights AS SELECT sql_pool_name, metric_timestamp AS timestamp, max_resource_percentage, is_optimized_for_reads, current_workspace_capacity, is_pool_under_pressure from queryinsights.fabric_workloadinsights AS t1 WHERE t1.TIMESTAMP > DATEADD(DAY, -30, GETDATE())