-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactFcstErrorCalc
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_FactFcstErrorCalc] (
    [CustomerGroup] varchar(8000) NULL,
    [ItemSKU] varchar(8000) NOT NULL,
    [Warehouse] varchar(8000) NOT NULL,
    [FiscalMonthYear] decimal(6,0) NOT NULL,
    [FiscalMonthEnd] date NULL,
    [SortFcstPeriod] int NULL,
    [FcstPeriod] varchar(5) NOT NULL,
    [TotalForecast] decimal(38,0) NULL,
    [ActualDemand] decimal(38,0) NOT NULL,
    [FcstError] decimal(38,0) NULL,
    [ABS_FcstError] decimal(38,0) NULL,
    [SqFcstError] float NULL,
    [NaiveFcst] int NOT NULL,
    [NaiveFcstError] decimal(38,0) NULL,
    [ABS_NaiveFcstError] decimal(38,0) NULL,
    [SqNaiveFcstError] float NULL,
    [SnapshotDate] date NULL,
    [FcstCycle] varchar(7) NOT NULL
);
