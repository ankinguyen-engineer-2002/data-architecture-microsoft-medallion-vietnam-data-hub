-- Source: SupplyChain_Warehouse.meta.dq_rules
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[dq_rules] (
    [rule_id] int NOT NULL,
    [rule_name] varchar(200) NOT NULL,
    [target_schema] varchar(50) NOT NULL,
    [target_table] varchar(200) NOT NULL,
    [check_type] varchar(30) NOT NULL,
    [column_name] varchar(100) NULL,
    [severity] varchar(10) NOT NULL,
    [threshold] decimal(18,2) NULL,
    [params] varchar(1000) NULL,
    [is_active] int NOT NULL,
    [layer] varchar(10) NOT NULL
);
