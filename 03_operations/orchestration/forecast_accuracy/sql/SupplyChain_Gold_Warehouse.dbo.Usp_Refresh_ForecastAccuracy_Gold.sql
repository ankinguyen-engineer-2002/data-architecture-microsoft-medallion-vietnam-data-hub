-- Target database: SupplyChain_Gold_Warehouse
-- Mart: forecast_accuracy
-- Wave order: W01 Shared dims → W10 Forecast dims → W30 Forecast facts
-- Topological: catalog wave = floor, dependencies push upward.
CREATE OR ALTER PROCEDURE [dbo].[Usp_Refresh_ForecastAccuracy_Gold]
AS
BEGIN
    SET NOCOUNT ON;

    -- Gold Wave 01: shared dimensions (depend on Gold W01 source tables)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimCalendar';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimProduct';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'Shared_DW', 'DimWarehouse';

    -- Gold Wave 10: Forecast accuracy dimensions
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'DimCustomerGrouping';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'DimForecastHorizon';

    -- Gold Wave 30: Forecast accuracy facts
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastActual';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastKpi';
END;
