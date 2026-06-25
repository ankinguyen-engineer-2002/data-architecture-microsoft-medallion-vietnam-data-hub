-- Source: SupplyChain_Warehouse.dbo.usp_Load_Dim_Product
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE       PROCEDURE dbo.usp_Load_Dim_Product
AS
BEGIN
    /* 1. Xóa bảng cũ nếu tồn tại trong dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.dim_product') AND type = 'U')
        DROP TABLE dbo.dim_product;

    /* 2. Dùng CTAS kéo data từ Lakehouse Silver sang Warehouse Dim */
    -- Đảm bảo [SupplyChain_Lakehouse] khớp chính xác với tên Lakehouse của Bro
    CREATE TABLE dbo.dim_product
    AS
    SELECT * FROM [SupplyChain_Lakehouse].[dbo].[ref_product];
    
    PRINT 'Successfully loaded dbo.dim_product from Silver layer';
END
