-- Source: SupplyChain_Warehouse.dbo.usp_Load_Dim_Warehouse
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE       PROCEDURE dbo.usp_Load_Dim_Warehouse
AS
BEGIN
    /* 1. Xóa bảng cũ nếu đã tồn tại trong dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.dim_warehouse') AND type = 'U')
        DROP TABLE dbo.dim_warehouse;

    /* 2. Dùng CTAS kéo data trực tiếp từ Bronze Lakehouse sang Warehouse Dim */
    /* Thực hiện Rename cột để xóa dấu cách và ký tự đặc biệt */
    CREATE TABLE dbo.dim_warehouse
    AS
    SELECT *
    FROM [SupplyChain_Lakehouse].[dbo].[ref_warehouse]


    PRINT 'Successfully loaded dbo.dim_warehouse directly from Bronze layer with cleaned schema';
END
