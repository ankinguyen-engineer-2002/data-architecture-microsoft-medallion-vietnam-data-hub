-- Source: SupplyChain_Warehouse.meta.schema_contracts
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [meta].[schema_contracts] (
    [contract_id] int NULL,
    [target_table] varchar(200) NULL,
    [source_object] varchar(500) NULL,
    [column_name] varchar(200) NULL,
    [expected_data_type] varchar(50) NULL,
    [is_nullable] int NULL,
    [is_active] int NULL,
    [created_date] datetime2(6) NULL,
    [last_validated] datetime2(6) NULL,
    [validation_status] varchar(20) NULL
);
