-- Target database: SupplyChain_Processing_Warehouse
-- Mart: forecast_accuracy
-- Wave order: W00 ReferenceMaster → W01 Line-level → W02 Aggregate → W03 Derived
-- Topological: catalog wave = floor, dependencies push upward.
CREATE OR ALTER PROCEDURE [dbo].[Usp_Refresh_ForecastAccuracy_Silver]
AS
BEGIN
    SET NOCOUNT ON;

    -- Silver Wave 00: shared ReferenceMaster prerequisites (no Silver deps)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'Calendar';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'CustomerAccount';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'CustomerAccountGroup';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'CustomerGrouping';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'CustomerShippingLocation';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'ForecastCycle';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'ForecastHorizon';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'ItemMaster';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'OrderType';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'Vendor';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ReferenceMaster_Enh', 'Warehouse';

    -- Silver Wave 01: line-level tables (depend on ReferenceMaster W00)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'InvoiceDetailLineLevel';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'OpenOrderHistory_Enh', 'OpenOrderLineLevel';

    -- Silver Wave 02: aggregate tables (depend on W01 line-level)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'ActualDemandMonthly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'ActualDemandWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'InvoiceWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ForecastHistory_Enh', 'ForecastDemandMonthly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'OpenOrderHistory_Enh', 'OpenOrderMonthly';

    -- Silver Wave 03: derived forecast (depends on W02 ForecastDemandMonthly)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ForecastHistory_Enh', 'NaiveForecastMonthly';
END;
