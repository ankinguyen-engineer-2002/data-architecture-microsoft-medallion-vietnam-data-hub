-- Source: SupplyChain_Warehouse.dbo.usp_Load_Dim_Customer_Grouping
-- Object type: SQL_STORED_PROCEDURE
-- Exported read-only from sys.sql_modules.

CREATE           PROCEDURE dbo.usp_Load_Dim_Customer_Grouping
AS
BEGIN
    /* 1. Xóa bảng cũ nếu tồn tại trong dbo */
    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.dim_customer_grouping') AND type = 'U')
        DROP TABLE dbo.dim_customer_grouping;

    /* 2. CTAS trực tiếp từ Bronze Lakehouse sang Warehouse Dim */
    /* Giữ nguyên tên cột gốc, chỉ thực hiện TRIM */
    CREATE TABLE dbo.dim_customer_grouping
    AS
    SELECT *
    FROM [SupplyChain_Lakehouse].[dbo].[ref_customer_grouping]
    

    PRINT 'Successfully loaded dbo.dim_customer_grouping with original column names';
END
