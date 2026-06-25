-- Source: SupplyChain_Warehouse.SCP_Core.usp_Update_Dimensions
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE       PROCEDURE [SCP_Core].[usp_Update_Dimensions]
AS

BEGIN 


EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimFiscalCalendar'
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimSCPItemMaster'
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimVendorMaster'
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimWarehouseMaster'
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimCustomerMaster'
EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView] 'SupplyChain_Warehouse', 'SCP_Core', 'DimFcstSnapshotDates'


END;