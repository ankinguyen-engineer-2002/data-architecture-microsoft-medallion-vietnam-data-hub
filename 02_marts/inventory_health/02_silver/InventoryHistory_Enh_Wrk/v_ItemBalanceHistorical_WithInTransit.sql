CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_ItemBalanceHistorical_WithInTransit]
AS

WITH ItemBalanceHistorical AS
(
    SELECT
        CAST(TRIM(ItemNumber) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(DateWeekEnding AS DATE) AS WeekEndingDate,

        CAST
        (
            SUM(COALESCE(CAST(OnHandQty AS DECIMAL(18,4)), 0))
            AS DECIMAL(18,4)
        ) AS OnHandQty,

        -- Nếu duplicate có nhiều ItemStatus khác nhau,
        -- tạm lấy giá trị lớn nhất.
        CAST(MAX(TRIM(ItemStatus)) AS VARCHAR(10)) AS ItemStatus,

        CAST('Enterprise_Lakehouse' AS VARCHAR(64)) AS SourceSystem,
        CAST(
            'Inventory_Enh_History.ItemBalance'
            AS VARCHAR(128)
        ) AS SourceTable
    FROM [Enterprise_Lakehouse].[Inventory_Enh_History].[ItemBalance]
    WHERE ItemNumber IS NOT NULL
      AND Warehouse IS NOT NULL
      AND TRIM(ItemNumber) <> ''
      AND TRIM(Warehouse) <> ''
    GROUP BY
        TRIM(ItemNumber),
        TRIM(Warehouse),
        CAST(DateWeekEnding AS DATE)
),
InTransitQty AS
(
    SELECT
        H.ItemSku,
        M.WarehouseCode,
        H.WeekEndingDate,
        CAST
        (
            SUM
            (
                CASE
                    WHEN H.OnHandQty > 0 THEN H.OnHandQty
                    ELSE 0
                END
            )
            AS DECIMAL(18,4)
        ) AS InTransitQty
    FROM ItemBalanceHistorical H
    INNER JOIN [ReferenceMaster_Enh].[Warehouse] M
        ON M.IntransitWarehouse = H.WarehouseCode
    WHERE H.WarehouseCode IN
    (
        'A', 'B', 'L', 'N', 'T',
        'F', 'E', 'W', 'M', 'V', 'S'
    )
    GROUP BY
        H.ItemSku,
        M.WarehouseCode,
        H.WeekEndingDate
)
SELECT
    FG.ItemSku,
    FG.WarehouseCode,
    FG.WeekEndingDate,
    FG.OnHandQty,

    CAST(
        COALESCE(IT.InTransitQty, 0)
        AS DECIMAL(18,4)
    ) AS InTransitQty,

    CAST(
        FG.OnHandQty + COALESCE(IT.InTransitQty, 0)
        AS DECIMAL(18,4)
    ) AS TotalAvailQty,

    FG.ItemStatus,
    FG.SourceSystem,
    FG.SourceTable,
    CAST(SYSUTCDATETIME() AS DATETIME2(6)) AS LoadDT
FROM ItemBalanceHistorical FG
LEFT JOIN InTransitQty IT
    ON  FG.ItemSku = IT.ItemSku
    AND FG.WarehouseCode = IT.WarehouseCode
    AND FG.WeekEndingDate = IT.WeekEndingDate;

-- Có thể thêm filter warehouse vật lý:
-- WHERE FG.WarehouseCode IN
-- (
--     '1', '5', '15', '17', '28',
--     '42', 'ECR', '3', '12', '16', '19'
-- );

GO
