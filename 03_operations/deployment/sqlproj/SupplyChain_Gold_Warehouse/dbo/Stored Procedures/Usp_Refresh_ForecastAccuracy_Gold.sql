-- Target database: SupplyChain_Gold_Warehouse
-- Mart: forecast_accuracy
-- This mart wrapper is self-contained after Forecast Accuracy Silver.
CREATE PROCEDURE [dbo].[Usp_Refresh_ForecastAccuracy_Gold]
AS
BEGIN
    SET NOCOUNT ON;

    -- Gold Wave 00: shared dimensions
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimCalendar';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimProduct';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimWarehouse';

    -- Gold Wave 10: Forecast dimensions
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'DimCustomerGrouping';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'DimForecastHorizon';

    -- Gold Wave 20: Forecast facts
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastActual';

    -- FactForecastKpi derives QtyActual from mutable ActualDemandMonthly.  Its
    -- target grain is not restated when a forecast Snapshot ages out, so a
    -- Snapshot-based DateRange load freezes Actual/error vintages.  Rebuild
    -- this fact from the current view; do not change the generic DateRange
    -- loader because other snapshot facts have a valid immutable contract.
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastKpi';
END;
