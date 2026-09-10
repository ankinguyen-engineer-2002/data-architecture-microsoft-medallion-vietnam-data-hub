-- Forecast Accuracy KPI customer-group grain load contract.
-- Official object: ForecastAccuracy_DW.FactForecastKpiCustomer.
-- QtyActual is mutable by target month, so the target must be rebuilt from
-- the current view. A Snapshot DateRange window is invalid because old
-- snapshots still need their Actual/error columns restated.
-- This script is idempotent and scoped to one row.
SET NOCOUNT ON;

BEGIN TRANSACTION;

DECLARE @ChangedAt datetime2(6) = SYSUTCDATETIME();

IF NOT EXISTS
(
    SELECT 1
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
      AND [SchemaName] = 'ForecastAccuracy_DW'
      AND [TableName] = 'FactForecastKpiCustomer'
)
BEGIN
    INSERT INTO [DW_Developer].[TableDictionary]
    (
        [ServerName], [DatabaseName], [SchemaName], [TableName], [ObjectType],
        [PrimaryKey], [StorageType], [DistributionKey], [IndexType],
        [SourceSystem], [SourceServer], [SourceDatabase], [SourceObject],
        [SourcePlatform], [ReplicatedSource], [ETLTool], [PackageName],
        [RefreshRate], [RefreshDescription], [UpdateMethod], [UpdateQuery],
        [CreatedBy], [ModifiedBy], [SourceObjectType], [DataLake],
        [DataLakeFolder], [OperationKey], [CreateDate], [CreatedDate], [Created], [Modified]
    )
    VALUES
    (
        'EDW-Fabric', 'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastKpiCustomer', 'Table',
        'CustomerGroupCode, ItemSKU, WarehouseCode, FSCMonthLast, HorizonCode, Snapshot',
        'Delta', 'AUTO', 'CLUSTERED COLUMNSTORE',
        'supplychain', 'EDW-Fabric', 'Enterprise SupplyChain-Dev',
        '["SalesHistory_ENH.ActualDemandMonthly","ForecastHistory_ENH.ForecastDemandMonthly","ForecastHistory_ENH.NaiveForecastMonthly","ReferenceMaster_ENH.ForecastHorizon"]',
        'GoldPublish', 'ForecastAccuracy_DW_Wrk.v_FactForecastKpiCustomer',
        'Fabric Pipeline', 'ForecastAccuracy_DW.FactForecastKpiCustomer',
        24, 'daily', 'overwrite', '[DW_Developer].[usp_RefreshCuratedTableFromView]',
        'NAric@ashleyfurniture.com', 'ForecastAccuracy-FactForecastKpiCustomer-Restate',
        'Table', 'SupplyChain DA', 'SupplyChain_Gold_Warehouse',
        'ForecastAccuracy_DW.FactForecastKpiCustomer',
        @ChangedAt, @ChangedAt, @ChangedAt, @ChangedAt
    );
END;

UPDATE [DW_Developer].[TableDictionary]
SET
    [UpdateMethod] = 'overwrite',
    [DateKey] = NULL,
    [DateRangeDays] = NULL,
    [UpdateQuery] = '[DW_Developer].[usp_RefreshCuratedTableFromView]',
    [PrimaryKey] = 'CustomerGroupCode, ItemSKU, WarehouseCode, FSCMonthLast, HorizonCode, Snapshot',
    [ReplicatedSource] = 'ForecastAccuracy_DW_Wrk.v_FactForecastKpiCustomer',
    [Modified] = @ChangedAt,
    [ModifiedBy] = 'ForecastAccuracy-FactForecastKpiCustomer-Restate'
WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
  AND [SchemaName] = 'ForecastAccuracy_DW'
  AND [TableName] = 'FactForecastKpiCustomer';

IF EXISTS
(
    SELECT 1
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
      AND [SchemaName] = 'ForecastAccuracy_DW'
      AND [TableName] = 'FactForecastKpiCustomer'
      AND ([UpdateMethod] <> 'overwrite' OR [DateKey] IS NOT NULL OR [DateRangeDays] IS NOT NULL)
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 51031, 'FactForecastKpiCustomer TableDictionary overwrite contract did not persist.', 1;
END;

COMMIT TRANSACTION;

SELECT
    [DatabaseName], [SchemaName], [TableName], [UpdateMethod], [DateKey],
    [DateRangeDays], [UpdateQuery], [PrimaryKey], [Modified], [ModifiedBy]
FROM [DW_Developer].[TableDictionary]
WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
  AND [SchemaName] = 'ForecastAccuracy_DW'
  AND [TableName] = 'FactForecastKpiCustomer';
