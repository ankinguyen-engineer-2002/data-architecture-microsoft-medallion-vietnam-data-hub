-- Forecast Accuracy KPI load contract.
-- FactForecastKpi derives QtyActual from mutable ActualDemandMonthly, so the
-- target must be rebuilt from the current view.  A Snapshot DateRange window
-- is invalid because old snapshots still need their Actual/error columns
-- restated.  This script is idempotent and intentionally scoped to one row.
SET NOCOUNT ON;

BEGIN TRANSACTION;

DECLARE @ChangedAt datetime2(6) = SYSUTCDATETIME();

IF NOT EXISTS
(
    SELECT 1
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
      AND [SchemaName] = 'ForecastAccuracy_DW'
      AND [TableName] = 'FactForecastKpi'
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 51030, 'FactForecastKpi TableDictionary row is missing; refuse implicit contract creation.', 1;
END;

UPDATE [DW_Developer].[TableDictionary]
SET
    [UpdateMethod] = 'overwrite',
    [DateKey] = NULL,
    [DateRangeDays] = NULL,
    [UpdateQuery] = '[DW_Developer].[usp_RefreshCuratedTableFromView]',
    [Modified] = @ChangedAt,
    [ModifiedBy] = 'ForecastAccuracy-FactForecastKpi-Restate'
WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
  AND [SchemaName] = 'ForecastAccuracy_DW'
  AND [TableName] = 'FactForecastKpi';

IF EXISTS
(
    SELECT 1
    FROM [DW_Developer].[TableDictionary]
    WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
      AND [SchemaName] = 'ForecastAccuracy_DW'
      AND [TableName] = 'FactForecastKpi'
      AND ([UpdateMethod] <> 'overwrite' OR [DateKey] IS NOT NULL OR [DateRangeDays] IS NOT NULL)
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 51031, 'FactForecastKpi TableDictionary overwrite contract did not persist.', 1;
END;

COMMIT TRANSACTION;

SELECT
    [DatabaseName], [SchemaName], [TableName], [UpdateMethod], [DateKey],
    [DateRangeDays], [UpdateQuery], [Modified], [ModifiedBy]
FROM [DW_Developer].[TableDictionary]
WHERE [DatabaseName] = 'SupplyChain_Gold_Warehouse'
  AND [SchemaName] = 'ForecastAccuracy_DW'
  AND [TableName] = 'FactForecastKpi';
