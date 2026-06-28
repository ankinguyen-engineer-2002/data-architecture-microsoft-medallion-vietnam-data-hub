-- ReferenceMaster_Enh_Wrk.v_Vendor
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_Vendor] AS
SELECT
    CAST(TRIM(v.VendorNumber) AS VARCHAR(50))           AS VendorNumber,
    CAST(v.VendorName         AS VARCHAR(200))          AS VendorName,
    CAST('Purchasing_AFI'     AS VARCHAR(64))           AS SourceSystem,
    CAST('VendorMaster'       AS VARCHAR(128))          AS SourceTable,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
WHERE v.VendorNumber IS NOT NULL AND TRIM(v.VendorNumber) <> '';
