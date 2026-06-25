-- Source: SupplyChain_Warehouse.meta.ufn_should_run
-- Object type: SQL_SCALAR_FUNCTION
-- Exported read-only from sys.sql_modules.


CREATE FUNCTION meta.ufn_should_run(@sp_name VARCHAR(200))
RETURNS INT
AS
BEGIN
    DECLARE @result INT = 0;
    SELECT @result = CASE
        WHEN is_active = 0 THEN 0
        WHEN next_run_time IS NULL THEN 1
        WHEN next_run_time <= GETUTCDATE() THEN 1
        ELSE 0
    END
    FROM meta.sp_registry WHERE sp_name = @sp_name;
    RETURN ISNULL(@result, 0);
END
