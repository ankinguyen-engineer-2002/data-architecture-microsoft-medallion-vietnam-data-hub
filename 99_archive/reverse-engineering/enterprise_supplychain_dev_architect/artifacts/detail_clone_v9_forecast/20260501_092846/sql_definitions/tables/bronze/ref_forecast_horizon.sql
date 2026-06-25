-- Source: SupplyChain_Warehouse.bronze.ref_forecast_horizon
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[ref_forecast_horizon] (
    [code_horizon] varchar(14) NOT NULL,
    [num_rank] int NOT NULL,
    [_load_dt] datetime2(6) NULL
);
