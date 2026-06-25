-- Source: SupplyChain_Warehouse.SCP_Core.DimVendorMaster
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[DimVendorMaster] (
    [VendorNumber] varchar(8000) NOT NULL,
    [VendorName] varchar(8000) NULL,
    [Office] varchar(8000) NULL,
    [VendorOfficeLocation] varchar(8000) NULL,
    [VendorDesc] varchar(8000) NULL,
    [Country] varchar(8000) NULL,
    [LeadTime] int NULL,
    [VendorActive] varchar(8000) NULL,
    [Vendor Import Domestic Flag] varchar(8000) NULL
);
