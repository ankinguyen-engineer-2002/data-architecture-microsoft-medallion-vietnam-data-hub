-- Generated from live Fabric metadata: Enterprise_Lakehouse
CREATE TABLE [SupplyChain_Enh].[PurchaseOrderSnapshot] (
    [posItNbr] varchar(8000) NOT NULL,
    [posWhse] varchar(8000) NOT NULL,
    [posQtyOr] decimal(15,3) NOT NULL,
    [posPstts] varchar(8000) NOT NULL,
    [posDueDt] decimal(7,0) NULL,
    [posSnapshot] datetime2(6) NULL,
    [posUUD1PM] decimal(7,0) NULL,
    [posVndnr] varchar(8000) NULL
);
