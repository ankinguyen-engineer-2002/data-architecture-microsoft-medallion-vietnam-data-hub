-- Align the DEV Enterprise ETL metadata with the 90-day W02 runtime contract.
SET NOCOUNT ON;

BEGIN TRANSACTION;

DECLARE @ContractRows int;
DECLARE @ChangedAt datetime2(6) = SYSUTCDATETIME();

SELECT @ContractRows = COUNT(*)
FROM [DW_Developer].[TableDictionary]
WHERE [DatabaseName] = 'SupplyChain_Processing_Warehouse'
  AND
  (
      ([SchemaName] = 'ForecastHistory_Enh' AND [TableName] = 'ForecastDemandMonthly')
      OR
      (
          [SchemaName] = 'InventoryHistory_Enh'
          AND [TableName] IN
          (
              'ForecastSnapshotWeekly',
              'PurchaseOrderSnapshotHistorical',
              'SupplyPlanDetail'
          )
      )
  );

IF @ContractRows <> 4
BEGIN
    ROLLBACK TRANSACTION;
    THROW 51020, 'Expected exactly four Supply Chain DateRange metadata rows.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Processing_Warehouse'
      AND ISNULL([DateRangeDays], -1) <> 90
      AND
      (
          ([SchemaName] = 'ForecastHistory_Enh' AND [TableName] = 'ForecastDemandMonthly')
          OR
          (
              [SchemaName] = 'InventoryHistory_Enh'
              AND [TableName] IN
              (
                  'ForecastSnapshotWeekly',
                  'PurchaseOrderSnapshotHistorical',
                  'SupplyPlanDetail'
              )
          )
      )
)
BEGIN
    UPDATE [DW_Developer].[TableDictionary]
    SET
        [DateRangeDays] = 90,
        [Modified] = @ChangedAt,
        [ModifiedBy] = 'EAS-2486-90d-sync'
    WHERE [DatabaseName] = 'SupplyChain_Processing_Warehouse'
      AND
      (
          ([SchemaName] = 'ForecastHistory_Enh' AND [TableName] = 'ForecastDemandMonthly')
          OR
          (
              [SchemaName] = 'InventoryHistory_Enh'
              AND [TableName] IN
              (
                  'ForecastSnapshotWeekly',
                  'PurchaseOrderSnapshotHistorical',
                  'SupplyPlanDetail'
              )
          )
      );

    INSERT INTO [DW_Developer].[TableDictionary_UpdateLog]
    (
        [DatabaseName],
        [SchemaName],
        [TableName],
        [LastUpdated]
    )
    SELECT
        [DatabaseName],
        [SchemaName],
        [TableName],
        @ChangedAt
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Processing_Warehouse'
      AND
      (
          ([SchemaName] = 'ForecastHistory_Enh' AND [TableName] = 'ForecastDemandMonthly')
          OR
          (
              [SchemaName] = 'InventoryHistory_Enh'
              AND [TableName] IN
              (
                  'ForecastSnapshotWeekly',
                  'PurchaseOrderSnapshotHistorical',
                  'SupplyPlanDetail'
              )
          )
      );

    INSERT INTO [DW_Developer].[AuditLog]
    (
        [Description],
        [DateTime],
        [User],
        [Command]
    )
    VALUES
    (
        'EAS-2486 DEV contract sync: four DateRange tables aligned to 90 days',
        @ChangedAt,
        SYSTEM_USER,
        'DateRangeDays -> 90; no ETL execution'
    );
END;

COMMIT TRANSACTION;

SELECT
    [DatabaseName],
    [SchemaName],
    [TableName],
    [UpdateMethod],
    [DateKey],
    [DateRangeDays],
    [Modified],
    [ModifiedBy]
FROM [DW_Developer].[TableDictionary]
WHERE [DatabaseName] = 'SupplyChain_Processing_Warehouse'
  AND
  (
      ([SchemaName] = 'ForecastHistory_Enh' AND [TableName] = 'ForecastDemandMonthly')
      OR
      (
          [SchemaName] = 'InventoryHistory_Enh'
          AND [TableName] IN
          (
              'ForecastSnapshotWeekly',
              'PurchaseOrderSnapshotHistorical',
              'SupplyPlanDetail'
          )
      )
  )
ORDER BY [SchemaName], [TableName];
