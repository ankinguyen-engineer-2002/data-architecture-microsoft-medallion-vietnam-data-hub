-- SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_AtpWeekEnding
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_AtpWeekEnding] AS
-- Source rule:
--   InsertedDate is the official snapshot/as-of date.
--   Keep historical Saturday snapshots, ATPWeek = Week2, InsertedVersion = 2.
--   Also keep the latest effective InsertedDate <= D-1 for InsertedVersion = 2 across all ATPWeek/WeekEnding rows.
--   If source has duplicate rows at the view grain, keep the latest InsertedDate timestamp.
WITH latest_effective_snapshot AS (
    SELECT
        MAX(CAST(InsertedDate AS DATE)) AS LatestAtpSnapshotDate
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[ATPWeekEnding]
    WHERE InsertedDate IS NOT NULL
      AND CAST(InsertedVersion AS INT) = 2
      AND CAST(InsertedDate AS DATE) <= DATEADD(day, -1, CAST(SYSUTCDATETIME() AS DATE))
),
source_rows AS (
    SELECT
        CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InsertedDate AS DATE) AS SnapshotDate,
        CAST(InsertedDate AS DATE) AS SnapshotWeekEndingDate,
        CAST(RunDate AS DATE) AS SourceRunDate,
        CAST(TRIM(SeriesNumber) AS VARCHAR(50)) AS SeriesNumber,
        CAST(TRIM(AFIFinanceDivision) AS VARCHAR(50)) AS AFIFinanceDivision,
        CAST(TRIM(AFISalesDivision) AS VARCHAR(50)) AS AFISalesDivision,
        CAST(TRIM(ItemGrouping) AS VARCHAR(100)) AS ItemGrouping,
        CAST(TRIM(ATPWeek) AS VARCHAR(20)) AS ATPWeek,
        TRY_CAST(REPLACE(TRIM(ATPWeek), 'Week', '') AS INT) AS WeekNumber,
        CAST(WeekEnding AS DATE) AS WeekEndingDate,
        CAST(ATPQty AS DECIMAL(18,4)) AS AtpQty,
        CAST(APNQ AS DECIMAL(18,4)) AS APNQ,
        CAST(InsertedDate AS DATETIME2(6)) AS InsertedDateTime,
        CAST(InsertedVersion AS INT) AS InsertedVersion,
        CAST(TRIM(VersionDescription) AS VARCHAR(100)) AS VersionDescription,
        CAST('SupplyChain_Enh' AS VARCHAR(64)) AS SourceSystem,
        CAST('ATPWeekEnding (InsertedVersion=2, Sat Week2 + latest effective all weeks)' AS VARCHAR(128)) AS SourceTable,
        CAST(CASE
            WHEN TRIM(ATPWeek) = 'Week2'
             AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(InsertedDate AS DATE)) % 7) + 1) = 6
                THEN 1
            ELSE 0
        END AS INT) AS IsHistoricalWeeklySnapshot,
        CAST(CASE
            WHEN CAST(InsertedDate AS DATE) = LatestAtpSnapshotDate
                THEN 1
            ELSE 0
        END AS INT) AS IsLatestAtpSnapshot,
        CAST(CASE
            WHEN CAST(InsertedDate AS DATE) = LatestAtpSnapshotDate
             AND TRIM(ATPWeek) = 'Week2'
             AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(InsertedDate AS DATE)) % 7) + 1) = 6
                THEN 'WEEKLY_AND_LATEST'
            WHEN CAST(InsertedDate AS DATE) = LatestAtpSnapshotDate
                THEN 'LATEST'
            ELSE 'WEEKLY'
        END AS VARCHAR(30)) AS SnapshotType,
        LatestAtpSnapshotDate
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[ATPWeekEnding]
    CROSS JOIN latest_effective_snapshot
    WHERE ItemSKU IS NOT NULL
      AND Warehouse IS NOT NULL
      AND TRIM(ItemSKU) <> ''
      AND TRIM(Warehouse) <> ''
      AND InsertedDate IS NOT NULL
      AND WeekEnding IS NOT NULL
      AND CAST(InsertedVersion AS INT) = 2
      AND (
            (
                TRIM(ATPWeek) = 'Week2'
                AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(InsertedDate AS DATE)) % 7) + 1) = 6
            )
         OR CAST(InsertedDate AS DATE) = LatestAtpSnapshotDate
      )
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                ItemSku,
                WarehouseCode,
                SnapshotDate,
                ATPWeek,
                WeekEndingDate,
                InsertedVersion
            ORDER BY
                InsertedDateTime DESC,
                SourceRunDate DESC,
                AtpQty DESC
        ) AS rn
    FROM source_rows
),
__bob_source AS (
SELECT
    ItemSku,
    WarehouseCode,
    SnapshotDate,
    SnapshotWeekEndingDate,
    SourceRunDate,
    SeriesNumber,
    AFIFinanceDivision,
    AFISalesDivision,
    ItemGrouping,
    ATPWeek,
    WeekNumber,
    WeekEndingDate,
    AtpQty,
    APNQ,
    InsertedDateTime,
    InsertedVersion,
    VersionDescription,
    SourceSystem,
    SourceTable,
    IsHistoricalWeeklySnapshot,
    IsLatestAtpSnapshot,
    SnapshotType,
    LatestAtpSnapshotDate
FROM ranked
WHERE rn = 1
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [SnapshotDate] = src.[SnapshotDate],
    [SnapshotWeekEndingDate] = src.[SnapshotWeekEndingDate],
    [SourceRunDate] = src.[SourceRunDate],
    [SeriesNumber] = src.[SeriesNumber],
    [AFIFinanceDivision] = src.[AFIFinanceDivision],
    [AFISalesDivision] = src.[AFISalesDivision],
    [ItemGrouping] = src.[ItemGrouping],
    [ATPWeek] = src.[ATPWeek],
    [WeekNumber] = src.[WeekNumber],
    [WeekEndingDate] = src.[WeekEndingDate],
    [AtpQty] = src.[AtpQty],
    [APNQ] = src.[APNQ],
    [InsertedDateTime] = src.[InsertedDateTime],
    [InsertedVersion] = src.[InsertedVersion],
    [VersionDescription] = src.[VersionDescription],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [IsHistoricalWeeklySnapshot] = src.[IsHistoricalWeeklySnapshot],
    [IsLatestAtpSnapshot] = src.[IsLatestAtpSnapshot],
    [SnapshotType] = src.[SnapshotType],
    [LatestAtpSnapshotDate] = src.[LatestAtpSnapshotDate],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
