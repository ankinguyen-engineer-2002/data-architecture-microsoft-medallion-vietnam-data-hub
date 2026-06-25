-- Source: SupplyChain_Warehouse.meta.usp_compute_slv_waves
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE PROCEDURE meta.usp_compute_slv_waves AS
BEGIN
    DELETE FROM meta.slv_dag_waves_runtime;

    DECLARE @wave INT = 0;
    DECLARE @assigned INT = 0;
    DECLARE @new_count INT = 1;
    DECLARE @total INT;
    DECLARE @max_waves INT = 30;

    SELECT @total = COUNT(*) FROM meta.sp_registry WHERE layer = 'SLV' AND is_active = 1;

    -- Wave 0: SPs with no silver dependencies
    -- Check for ANY silver dependency pattern (covers both old and new naming)
    INSERT INTO meta.slv_dag_waves_runtime (sp_name, wave)
    SELECT sp_name, 0
    FROM meta.sp_registry
    WHERE layer = 'SLV' AND is_active = 1
    AND (depends_on IS NULL OR (depends_on NOT LIKE '%silver.slv_%' AND depends_on NOT LIKE '%silver.usp_%'));

    SELECT @assigned = COUNT(*) FROM meta.slv_dag_waves_runtime;
    SET @wave = 1;

    -- Iteratively: assign SPs whose ALL silver deps are in STRICTLY PREVIOUS waves
    WHILE @assigned < @total AND @wave < @max_waves AND @new_count > 0
    BEGIN
        INSERT INTO meta.slv_dag_waves_runtime (sp_name, wave)
        SELECT r.sp_name, @wave
        FROM meta.sp_registry r
        WHERE r.layer = 'SLV' AND r.is_active = 1
        AND r.sp_name NOT IN (SELECT sp_name FROM meta.slv_dag_waves_runtime)
        AND NOT EXISTS (
            SELECT 1 FROM meta.sp_registry dep
            WHERE dep.layer = 'SLV' AND dep.is_active = 1
            AND r.depends_on LIKE '%' + dep.sp_name + '%'
            AND dep.sp_name NOT IN (
                SELECT sp_name FROM meta.slv_dag_waves_runtime
                WHERE wave < @wave
            )
        );

        SET @new_count = @@ROWCOUNT;
        SET @assigned = @assigned + @new_count;
        SET @wave = @wave + 1;
    END
END
