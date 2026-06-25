-- Source: SupplyChain_Warehouse.SCP_Core.FactFcstErrorCalc
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[FactFcstErrorCalc] (
    [CustomerGroup] varchar(8000) NOT NULL,
    [ItemSKU] varchar(8000) NULL,
    [Warehouse] varchar(8000) NULL,
    [FiscalMonthYear] int NULL,
    [FiscalMonthEnd] date NOT NULL,
    [SortFcstPeriod] int NULL,
    [FcstPeriod] varchar(8000) NULL,
    [TotalForecast] int NOT NULL,
    [ActualDemand] int NOT NULL,
    [FcstError] int NOT NULL,
    [ABS_FcstError] int NOT NULL,
    [SqFcstError] int NOT NULL,
    [NaiveFcst] int NOT NULL,
    [NaiveFcstError] int NOT NULL,
    [ABS_NaiveFcstError] int NOT NULL,
    [SqNaiveFcstError] int NOT NULL,
    [SnapshotDate] date NOT NULL,
    [FcstCycle] varchar(7) NULL
);
