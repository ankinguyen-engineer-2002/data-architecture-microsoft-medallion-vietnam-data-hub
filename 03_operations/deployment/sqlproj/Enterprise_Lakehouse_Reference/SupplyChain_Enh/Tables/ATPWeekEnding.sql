-- Generated from live Fabric metadata: Enterprise_Lakehouse
CREATE TABLE [SupplyChain_Enh].[ATPWeekEnding] (
    [ItemSKU] varchar(8000) NULL,
    [Warehouse] varchar(8000) NULL,
    [SeriesNumber] varchar(8000) NULL,
    [AFIFinanceDivision] varchar(8000) NULL,
    [AFISalesDivision] varchar(8000) NULL,
    [ItemGrouping] varchar(8000) NULL,
    [ATPWeek] varchar(8000) NULL,
    [WeekEnding] date NULL,
    [ATPQty] decimal(18,0) NULL,
    [RunDate] date NULL,
    [InsertedDate] datetime2(6) NULL,
    [InsertedVersion] int NULL,
    [VersionDescription] varchar(8000) NULL,
    [APNQ] decimal(18,0) NULL
);
