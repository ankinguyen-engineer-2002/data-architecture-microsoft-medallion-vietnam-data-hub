-- ReferenceMaster_Enh_Wrk.v_Vendor
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_Vendor] AS
WITH __bob_source AS (
SELECT
    CAST(TRIM(v.VendorNumber) AS VARCHAR(50))           AS VendorNumber,
    CAST(v.VendorName         AS VARCHAR(200))          AS VendorName,
    CAST('Purchasing_AFI'     AS VARCHAR(64))           AS SourceSystem,
    CAST('VendorMaster'       AS VARCHAR(128))          AS SourceTable
FROM [Enterprise_Lakehouse].[Purchasing_AFI].[VendorMaster] v
WHERE v.VendorNumber IS NOT NULL AND TRIM(v.VendorNumber) <> ''
)
SELECT
    [VendorNumber] = src.[VendorNumber],
    [VendorName] = src.[VendorName],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
