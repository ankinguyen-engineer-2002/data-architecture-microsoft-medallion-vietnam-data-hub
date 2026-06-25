-- Source: SupplyChain_Warehouse.SCP_Core.DimFcstSnapshotDates
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[DimFcstSnapshotDates] (
    [FcstCycle] varchar(7) NOT NULL,
    [FcstPeriod] varchar(5) NOT NULL,
    [FcstSnapshotDate] date NULL,
    [ActualsMonthEnd] date NULL,
    [ActualsFiscalPeriod] int NULL,
    [SortFcstPeriod] int NULL
);
