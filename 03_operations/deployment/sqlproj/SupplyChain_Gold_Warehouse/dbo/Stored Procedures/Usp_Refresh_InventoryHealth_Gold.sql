-- Target database: SupplyChain_Gold_Warehouse
-- Mart: inventory_health
-- This mart wrapper is self-contained after Inventory Health Silver.
CREATE PROCEDURE [dbo].[Usp_Refresh_InventoryHealth_Gold]
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

    -- Gold Wave 10: Inventory dimensions
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'DimVendor';

    -- Gold Wave 20: Inventory helper/status tables
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'ProjectedInventoryHealthSubStatus';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryHealthSubStatusWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'InventoryClassificationQtyWeekly';

    -- Gold Wave 30: Inventory facts
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'FactInventoryHealthFutureWeekEnding';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Gold_Warehouse', 'InventoryHealth_DW', 'FactInventoryHealthSnapshot';
END;
