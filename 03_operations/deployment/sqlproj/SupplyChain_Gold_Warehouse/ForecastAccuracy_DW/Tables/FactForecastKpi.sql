-- Generated from live Fabric metadata: SupplyChain_Gold_Warehouse
CREATE TABLE [ForecastAccuracy_DW].[FactForecastKpi] (
    [ItemSKU] varchar(8000) NULL,
    [WarehouseCode] varchar(8000) NULL,
    [FSCMonthFirst] date NULL,
    [FSCMonthLast] date NULL,
    [HorizonCode] varchar(20) NULL,
    [Snapshot] date NULL,
    [QtyForecast] float NULL,
    [QtyActual] float NULL,
    [QtyNaiveForecast] float NULL,
    [QtyFcstError] float NULL,
    [QtyAbsFcstError] float NULL,
    [QtyNaiveFcstError] float NULL,
    [QtyAbsNaiveFcstError] float NULL,
    [QtySquaredFcstError] float NULL,
    [QtySquaredNaiveFcstError] float NULL,
    [ValidObsFlag] int NULL,
    [ValidActualNonzeroFlag] int NULL,
    [AbsPctError] float NULL,
    [LoadDT] datetime2(6) NULL
);
