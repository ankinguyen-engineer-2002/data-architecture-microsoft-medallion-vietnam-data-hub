-- Source: SupplyChain_Warehouse.meta.usp_debug_loop
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_debug_loop AS
BEGIN
    DECLARE @id INT;
    DECLARE @cnt INT = 0;
    SELECT @id = MIN(rule_id) FROM meta.dq_rules WHERE layer = 'BRZ' AND is_active = 1;
    
    WHILE @id IS NOT NULL
    BEGIN
        SET @cnt = @cnt + 1;
        
        -- Get next
        SELECT @id = MIN(rule_id) FROM meta.dq_rules WHERE rule_id > @id AND layer = 'BRZ' AND is_active = 1;
    END
    
    SELECT @cnt AS total_iterations;
END
