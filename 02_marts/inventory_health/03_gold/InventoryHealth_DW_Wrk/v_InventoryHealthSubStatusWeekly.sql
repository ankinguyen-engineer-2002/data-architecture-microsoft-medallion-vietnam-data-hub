-- SupplyChain_Gold_Warehouse.InventoryHealth_DW_Wrk.v_InventoryHealthSubStatusWeekly
CREATE   VIEW [InventoryHealth_DW_Wrk].[v_InventoryHealthSubStatusWeekly] AS
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
po_base AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        SUM(COALESCE(POOnOrderQty, 0)) AS POOnOrderQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[PurchaseOrderSnapshotHistorical]
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotDate
),
mo_base AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        SUM(COALESCE(RemainingMOQty, 0)) AS RemainingMOQty
    FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily]
    GROUP BY
        ItemSku,
        WarehouseCode,
        SnapshotDate
),
src AS (
    SELECT
        inv.ItemSku AS ItemSku,
        inv.WarehouseCode AS WarehouseCode,
        inv.SnapshotWeekEndingDate AS SnapshotWeekEnding,
        -- inv.FiscalWeekIndicator,
        CAST(COALESCE(inv.OnHandQty, 0) AS DECIMAL(18,4)) AS OnHandsQty,
        CAST(COALESCE(po.POOnOrderQty, 0) + COALESCE(mo.RemainingMOQty, 0) AS DECIMAL(18,4)) AS OnOrderQty,
        CAST(awd.AwdQty AS DECIMAL(18,4)) AS AvgWeeklyDemand,
        CAST(COALESCE(ss.SafetyStockTarget, 0) AS DECIMAL(18,4)) AS SSTarget,
        im.AFIStatus AS AFIStatus,
        TRY_CONVERT(DATE, li.LastInvoiceDate) AS LastInvoiceDate
    FROM inv_base inv
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AwdHelper] awd
        ON awd.ItemSku = inv.ItemSku
       AND awd.WarehouseCode = inv.WarehouseCode
       AND awd.AsOfDate = inv.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SafetyStockHelper] ss
        ON ss.ItemSku = inv.ItemSku
       AND ss.WarehouseCode = inv.WarehouseCode
       AND ss.AsOfDate = inv.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[AFIStatusSnapshotWeekly] im
        ON im.ItemSku = inv.ItemSku
       AND im.WarehouseCode = inv.WarehouseCode
       AND im.WeekEndingDate = inv.SnapshotWeekEndingDate
    LEFT JOIN [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[LastInvoiceWeekly] li
        ON li.ItemSku = inv.ItemSku
       AND li.WarehouseCode = inv.WarehouseCode
       AND li.WeekEndingDate = inv.SnapshotWeekEndingDate
    LEFT JOIN po_base po
        ON po.ItemSku = inv.ItemSku
       AND po.WarehouseCode = inv.WarehouseCode
       AND po.SnapshotDate = inv.SnapshotWeekEndingDate
    LEFT JOIN mo_base mo
        ON mo.ItemSku = inv.ItemSku
       AND mo.WarehouseCode = inv.WarehouseCode
       AND mo.SnapshotDate = inv.SnapshotWeekEndingDate
),
classified AS (
    SELECT
        s.*,
        CASE
            WHEN UPPER(LTRIM(RTRIM(COALESCE(AFIStatus, '')))) IN ('D', 'R')
                 AND OnHandsQty + OnOrderQty = 0 THEN 'INACTIVE'
            WHEN LastInvoiceDate IS NOT NULL
                 AND LastInvoiceDate <= DATEADD(WEEK, -17, SnapshotWeekEnding)
                 AND UPPER(LTRIM(RTRIM(COALESCE(AFIStatus, '')))) NOT IN ('N') THEN 'SLOB'
            WHEN COALESCE(OnHandsQty, 0) < 0.5 * COALESCE(SSTarget, 0)
                 AND COALESCE(SSTarget, 0) > 0 THEN 'BELOW_TARGET'
            WHEN AvgWeeklyDemand > 0
                 AND OnHandsQty > 104 * AvgWeeklyDemand THEN 'TB_INVENTORY'
            WHEN AvgWeeklyDemand > 0
                 AND OnHandsQty > 52 * AvgWeeklyDemand THEN 'AGGRESSIVE_EXCESS'
            WHEN AvgWeeklyDemand > 0
                 AND OnHandsQty > 17 * AvgWeeklyDemand THEN 'EXCESS'
            WHEN OnHandsQty > 1.5 * COALESCE(SSTarget, 0) THEN 'OVER_TARGET'
            WHEN OnHandsQty >= 0.5 * COALESCE(SSTarget, 0) THEN 'SWEET_SPOT'
            ELSE 'UNCLASSIFIED'
        END AS SubStatus
    FROM src s
),
ranked AS (
    SELECT
        c.*,
        CASE SubStatus
            WHEN 'INACTIVE' THEN 0
            WHEN 'SLOB' THEN 1
            WHEN 'BELOW_TARGET' THEN 2
            WHEN 'SWEET_SPOT' THEN 3
            WHEN 'OVER_TARGET' THEN 4
            WHEN 'EXCESS' THEN 5
            WHEN 'AGGRESSIVE_EXCESS' THEN 6
            WHEN 'TB_INVENTORY' THEN 7
            ELSE 99
        END AS Ranking
    FROM classified c
)
SELECT
    ItemSku,
    WarehouseCode,
    SnapshotWeekEnding,
    -- FiscalWeekIndicator,
    SubStatus,
    Ranking,
    CASE MIN(Ranking) OVER (PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEnding)
        WHEN 0 THEN 'INACTIVE'
        WHEN 1 THEN 'SLOB'
        WHEN 2 THEN 'BELOW_TARGET'
        WHEN 3 THEN 'SWEET_SPOT'
        WHEN 4 THEN 'OVER_TARGET'
        WHEN 5 THEN 'EXCESS'
        WHEN 6 THEN 'AGGRESSIVE_EXCESS'
        WHEN 7 THEN 'TB_INVENTORY'
        ELSE 'UNCLASSIFIED'
    END AS [InventoryClassification Final Status],
    AvgWeeklyDemand AS [Avg Weekly Demand],
    SSTarget AS [SS target],
    OnHandsQty AS [On Hands Qty],
    OnOrderQty AS [On Order Qty],
    AFIStatus,
    LastInvoiceDate
FROM ranked;
