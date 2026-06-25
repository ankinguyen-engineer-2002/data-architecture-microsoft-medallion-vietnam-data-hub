-- Source: SupplyChain_Warehouse.SCP_Core.DimFcstConsensusCycleDates
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[DimFcstConsensusCycleDates] (
    [CycleName] varchar(8000) NULL,
    [CycleDescription] varchar(8000) NULL,
    [CycleMonthLastDate] date NULL,
    [FcstSnapshot] date NULL,
    [ExceptionNote] varchar(8000) NULL,
    [Modified] datetime2(6) NULL,
    [Created] datetime2(6) NULL
);
