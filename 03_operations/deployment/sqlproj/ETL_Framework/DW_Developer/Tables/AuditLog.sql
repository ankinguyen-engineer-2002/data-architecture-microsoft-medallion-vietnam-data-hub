-- Generated from live Fabric metadata: ETL_Framework
CREATE TABLE [DW_Developer].[AuditLog] (
    [Description] varchar(200) NULL,
    [DateTime] datetime2(6) NULL,
    [User] varchar(150) NULL,
    [Command] varchar(8000) NULL
);
