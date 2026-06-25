-- Source: SupplyChain_Warehouse.meta.usp_build_lineage
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE PROCEDURE meta.usp_build_lineage
AS
BEGIN
    DELETE FROM meta.sp_lineage;

    INSERT INTO meta.sp_lineage (lineage_id, source_schema, source_table, target_schema, target_table, relationship_type, sp_name)
    SELECT
        ROW_NUMBER() OVER (ORDER BY r.sp_name, src.value),
        CASE WHEN CHARINDEX('.', TRIM(src.value)) > 0 
             THEN LEFT(TRIM(src.value), CHARINDEX('.', TRIM(src.value)) - 1)
             ELSE 'unknown' END,
        CASE WHEN CHARINDEX('.', TRIM(src.value)) > 0 
             THEN SUBSTRING(TRIM(src.value), CHARINDEX('.', TRIM(src.value)) + 1, LEN(TRIM(src.value)))
             ELSE TRIM(src.value) END,
        r.target_schema,
        r.target_table,
        'direct',
        r.sp_name
    FROM meta.sp_registry r
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(r.source_objects, '[', ''), ']', ''), ',') src
    WHERE r.source_objects IS NOT NULL AND LEN(TRIM(src.value)) > 0;
END
