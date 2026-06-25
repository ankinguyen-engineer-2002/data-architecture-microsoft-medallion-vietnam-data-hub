-- InventoryHistory_Enh_Wrk.v_InventorySnapshotWeekly
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_InventorySnapshotWeekly] AS
WITH latest_effective_snapshot AS (
    SELECT MAX(CAST(dinSnapshot AS DATE)) AS LatestInventorySnapshotDate
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandInventorySnapshotDaily]
    WHERE CAST(dinSnapshot AS DATE) <= DATEADD(day, -1, CAST(SYSUTCDATETIME() AS DATE))
),
source_rows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(dinSnapshot AS DATE) AS SnapshotWeekEndingDate,
        CAST(dinFiscalMonth AS INT) AS FiscalMonth,
        CAST(DATEFROMPARTS(CAST(dinFiscalMonth / 100 AS INT), CAST(dinFiscalMonth % 100 AS INT), 1) AS DATE) AS FiscalMonthDate,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(dinIOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
        CAST(dinOrderQuantity AS DECIMAL(18,4)) AS OrderQty,
        CAST(dinBuildQuantity AS DECIMAL(18,4)) AS BuildQty,
        CAST(TRIM(dinMakeBuyCode) AS VARCHAR(10)) AS MakeBuyCode,
        CAST(TRIM(dinSource1) AS VARCHAR(50)) AS SourceWarehouseCode,
        CAST(TRIM(dinPrimaryVendorNumber) AS VARCHAR(50)) AS PrimaryVendorNumber,
        CAST(TRIM(dinPrimaryVendorName) AS VARCHAR(200)) AS PrimaryVendorName,
        CAST(TRIM(dinPrimaryVendorSplit) AS VARCHAR(50)) AS PrimaryVendorSplit,
        CAST(TRIM(dinSecondaryVendorNumber) AS VARCHAR(50)) AS SecondaryVendorNumber,
        CAST(TRIM(dinSecondaryVendorName) AS VARCHAR(200)) AS SecondaryVendorName,
        CAST(TRIM(dinSecondaryVendorSplit) AS VARCHAR(50)) AS SecondaryVendorSplit,
        CAST(dinReplenishmentLeadTime AS DECIMAL(18,4)) AS ReplenishmentLeadTime,
        CAST('DemandInventorySnapshotDaily' AS VARCHAR(50)) AS SourceLabel,
        CAST('SupplyChain_Enh' AS VARCHAR(64)) AS SourceSystem,
        CAST('DemandInventorySnapshotDaily (Sat + latest effective dedupe)' AS VARCHAR(128)) AS SourceTable,
        CAST(CASE
            WHEN ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
                THEN 1
            ELSE 0
        END AS INT) AS IsHistoricalWeeklySnapshot,
        CAST(CASE
            WHEN CAST(dinSnapshot AS DATE) = LatestInventorySnapshotDate
                THEN 1
            ELSE 0
        END AS INT) AS IsLatestInventorySnapshot,
        CAST(CASE
            WHEN CAST(dinSnapshot AS DATE) = LatestInventorySnapshotDate
             AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
                THEN 'WEEKLY_AND_LATEST'
            WHEN CAST(dinSnapshot AS DATE) = LatestInventorySnapshotDate
                THEN 'LATEST'
            ELSE 'WEEKLY'
        END AS VARCHAR(30)) AS SnapshotType,
        LatestInventorySnapshotDate,
        dtec,
        dtea
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandInventorySnapshotDaily]
    CROSS JOIN latest_effective_snapshot
    WHERE dinItem IS NOT NULL
      AND dinWarehouse IS NOT NULL
      AND TRIM(dinItem) <> ''
      AND TRIM(dinWarehouse) <> ''
      AND dinFiscalMonth IS NOT NULL
      AND (
            ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
         OR CAST(dinSnapshot AS DATE) = LatestInventorySnapshotDate
      )
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
            ORDER BY dtec DESC, dtea DESC
        ) AS rn
    FROM source_rows
),
__bob_source AS (
SELECT
    ItemSku,
    WarehouseCode,
    SnapshotDate,
    SnapshotWeekEndingDate,
    FiscalMonth,
    FiscalMonthDate,
    OnHandQty,
    SafetyStockTarget,
    IOSafetyStock,
    OrderQty,
    BuildQty,
    MakeBuyCode,
    SourceWarehouseCode,
    PrimaryVendorNumber,
    PrimaryVendorName,
    PrimaryVendorSplit,
    SecondaryVendorNumber,
    SecondaryVendorName,
    SecondaryVendorSplit,
    ReplenishmentLeadTime,
    SourceLabel,
    SourceSystem,
    SourceTable,
    IsHistoricalWeeklySnapshot,
    IsLatestInventorySnapshot,
    SnapshotType,
    LatestInventorySnapshotDate
FROM ranked
WHERE rn = 1
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [SnapshotDate] = src.[SnapshotDate],
    [SnapshotWeekEndingDate] = src.[SnapshotWeekEndingDate],
    [FiscalMonth] = src.[FiscalMonth],
    [FiscalMonthDate] = src.[FiscalMonthDate],
    [OnHandQty] = src.[OnHandQty],
    [SafetyStockTarget] = src.[SafetyStockTarget],
    [IOSafetyStock] = src.[IOSafetyStock],
    [OrderQty] = src.[OrderQty],
    [BuildQty] = src.[BuildQty],
    [MakeBuyCode] = src.[MakeBuyCode],
    [SourceWarehouseCode] = src.[SourceWarehouseCode],
    [PrimaryVendorNumber] = src.[PrimaryVendorNumber],
    [PrimaryVendorName] = src.[PrimaryVendorName],
    [PrimaryVendorSplit] = src.[PrimaryVendorSplit],
    [SecondaryVendorNumber] = src.[SecondaryVendorNumber],
    [SecondaryVendorName] = src.[SecondaryVendorName],
    [SecondaryVendorSplit] = src.[SecondaryVendorSplit],
    [ReplenishmentLeadTime] = src.[ReplenishmentLeadTime],
    [SourceLabel] = src.[SourceLabel],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [IsHistoricalWeeklySnapshot] = src.[IsHistoricalWeeklySnapshot],
    [IsLatestInventorySnapshot] = src.[IsLatestInventorySnapshot],
    [SnapshotType] = src.[SnapshotType],
    [LatestInventorySnapshotDate] = src.[LatestInventorySnapshotDate],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
