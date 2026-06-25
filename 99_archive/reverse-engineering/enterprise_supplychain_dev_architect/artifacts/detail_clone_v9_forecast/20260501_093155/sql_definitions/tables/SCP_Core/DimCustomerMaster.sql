-- Source: SupplyChain_Warehouse.SCP_Core.DimCustomerMaster
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [SCP_Core].[DimCustomerMaster] (
    [Account Number] varchar(8000) NOT NULL,
    [ShipTo Number] varchar(8000) NULL,
    [Customer Name] varchar(8000) NULL,
    [ShipTo Name] varchar(8000) NULL,
    [Account And ShipTo Number] varchar(8000) NOT NULL,
    [Commission Code] varchar(8000) NULL,
    [Freight Code] varchar(8000) NULL,
    [Price Code] varchar(8000) NULL,
    [Default Warehouse] varchar(8000) NULL,
    [ShipTo City] varchar(8000) NULL,
    [ShipTo State] varchar(8000) NULL,
    [ShipTo Country] varchar(8000) NULL,
    [Business Type Code] varchar(8000) NULL,
    [Business Type] varchar(8000) NULL,
    [Reporting Business Type] varchar(8000) NULL,
    [Customer Group] varchar(8000) NULL,
    [Account Group] varchar(8000) NULL
);
