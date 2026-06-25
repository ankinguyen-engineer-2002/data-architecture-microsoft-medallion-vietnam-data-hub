-- Source: SupplyChain_Warehouse.dbo.usp_Load_Dim_Forecast_Horizon
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE         PROCEDURE dbo.usp_Load_Dim_Forecast_Horizon
AS
BEGIN
    /* 1. Xóa bảng cũ nếu đã tồn tại trong dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.dim_forecast_horizon') AND type = 'U')
        DROP TABLE dbo.dim_forecast_horizon;

    /* 2. Dùng CTAS kéo data trực tiếp từ Bronze Lakehouse sang Calendar Dim */
    /* Thực hiện Rename cột để xóa dấu cách và ký tự đặc biệt */
    CREATE TABLE dbo.dim_forecast_horizon
    AS
    SELECT *
    FROM [SupplyChain_Lakehouse].[dbo].[ref_forecast_horizon]


    PRINT 'Successfully loaded dbo.ref_forecast_horizon directly from Bronze layer with cleaned schema';
END
