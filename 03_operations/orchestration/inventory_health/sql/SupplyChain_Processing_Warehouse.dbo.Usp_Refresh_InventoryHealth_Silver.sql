-- Target database: SupplyChain_Processing_Warehouse
-- Mart: inventory_health
-- Wave order: W00 ReferenceMaster + seeds → W01 Derived sources → W02 Dependent helpers
-- Topological fix: AwdHelper/Cogs52WWeekly/LastInvoiceWeekly depend on
-- InvoiceDetailLineLevel (W01), so they must be W02, not same wave.
CREATE OR ALTER PROCEDURE [dbo].[Usp_Refresh_InventoryHealth_Silver]
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

    -- Silver Wave 00: source snapshots with no Silver dependencies
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'InventorySnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AtpWeekEnding';

    -- Silver Wave 01: derived source tables (depend on W00 ReferenceMaster + seeds)
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'PurchaseOrderSnapshotHistorical';

    EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ManufacturingOrderSnapshotDaily', 'NULL';

    EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'HoldingTransferSnapshotDaily', 'NULL';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ForecastSnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'SupplyPlanDetail';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ItemBalanceHistorical_WithInTransit';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'SafetyStockHelper';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'InvoiceDetailLineLevel';

    -- Silver Wave 02: dependent helpers (depend on W01 tables above)
    -- AFIStatusSnapshotWeekly depends on ItemMaster + ItemBalanceHistorical_WithInTransit (W01).
    -- AwdHelper, Cogs52WWeekly, LastInvoiceWeekly depend on InvoiceDetailLineLevel (W01).
    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AFIStatusSnapshotWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'AwdHelper';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'LastInvoiceWeekly';

    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]
        'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'Cogs52WWeekly';
END;
