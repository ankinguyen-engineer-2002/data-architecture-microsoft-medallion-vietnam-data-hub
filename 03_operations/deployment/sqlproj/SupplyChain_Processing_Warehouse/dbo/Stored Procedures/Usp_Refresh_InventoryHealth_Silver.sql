-- Target database: SupplyChain_Processing_Warehouse
-- Mart: inventory_health
-- This mart wrapper is self-contained for ad-hoc execution.
CREATE PROCEDURE [dbo].[Usp_Refresh_InventoryHealth_Silver]
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

    -- Wave 0: source snapshots and direct Silver foundations
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'PurchaseOrderSnapshotHistorical';

    EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ManufacturingOrderSnapshotDaily', 'NULL';

    EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'HoldingTransferSnapshotDaily', 'NULL';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'InventorySnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ForecastSnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'SupplyPlanDetail';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AtpWeekEnding';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ItemBalanceHistorical_WithInTransit';

    -- Wave 1: derived Silver helpers
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'InvoiceDetailLineLevel';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AFIStatusSnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AwdHelper';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'SafetyStockHelper';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'LastInvoiceWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'Cogs52WWeekly';
END;
