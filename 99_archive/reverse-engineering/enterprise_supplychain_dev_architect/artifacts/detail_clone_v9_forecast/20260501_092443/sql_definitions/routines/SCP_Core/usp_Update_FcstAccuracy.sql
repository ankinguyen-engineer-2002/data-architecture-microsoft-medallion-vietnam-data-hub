-- Source: SupplyChain_Warehouse.SCP_Core.usp_Update_FcstAccuracy
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE   PROCEDURE [SCP_Core].[usp_Update_FcstAccuracy]
AS

BEGIN 

EXEC [ETL_Framework].[DW_Developer].[usp_IncrementalTableLoad] 'SupplyChain_Warehouse', 'SCP_Core', 'FactFcstErrorCalc', 'Append'

END;