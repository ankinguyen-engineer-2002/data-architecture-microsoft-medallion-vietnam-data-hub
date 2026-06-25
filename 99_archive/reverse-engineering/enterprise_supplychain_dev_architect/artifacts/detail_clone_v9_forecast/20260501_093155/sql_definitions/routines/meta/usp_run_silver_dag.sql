-- Source: SupplyChain_Warehouse.meta.usp_run_silver_dag
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.


CREATE   PROCEDURE meta.usp_run_silver_dag AS
BEGIN
    -- Step 1: Compute waves
    EXEC meta.usp_compute_slv_waves;

    -- Step 2: Get max wave (use sp_executesql to avoid variable in distributed query)
    DECLARE @max_wave INT;
    EXEC sp_executesql N'SELECT @mw = ISNULL(MAX(wave), -1) FROM meta.slv_dag_waves_runtime',
         N'@mw INT OUTPUT', @mw = @max_wave OUTPUT;

    IF @max_wave < 0
    BEGIN
        PRINT 'No SLV SPs to run';
        RETURN;
    END

    -- Step 3: Loop through waves
    DECLARE @current_wave INT = 0;
    DECLARE @sp_name NVARCHAR(200);
    DECLARE @exec_sql NVARCHAR(500);
    DECLARE @find_sql NVARCHAR(500);

    WHILE @current_wave <= @max_wave
    BEGIN
        -- Find first SP in this wave using sp_executesql (parameterized)
        SET @sp_name = NULL;
        SET @find_sql = N'SELECT @out = MIN(sp_name) FROM meta.slv_dag_waves_runtime WHERE wave = @w';
        EXEC sp_executesql @find_sql, N'@w INT, @out NVARCHAR(200) OUTPUT', 
             @w = @current_wave, @out = @sp_name OUTPUT;

        WHILE @sp_name IS NOT NULL
        BEGIN
            -- Execute the SP
            SET @exec_sql = N'EXEC ' + @sp_name;
            EXEC sp_executesql @exec_sql;

            -- Find next SP in same wave
            SET @find_sql = N'SELECT @out = MIN(sp_name) FROM meta.slv_dag_waves_runtime WHERE wave = @w AND sp_name > @prev';
            EXEC sp_executesql @find_sql, N'@w INT, @prev NVARCHAR(200), @out NVARCHAR(200) OUTPUT',
                 @w = @current_wave, @prev = @sp_name, @out = @sp_name OUTPUT;
        END

        SET @current_wave = @current_wave + 1;
    END
END
