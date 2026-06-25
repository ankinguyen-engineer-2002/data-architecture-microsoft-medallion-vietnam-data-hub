-- Source: SupplyChain_Warehouse.sys.sys_dw_schemas
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW sys.sys_dw_schemas
AS
SELECT s.*, i.* 
FROM sys.schemas s
OUTER APPLY OpenRowSet(TABLE DW_SCHEMAS, s.schema_id) i
