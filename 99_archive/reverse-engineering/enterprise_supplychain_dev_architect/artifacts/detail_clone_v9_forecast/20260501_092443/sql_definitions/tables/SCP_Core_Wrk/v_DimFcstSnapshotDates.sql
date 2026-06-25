-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimFcstSnapshotDates
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_DimFcstSnapshotDates] (
    [FcstCycle] varchar(8000) NULL,
    [FcstPeriod] varchar(5) NOT NULL,
    [FcstSnapshotDate] date NULL,
    [ActualsMonthEnd] date NULL,
    [ActualsFiscalPeriod] int NULL,
    [SortFcstPeriod] varchar(1) NOT NULL
);
