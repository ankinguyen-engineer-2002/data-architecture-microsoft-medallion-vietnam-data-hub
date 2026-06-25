-- InventoryHistory_Enh_Wrk.v_ItemBalanceHistorical_WithInTransit
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_ItemBalanceHistorical_WithInTransit] AS
WITH ranked AS
(
    SELECT
        TRIM(ItemNumber)                  AS ItemSku,
        TRIM(Warehouse)                   AS WarehouseCode,
        CAST(DateWeekEnding AS DATE)      AS WeekEndingDate,
        CAST(OnHandQty AS DECIMAL(18,4))  AS OnHandQty,
        TRIM(ItemStatus)                  AS ItemStatus,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                TRIM(ItemNumber),
                TRIM(Warehouse),
                CAST(DateWeekEnding AS DATE)
            ORDER BY
                OnHandQty DESC,
                ItemStatus
        ) AS rn
    FROM [Enterprise_Lakehouse].[Inventory_Enh_History].[ItemBalance]
    WHERE ItemNumber IS NOT NULL
      AND Warehouse IS NOT NULL
      AND TRIM(ItemNumber) <> ''
      AND TRIM(Warehouse) <> ''
),
ItemBalanceHistorical AS
(
    SELECT
        CAST(ItemSku        AS VARCHAR(50))   AS ItemSku,
        CAST(WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
        CAST(WeekEndingDate AS DATE)          AS WeekEndingDate,
        CAST(OnHandQty      AS DECIMAL(18,4)) AS OnHandQty,
        CAST(ItemStatus     AS VARCHAR(10))   AS ItemStatus,
        CAST('Enterprise_Lakehouse' AS VARCHAR(64))  AS SourceSystem,
        CAST('Inventory_Enh_History.ItemBalance' AS VARCHAR(128)) AS SourceTable
    FROM ranked
    WHERE rn = 1
),
InTransitQty AS
(
    SELECT
        H.ItemSku,
        M.[WarehouseCode] AS WarehouseCode,
        H.WeekEndingDate,
        SUM(H.OnHandQty) AS InTransitQty
    FROM ItemBalanceHistorical H
    INNER JOIN [ReferenceMaster_Enh].[Warehouse] M
        ON M.[IntransitWarehouse] = H.WarehouseCode
    WHERE H.WarehouseCode IN
    (
        'A','B','L','N','T',
        'F','E','W','M','V','S'
    )
    GROUP BY
        H.ItemSku,
        M.[WarehouseCode],
        H.WeekEndingDate
),
__bob_source AS (
SELECT
    FG.ItemSku,
    FG.WarehouseCode,
    FG.WeekEndingDate,
    FG.OnHandQty,
    CAST(ISNULL(IT.InTransitQty,0) AS DECIMAL(18,4)) AS InTransitQty,
    CAST(FG.OnHandQty + ISNULL(IT.InTransitQty,0) AS DECIMAL(18,4)) AS TotalAvailQty,
    FG.ItemStatus,
    FG.SourceSystem,
    FG.SourceTable
FROM ItemBalanceHistorical FG
LEFT JOIN InTransitQty IT
    ON FG.ItemSku         = IT.ItemSku
   AND FG.WarehouseCode  = IT.WarehouseCode
   AND FG.WeekEndingDate = IT.WeekEndingDate
WHERE FG.WarehouseCode IN
(
    '1','5','15','17','28',
    '42','ECR','3','12','16','19'
)
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [WeekEndingDate] = src.[WeekEndingDate],
    [OnHandQty] = src.[OnHandQty],
    [InTransitQty] = src.[InTransitQty],
    [TotalAvailQty] = src.[TotalAvailQty],
    [ItemStatus] = src.[ItemStatus],
    [SourceSystem] = src.[SourceSystem],
    [SourceTable] = src.[SourceTable],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
