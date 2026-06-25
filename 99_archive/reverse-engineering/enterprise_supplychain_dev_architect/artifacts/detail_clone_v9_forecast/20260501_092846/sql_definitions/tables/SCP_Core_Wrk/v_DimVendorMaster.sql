-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimVendorMaster
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core_Wrk].[v_DimVendorMaster] (
    [VendorNumber] varchar(8000) NULL,
    [VendorName] varchar(8000) NULL,
    [Office] varchar(8000) NULL,
    [VendorOfficeLocation] varchar(12) NOT NULL,
    [VendorDesc] varchar(8000) NOT NULL,
    [Country] varchar(8000) NULL,
    [LeadTime] decimal(5,0) NULL,
    [VendorActive] varchar(3) NOT NULL,
    [Vendor Import Domestic Flag] varchar(8) NOT NULL
);
