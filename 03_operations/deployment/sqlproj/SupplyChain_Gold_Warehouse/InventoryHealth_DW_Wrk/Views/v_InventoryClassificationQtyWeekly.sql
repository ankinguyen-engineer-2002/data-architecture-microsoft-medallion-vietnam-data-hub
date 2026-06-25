-- InventoryHealth_DW_Wrk.v_InventoryClassificationQtyWeekly
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_InventoryClassificationQtyWeekly] AS
WITH inv_base AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotWeekEndingDate,
        OnHandQty
    FROM (
        SELECT
            ItemSku,
            WarehouseCode,
            SnapshotWeekEndingDate,
            OnHandQty,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate
                ORDER BY FiscalMonthDate ASC
            ) AS rn
        FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[InventorySnapshotWeekly]
    ) ranked_inv
    WHERE rn = 1
),
src AS (
    SELECT
        inv.ItemSku AS Item,
        inv.WarehouseCode AS WH,
        inv.SnapshotWeekEndingDate AS SnapshotWeekEnding,
        CAST(COALESCE(inv.OnHandQty, 0) AS DECIMAL(18,4)) AS OnHandsQty,
        CAST(COALESCE(ss.SafetyStockTarget, 0) AS DECIMAL(18,4)) AS SSTarget,
        CAST(awd.AwdQty AS DECIMAL(18,4)) AS AvgWeeklyDemand,
        cls.[InventoryClassification Final Status]
    FROM inv_base inv
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
        ON awd.ItemSku = inv.ItemSku
       AND awd.WarehouseCode = inv.WarehouseCode
       AND awd.AsOfDate = inv.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss
        ON ss.ItemSku = inv.ItemSku
       AND ss.WarehouseCode = inv.WarehouseCode
       AND ss.AsOfDate = inv.SnapshotWeekEndingDate
    LEFT JOIN [InventoryHealth_DW].[InventoryHealthSubStatusWeekly] cls
        ON cls.ItemSku = inv.ItemSku
       AND cls.WarehouseCode = inv.WarehouseCode
       AND cls.SnapshotWeekEnding = inv.SnapshotWeekEndingDate
),
raw_bounds AS (
    SELECT
        src.*,
        CASE WHEN 0.5 * SSTarget > 0 THEN 0.5 * SSTarget ELSE 0 END AS RawBelowUpperQty,
        CASE WHEN 1.5 * SSTarget > 0 THEN 1.5 * SSTarget ELSE 0 END AS RawSweetSpotUpperQty,
        CASE
            WHEN AvgWeeklyDemand > 0 THEN 17 * AvgWeeklyDemand
            ELSE OnHandsQty
        END AS RawOverTargetUpperQty,
        CASE
            WHEN AvgWeeklyDemand > 0 THEN 52 * AvgWeeklyDemand
            ELSE OnHandsQty
        END AS RawExcessUpperQty,
        CASE
            WHEN AvgWeeklyDemand > 0 THEN 104 * AvgWeeklyDemand
            ELSE OnHandsQty
        END AS RawAEUpperQty
    FROM src
),
below_bound AS (
    SELECT
        raw_bounds.*,
        RawBelowUpperQty AS BelowUpperQty
    FROM raw_bounds
),
sweet_bound AS (
    SELECT
        below_bound.*,
        CASE
            WHEN RawSweetSpotUpperQty > BelowUpperQty THEN RawSweetSpotUpperQty
            ELSE BelowUpperQty
        END AS SweetSpotUpperQty
    FROM below_bound
),
over_bound AS (
    SELECT
        sweet_bound.*,
        CASE
            WHEN RawOverTargetUpperQty > SweetSpotUpperQty THEN RawOverTargetUpperQty
            ELSE SweetSpotUpperQty
        END AS OverTargetUpperQty
    FROM sweet_bound
),
excess_bound AS (
    SELECT
        over_bound.*,
        CASE
            WHEN RawExcessUpperQty > OverTargetUpperQty THEN RawExcessUpperQty
            ELSE OverTargetUpperQty
        END AS ExcessUpperQty
    FROM over_bound
),
bounded AS (
    SELECT
        excess_bound.*,
        CASE
            WHEN RawAEUpperQty > ExcessUpperQty THEN RawAEUpperQty
            ELSE ExcessUpperQty
        END AS AEUpperQty
    FROM excess_bound
),
__bob_source AS (
SELECT
    Item,
    WH,
    SnapshotWeekEnding,
    [InventoryClassification Final Status],
    CASE WHEN [InventoryClassification Final Status] = 'INACTIVE' THEN OnHandsQty ELSE 0 END AS [Qty by InventoryClassification (Inactive)],
    CASE WHEN [InventoryClassification Final Status] = 'SLOB' THEN OnHandsQty ELSE 0 END AS [Qty by InventoryClassification (SLOB)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= 0 THEN 0
        WHEN OnHandsQty <= BelowUpperQty THEN OnHandsQty
        ELSE BelowUpperQty
    END AS [Qty by InventoryClassification (Below Target)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= BelowUpperQty THEN 0
        WHEN OnHandsQty <= SweetSpotUpperQty THEN OnHandsQty - BelowUpperQty
        ELSE SweetSpotUpperQty - BelowUpperQty
    END AS [Qty by InventoryClassification (SweetSpot)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= SweetSpotUpperQty THEN 0
        WHEN OnHandsQty <= OverTargetUpperQty THEN OnHandsQty - SweetSpotUpperQty
        ELSE OverTargetUpperQty - SweetSpotUpperQty
    END AS [Qty by InventoryClassification (OverTarget)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= OverTargetUpperQty THEN 0
        WHEN OnHandsQty <= ExcessUpperQty THEN OnHandsQty - OverTargetUpperQty
        ELSE ExcessUpperQty - OverTargetUpperQty
    END AS [Qty by InventoryClassification (Excess)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= ExcessUpperQty THEN 0
        WHEN OnHandsQty <= AEUpperQty THEN OnHandsQty - ExcessUpperQty
        ELSE AEUpperQty - ExcessUpperQty
    END AS [Qty by InventoryClassification (AE)],
    CASE
        WHEN [InventoryClassification Final Status] IN ('INACTIVE','SLOB') THEN 0
        WHEN OnHandsQty <= AEUpperQty THEN 0
        ELSE OnHandsQty - AEUpperQty
    END AS [Qty by InventoryClassification (TB Inventory)]
FROM bounded
)
SELECT
    [Item] = src.[Item],
    [WH] = src.[WH],
    [SnapshotWeekEnding] = src.[SnapshotWeekEnding],
    [InventoryClassification Final Status] = src.[InventoryClassification Final Status],
    [Qty by InventoryClassification (Inactive)] = src.[Qty by InventoryClassification (Inactive)],
    [Qty by InventoryClassification (SLOB)] = src.[Qty by InventoryClassification (SLOB)],
    [Qty by InventoryClassification (Below Target)] = src.[Qty by InventoryClassification (Below Target)],
    [Qty by InventoryClassification (SweetSpot)] = src.[Qty by InventoryClassification (SweetSpot)],
    [Qty by InventoryClassification (OverTarget)] = src.[Qty by InventoryClassification (OverTarget)],
    [Qty by InventoryClassification (Excess)] = src.[Qty by InventoryClassification (Excess)],
    [Qty by InventoryClassification (AE)] = src.[Qty by InventoryClassification (AE)],
    [Qty by InventoryClassification (TB Inventory)] = src.[Qty by InventoryClassification (TB Inventory)]
FROM __bob_source AS src;
