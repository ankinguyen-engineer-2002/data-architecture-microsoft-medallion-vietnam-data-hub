-- ---- InventoryHealth_DW.v_DimVendor ----
CREATE VIEW InventoryHealth_DW.v_DimVendor AS
SELECT
    CAST(v.VendorNumber  AS VARCHAR(50))   AS VendorNumber,
    CAST(v.VendorName    AS VARCHAR(200))  AS VendorName
FROM [SupplyChain_Processing_Warehouse].[ReferenceMaster_Enh].[Vendor] v
WHERE v.VendorNumber IS NOT NULL

GO
