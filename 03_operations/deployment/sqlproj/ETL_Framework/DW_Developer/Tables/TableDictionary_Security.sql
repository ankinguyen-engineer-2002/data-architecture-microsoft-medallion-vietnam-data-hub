-- Generated from live Fabric metadata: ETL_Framework
CREATE TABLE [DW_Developer].[TableDictionary_Security] (
    [UserName] varchar(100) NOT NULL,
    [DatabaseName] varchar(100) NOT NULL,
    [SchemaMapping] varchar(100) NOT NULL,
    [Select] bit NOT NULL,
    [Execute] bit NOT NULL,
    [ViewDefinition] bit NOT NULL,
    [Insert] bit NOT NULL,
    [Delete] bit NOT NULL,
    [Update] bit NOT NULL,
    [Alter] bit NOT NULL,
    [Control] bit NOT NULL,
    [References] bit NOT NULL,
    [Include_WRK_Schemas] bit NOT NULL,
    [Include_XBK_Schemas] bit NOT NULL,
    [Unmask] bit NOT NULL
);
