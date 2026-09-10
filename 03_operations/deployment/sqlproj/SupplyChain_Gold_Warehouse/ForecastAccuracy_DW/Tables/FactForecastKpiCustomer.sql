-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [ForecastAccuracy_DW].[FactForecastKpiCustomer] (
    [CustomerGroupCode] varchar(20) NULL,
    [ItemSKU] varchar(20) NULL,
    [WarehouseCode] varchar(10) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [HorizonCode] varchar(20) NULL,
    [Snapshot] date NULL,
    [QtyForecast] int NULL,
    [QtyActual] int NULL,
    [QtyNaiveForecast] int NULL,
    [QtyFcstError] int NULL,
    [QtyAbsFcstError] int NULL,
    [QtyNaiveFcstError] int NULL,
    [QtyAbsNaiveFcstError] int NULL,
    [QtySquaredFcstError] int NULL,
    [QtySquaredNaiveFcstError] int NULL,
    [ValidObsFlag] int NULL,
    [ValidActualNonzeroFlag] int NULL,
    [AbsPctError] decimal(10,4) NULL,
    [LoadDT] datetime2(6) NULL
);
