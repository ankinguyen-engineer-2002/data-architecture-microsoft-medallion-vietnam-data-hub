-- Target database: SupplyChain_Processing_Warehouse
-- Mart: forecast_accuracy
-- This mart wrapper is self-contained for ad-hoc execution.
CREATE OR ALTER PROCEDURE [dbo].[Usp_Refresh_ForecastAccuracy_Silver]
AS
BEGIN
    SET NOCOUNT ON;

    -- Silver Wave 00: shared ReferenceMaster prerequisites
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

    -- Wave 1: line-level Silver
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'InvoiceDetailLineLevel';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'OpenOrderHistory_Enh', 'OpenOrderLineLevel';

    -- Wave 2: aggregate Silver
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'ActualDemandMonthly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'ForecastHistory_Enh', 'ForecastDemandMonthly';
END;
