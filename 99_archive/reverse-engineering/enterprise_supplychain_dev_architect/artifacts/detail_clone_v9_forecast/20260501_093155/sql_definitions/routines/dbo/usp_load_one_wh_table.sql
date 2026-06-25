-- Source: SupplyChain_Warehouse.dbo.usp_load_one_wh_table
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE PROCEDURE dbo.usp_load_one_wh_table
    @table_name VARCHAR(200)
AS
BEGIN
    -- ============================================================
    -- SP: Load 1 bảng từ Lakehouse → Warehouse
    -- Pattern: metadata-driven, table-agnostic, parallel-safe
    -- Author: Aric Nguyen
    -- ============================================================
    DECLARE @tgt_schema  VARCHAR(50),
            @tgt_table   VARCHAR(200),
            @found       INT,
            @sql         VARCHAR(8000);

    -- Step 1: Đọc metadata từ Lakehouse qua 3-part name
    SELECT 
        @tgt_schema = ISNULL(wh_target_schema, 'dbo'),
        @tgt_table  = ISNULL(wh_target_table, table_name),
        @found      = 1
    FROM [SupplyChain_Lakehouse].[dbo].[utl_pipeline_metadata]
    WHERE table_name = @table_name
      AND load_to_wh = 1
      AND is_active  = 1;

    -- Step 2: Guard clause — không match thì skip lặng lẽ
    IF @found IS NULL
    BEGIN
        PRINT 'SKIP: ' + @table_name + ' (not flagged or inactive)';
        RETURN;
    END

    -- Step 3: DROP target nếu tồn tại (overwrite mode)
    SET @sql = 'DROP TABLE IF EXISTS [' + @tgt_schema + '].[' + @tgt_table + ']';
    PRINT 'EXEC: ' + @sql;
    EXEC(@sql);

    -- Step 4: CTAS từ Lakehouse
    SET @sql = 'CREATE TABLE [' + @tgt_schema + '].[' + @tgt_table + '] AS ' +
               'SELECT * FROM [SupplyChain_Lakehouse].[dbo].[' + @table_name + ']';
    PRINT 'EXEC: ' + @sql;
    EXEC(@sql);

    -- Step 5: Báo thành công
    PRINT 'SUCCESS: ' + @table_name + ' -> [' + @tgt_schema + '].[' + @tgt_table + ']';
END