-- Source: SupplyChain_Warehouse.dbo.dq_forecast_accuracy
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [dbo].[dq_forecast_accuracy] (
    [check_id] varchar(5) NOT NULL,
    [check_name] varchar(60) NOT NULL,
    [is_pass] int NOT NULL
);
