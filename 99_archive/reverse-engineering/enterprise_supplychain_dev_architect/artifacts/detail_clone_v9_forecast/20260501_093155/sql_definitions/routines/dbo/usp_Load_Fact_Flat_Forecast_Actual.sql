-- Source: SupplyChain_Warehouse.dbo.usp_Load_Fact_Flat_Forecast_Actual
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE       PROCEDURE dbo.usp_Load_Fact_Flat_Forecast_Actual
AS
BEGIN
    /* 1. Xóa bảng cũ nếu đã tồn tại trong schema dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fact_flat_forecast_actual') AND type = 'U')
        DROP TABLE dbo.fact_flat_forecast_actual;

    /* 2. Dùng CTAS kéo data trực tiếp từ Lakehouse Gold sang Warehouse Fact */
    -- Thay [SupplyChain_Lakehouse] bằng tên chính xác của Lakehouse của Bro
    CREATE TABLE dbo.fact_flat_forecast_actual
    AS
    SELECT * FROM [SupplyChain_Lakehouse].[dbo].[gld_flat_forecast_actual];

    PRINT 'Successfully loaded dbo.fact_flat_forecast_actual';
END
