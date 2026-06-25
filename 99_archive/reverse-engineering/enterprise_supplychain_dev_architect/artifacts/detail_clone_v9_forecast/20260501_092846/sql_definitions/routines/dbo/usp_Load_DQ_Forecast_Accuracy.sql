-- Source: SupplyChain_Warehouse.dbo.usp_Load_DQ_Forecast_Accuracy
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE         PROCEDURE dbo.usp_Load_DQ_Forecast_Accuracy
AS
BEGIN
    /* 1. Xóa bảng cũ nếu đã tồn tại trong dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.dq_forecast_accuracy') AND type = 'U')
        DROP TABLE dbo.dq_forecast_accuracy;

    /* 2. Dùng CTAS kéo data trực tiếp từ Bronze Lakehouse sang Calendar Dim */
    /* Thực hiện Rename cột để xóa dấu cách và ký tự đặc biệt */
    CREATE TABLE dbo.dq_forecast_accuracy
    AS
    SELECT *
    FROM [dbo].[vw_dq_forecast_accuracy]


    PRINT 'Successfully loaded dbo.dim_calender directly from Bronze layer with cleaned schema';
END
