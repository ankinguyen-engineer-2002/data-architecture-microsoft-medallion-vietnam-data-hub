-- Target database: SupplyChain_Gold_Warehouse
-- Mart: inventory_health
-- Wave order: W01 Shared dims → W10 Inv dims → W20 Helpers → W21 Dependent helper → W30 Facts
-- Topological fix: InventoryClassificationQtyWeekly depends on
-- InventoryHealthSubStatusWeekly (W20), so it must be W21, not same wave.
CREATE OR ALTER PROCEDURE [dbo].[Usp_Refresh_InventoryHealth_Gold]
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

    -- Gold Wave 10: Inventory dimensions
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'DimVendor';

    -- Gold Wave 20: Inventory helper/status tables
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'ProjectedInventoryHealthSubStatus';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryHealthSubStatusWeekly';

    -- Gold Wave 21: dependent helper (depends on InventoryHealthSubStatusWeekly W20)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryClassificationQtyWeekly';

    -- Gold Wave 30: Inventory facts
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'FactInventoryHealthFutureWeekEnding';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'FactInventoryHealthSnapshot';
END;
