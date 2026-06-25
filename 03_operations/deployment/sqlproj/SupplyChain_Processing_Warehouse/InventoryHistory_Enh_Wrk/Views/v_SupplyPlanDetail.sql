-- InventoryHistory_Enh_Wrk.v_SupplyPlanDetail
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_SupplyPlanDetail] AS
WITH dedup_base AS (
    SELECT
        *,
        CAST(dtea AS date) AS SnapshotDate,
        TRIM(spdItem) AS ItemSku,
        TRIM(spdWarehouse) AS WarehouseCode,
        ROW_NUMBER() OVER (
            PARTITION BY
                CAST(dtea AS date),
                TRIM(spdItem),
                TRIM(spdWarehouse),
                spdWeekEnding
            ORDER BY dtec DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[SupplyPlanDetailSnapshotDaily]
),

dedup AS (
    SELECT *
    FROM dedup_base
    WHERE rn = 1
),

latest_effective_snapshot AS (
    SELECT
        MAX(SnapshotDate) AS LatestSupplyPlanSnapshotDate
    FROM dedup
    WHERE SnapshotDate <= DATEADD(day, -1, CAST(SYSUTCDATETIME() AS date))
),

snapshotselected_dedup AS (
    SELECT
        d.*,
        CAST(CASE
            WHEN d.SnapshotDate = DATEADD(day, -5, CAST(d.spdWeekEnding AS date))
                THEN 1
            ELSE 0
        END AS INT) AS IsHistoricalWeeklySnapshot,
        CAST(CASE
            WHEN d.SnapshotDate = les.LatestSupplyPlanSnapshotDate
                THEN 1
            ELSE 0
        END AS INT) AS IsLatestSupplyPlanSnapshot,
        CAST(CASE
            WHEN d.SnapshotDate = les.LatestSupplyPlanSnapshotDate
             AND d.SnapshotDate = DATEADD(day, -5, CAST(d.spdWeekEnding AS date))
                THEN 'WEEKLY_AND_LATEST'
            WHEN d.SnapshotDate = les.LatestSupplyPlanSnapshotDate
                THEN 'LATEST'
            ELSE 'WEEKLY'
        END AS VARCHAR(30)) AS SnapshotType,
        les.LatestSupplyPlanSnapshotDate
    FROM dedup d
    CROSS JOIN latest_effective_snapshot les
    WHERE d.spdWeekEnding IS NOT NULL
      AND (
            d.SnapshotDate = DATEADD(day, -5, CAST(d.spdWeekEnding AS date))
         OR d.SnapshotDate = les.LatestSupplyPlanSnapshotDate
      )
),

future_from_same_snapshot AS (
    SELECT
        cur.ItemSku,
        cur.WarehouseCode,
        cur.SnapshotDate,
        cur.spdWeekEnding AS WeekEnding,

        SUM(CASE
                WHEN nxt.spdWeekEnding = DATEADD(day, 7, cur.spdWeekEnding)
                THEN COALESCE(nxt.spdFirmDemands, 0)
                ELSE 0
            END) AS FirmDemandQtyNext7D,

        SUM(CASE
                WHEN nxt.spdWeekEnding IN (
                    DATEADD(day, 7, cur.spdWeekEnding),
                    DATEADD(day, 14, cur.spdWeekEnding)
                )
                THEN COALESCE(nxt.spdFirmDemands, 0)
                ELSE 0
            END) AS FirmDemandQtyNext14D,

        SUM(CASE
                WHEN nxt.spdWeekEnding IN (
                    DATEADD(day, 7, cur.spdWeekEnding),
                    DATEADD(day, 14, cur.spdWeekEnding)
                )
                THEN COALESCE(nxt.spdNetForecast, 0)
                ELSE 0
            END) AS NetFcstQtyNext14D

    FROM snapshotselected_dedup cur
    LEFT JOIN dedup nxt
        ON cur.ItemSku = nxt.ItemSku
       AND cur.WarehouseCode = nxt.WarehouseCode
       AND cur.SnapshotDate = nxt.SnapshotDate
       AND nxt.spdWeekEnding IN (
            DATEADD(day, 7, cur.spdWeekEnding),
            DATEADD(day, 14, cur.spdWeekEnding)
       )
    GROUP BY
        cur.ItemSku,
        cur.WarehouseCode,
        cur.SnapshotDate,
        cur.spdWeekEnding
),

final AS (
    SELECT
        cur.ItemSku,
        cur.WarehouseCode,
        cur.SnapshotDate,
        CAST(cur.spdWeekEnding AS date) AS WeekEnding,

        CAST(cur.spdBeginingBalance AS decimal(18,4)) AS BeginningBalanceQty,
        CAST(cur.spdFirmDemands AS decimal(18,4)) AS FirmDemandQty,
        CAST(cur.spdNetForecast AS decimal(18,4)) AS NetFcstQty,
        CAST(cur.spdFirmTransferOut AS decimal(18,4)) AS FirmTransferOutQty,
        CAST(cur.spdFirmProduction AS decimal(18,4)) AS FirmProductionQty,
        CAST(cur.spdFirmPurchaseOrders AS decimal(18,4)) AS FirmPurchaseOrderQty,
        CAST(cur.spdInTransitTransferIn AS decimal(18,4)) AS InTransitTransferInQty,
        CAST(cur.spdOnOrderTransferIn AS decimal(18,4)) AS OnOrderTransferInQty,
        CAST(cur.spdPlannedTransferIn AS decimal(18,4)) AS PlannedTransferInQty,
        CAST(cur.spdPlannedTransferOut AS decimal(18,4)) AS PlannedTransferOutQty,
        CAST(cur.spdPlannedProduction AS decimal(18,4)) AS PlannedProductionQty,
        CAST(cur.spdPlannedPurchaseOrders AS decimal(18,4)) AS PlannedPurchaseOrderQty,
        CAST(cur.spdTotalReceipts AS decimal(18,4)) AS TotalReceiptQty,
        CAST(cur.spdShippableInventory AS decimal(18,4)) AS SIQty,
        CAST(cur.spdSafetyStock AS decimal(18,4)) AS SafetyStockQty,
        CAST(cur.spdMonthsOfSupply AS decimal(18,4)) AS MonthsOfSupplyQty,
        CAST(cur.spdResultantForecast AS decimal(18,4)) AS ResultantForecastQty,
        CAST(cur.spdPromotionalLift AS decimal(18,4)) AS PromotionalLiftQty,
        CAST(cur.spdDemandFulfillment AS decimal(18,4)) AS DemandFulfillmentQty,
        CAST(cur.spdWeeklyPromotionalLift AS decimal(18,4)) AS WeeklyPromotionalLiftQty,
        cur.IsHistoricalWeeklySnapshot,
        cur.IsLatestSupplyPlanSnapshot,
        cur.SnapshotType,
        cur.LatestSupplyPlanSnapshotDate,

        CAST(
            CASE
                WHEN COALESCE(cur.spdShippableInventory, 0) < 0
                THEN cur.spdShippableInventory
                ELSE 0
            END AS decimal(18,4)
        ) AS SINegQty,

        CAST(fut.FirmDemandQtyNext7D AS decimal(18,4)) AS FirmDemandQtyNext7D,

        CASE
            WHEN fut.FirmDemandQtyNext7D > 0
            THEN 1 ELSE 0
        END AS IsActiveItemWhIn7DNext,

        CAST(fut.FirmDemandQtyNext14D AS decimal(18,4)) AS FirmDemandQtyNext14D,
        CAST(fut.NetFcstQtyNext14D AS decimal(18,4)) AS NetFcstQtyNext14D,

        CASE
            WHEN fut.FirmDemandQtyNext14D > 0
             AND fut.NetFcstQtyNext14D > 0
            THEN 1 ELSE 0
        END AS IsActiveItemWhIn14DNext,

        CAST(
            CASE
                WHEN COALESCE(cur.spdShippableInventory, 0) >= 0 THEN 0

                WHEN ABS(cur.spdShippableInventory) <= COALESCE(cur.spdNetForecast, 0)
                THEN cur.spdShippableInventory

                ELSE -1 * COALESCE(cur.spdNetForecast, 0)
            END AS decimal(18,4)
        ) AS NetFcstQtyAtRisk,

        CAST(
            CASE
                WHEN COALESCE(cur.spdShippableInventory, 0) >= 0 THEN 0

                WHEN ABS(cur.spdShippableInventory) <= COALESCE(cur.spdNetForecast, 0)
                THEN 0

                WHEN ABS(cur.spdShippableInventory) - COALESCE(cur.spdNetForecast, 0)
                    <= COALESCE(cur.spdFirmDemands, 0)
                THEN -1 * (
                    ABS(cur.spdShippableInventory)
                    - COALESCE(cur.spdNetForecast, 0)
                )

                ELSE -1 * COALESCE(cur.spdFirmDemands, 0)
            END AS decimal(18,4)
        ) AS FirmDemandQtyAtRisk



    FROM snapshotselected_dedup cur
    LEFT JOIN future_from_same_snapshot fut
        ON cur.ItemSku = fut.ItemSku
       AND cur.WarehouseCode = fut.WarehouseCode
       AND cur.SnapshotDate = fut.SnapshotDate
       AND cur.spdWeekEnding = fut.WeekEnding
),
__bob_source AS (
SELECT *
FROM final
)
SELECT
    [ItemSku] = src.[ItemSku],
    [WarehouseCode] = src.[WarehouseCode],
    [SnapshotDate] = src.[SnapshotDate],
    [WeekEnding] = src.[WeekEnding],
    [BeginningBalanceQty] = src.[BeginningBalanceQty],
    [FirmDemandQty] = src.[FirmDemandQty],
    [NetFcstQty] = src.[NetFcstQty],
    [FirmTransferOutQty] = src.[FirmTransferOutQty],
    [FirmProductionQty] = src.[FirmProductionQty],
    [FirmPurchaseOrderQty] = src.[FirmPurchaseOrderQty],
    [InTransitTransferInQty] = src.[InTransitTransferInQty],
    [OnOrderTransferInQty] = src.[OnOrderTransferInQty],
    [PlannedTransferInQty] = src.[PlannedTransferInQty],
    [PlannedTransferOutQty] = src.[PlannedTransferOutQty],
    [PlannedProductionQty] = src.[PlannedProductionQty],
    [PlannedPurchaseOrderQty] = src.[PlannedPurchaseOrderQty],
    [TotalReceiptQty] = src.[TotalReceiptQty],
    [SIQty] = src.[SIQty],
    [SafetyStockQty] = src.[SafetyStockQty],
    [MonthsOfSupplyQty] = src.[MonthsOfSupplyQty],
    [ResultantForecastQty] = src.[ResultantForecastQty],
    [PromotionalLiftQty] = src.[PromotionalLiftQty],
    [DemandFulfillmentQty] = src.[DemandFulfillmentQty],
    [WeeklyPromotionalLiftQty] = src.[WeeklyPromotionalLiftQty],
    [IsHistoricalWeeklySnapshot] = src.[IsHistoricalWeeklySnapshot],
    [IsLatestSupplyPlanSnapshot] = src.[IsLatestSupplyPlanSnapshot],
    [SnapshotType] = src.[SnapshotType],
    [LatestSupplyPlanSnapshotDate] = src.[LatestSupplyPlanSnapshotDate],
    [SINegQty] = src.[SINegQty],
    [FirmDemandQtyNext7D] = src.[FirmDemandQtyNext7D],
    [IsActiveItemWhIn7DNext] = src.[IsActiveItemWhIn7DNext],
    [FirmDemandQtyNext14D] = src.[FirmDemandQtyNext14D],
    [NetFcstQtyNext14D] = src.[NetFcstQtyNext14D],
    [IsActiveItemWhIn14DNext] = src.[IsActiveItemWhIn14DNext],
    [NetFcstQtyAtRisk] = src.[NetFcstQtyAtRisk],
    [FirmDemandQtyAtRisk] = src.[FirmDemandQtyAtRisk],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
