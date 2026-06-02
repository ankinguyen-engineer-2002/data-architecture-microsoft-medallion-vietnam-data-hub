-- ---- InventoryHealth_DW.v_FactInventoryRiskForward ----
-- Grain: (ItemSku, WarehouseCode, WeekEndingDate)
-- Source: _SupplyPlan (latest snapshot per WeekEnding) + AtpWeekEnding (Week2) + AllocatedDemand
-- H5 FIX (2026-05-17): WeekFourFlag = exact week-4 ending only (Saturday + 28 days). Robert sign-off pending.
CREATE VIEW InventoryHealth_DW.v_FactInventoryRiskForward AS
WITH _SupplyPlan AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.SupplyPlan
    SELECT
        CAST(TRIM(spdItem)                              AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(spdWarehouse)                         AS VARCHAR(50))   AS WarehouseCode,
        CAST(dtea                                       AS DATE)          AS SnapshotDate,
        CAST(spdWeekEnding                              AS DATE)          AS WeekEndingDate,
        CAST(spdBeginingBalance                         AS DECIMAL(18,4)) AS BeginningBalanceQty,
        CAST(spdFirmDemands                             AS DECIMAL(18,4)) AS FirmDemandQty,
        CAST(spdNetForecast                             AS DECIMAL(18,4)) AS NetForecastQty,
        CAST(spdFirmPurchaseOrders                      AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
        CAST(spdPlannedPurchaseOrders                   AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
        CAST(spdOnOrderTransferIn                       AS DECIMAL(18,4)) AS OnOrderTransferInQty,
        CAST(spdShippableInventory                      AS DECIMAL(18,4)) AS ShippableInventoryQty,
        CAST(spdSafetyStock                             AS DECIMAL(18,4)) AS SafetyStockTargetQty,
        CAST(spdMonthsOfSupply                          AS DECIMAL(18,4)) AS MonthsOfSupply,
        CAST(CASE WHEN spdShippableInventory < 0
                  THEN ABS(CAST(spdShippableInventory AS DECIMAL(18,4)))
                  ELSE 0 END                            AS DECIMAL(18,4)) AS SINegQty
    FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
    WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
      AND TRIM(spdItem) <> '' AND TRIM(spdWarehouse) <> ''
),
_AtpWeekEnding AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.AtpWeekEnding
    SELECT
        u.ItemSku, u.WarehouseCode, u.WeekNumber,
        CAST(DATEADD(week, u.WeekNumber - 1, b.BaseWeekEndingDate) AS DATE) AS WeekEndingDate,
        u.AtpQty
    FROM (
        SELECT
            TRIM(APITNB) AS ItemSku, TRIM(APHOUS) AS WarehouseCode,
            CAST(REPLACE(WeekCol, 'APAT', '') AS INT) AS WeekNumber,
            CAST(AtpQty AS DECIMAL(18,4)) AS AtpQty
        FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
        UNPIVOT (AtpQty FOR WeekCol IN (
            APAT01,APAT02,APAT03,APAT04,APAT05,APAT06,APAT07,APAT08,APAT09,APAT10,
            APAT11,APAT12,APAT13,APAT14,APAT15,APAT16,APAT17,APAT18,APAT19,APAT20,
            APAT21,APAT22,APAT23,APAT24,APAT25,APAT26,APAT27,APAT28,APAT29,APAT30,
            APAT31,APAT32,APAT33,APAT34,APAT35,APAT36,APAT37,APAT38,APAT39,APAT40,
            APAT41,APAT42,APAT43
        )) un
    ) u
    JOIN (
        SELECT TRIM(APITNB) AS ItemSku, TRIM(APHOUS) AS WarehouseCode,
               TRY_CAST(CAST(CAST(APWK01 AS BIGINT) AS VARCHAR(8)) AS DATE) AS BaseWeekEndingDate
        FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
        WHERE APITNB IS NOT NULL AND APHOUS IS NOT NULL
          AND TRIM(APITNB) <> '' AND TRIM(APHOUS) <> ''
    ) b ON b.ItemSku = u.ItemSku AND b.WarehouseCode = u.WarehouseCode
    WHERE b.BaseWeekEndingDate IS NOT NULL
),
_AllocatedDemandCandidate AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.AllocatedDemandCandidate
    SELECT
        CAST(TRIM(d.ItemSKU)             AS VARCHAR(50))   AS ItemSku,
        CAST(TRIM(d.Warehouse)           AS VARCHAR(50))   AS WarehouseCode,
        CAST(d.QuantityBackOrdered       AS DECIMAL(18,4)) AS AllocatedDemandQty
    FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
    WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
      AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
      AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
      AND TRIM(d.ItemSKU) <> '' AND TRIM(d.Warehouse) <> ''
),
_ItemMasterExt AS (
    -- 2026-05-29: Shared product contract; single source for item lifecycle, price, cube, vendor, and unavailable flags.
    SELECT
        CAST(ItemSKU AS VARCHAR(50)) AS ItemSku,
        CAST(ItemDescription AS VARCHAR(200)) AS ItemDescription,
        CAST(ItemClassCode AS VARCHAR(50)) AS ItemClassCode,
        CAST(ItemClassName AS VARCHAR(100)) AS ItemClassName,
        CAST(CategoryName AS VARCHAR(100)) AS CategoryName,
        CAST(CategoryCode AS VARCHAR(50)) AS CategoryCode,
        CAST(CollectiveClass AS VARCHAR(50)) AS CollectiveClass,
        CAST(SeriesNumber AS VARCHAR(50)) AS SeriesNumber,
        CAST(SeriesName AS VARCHAR(100)) AS SeriesName,
        CAST(SeriesDescription AS VARCHAR(200)) AS SeriesDescription,
        CAST(AfiItemStatus AS VARCHAR(10)) AS AfiItemStatus,
        CAST(PrimaryVendorNumber AS VARCHAR(50)) AS PrimaryVendorNumber,
        CAST(PrimaryVendorDisplayName AS VARCHAR(200)) AS PrimaryVendorName,
        CAST(Cubes AS DECIMAL(18,4)) AS Cubes,
        CAST(FOBArcPrice AS DECIMAL(18,4)) AS FobArcPrice,
        CAST(IsFinishedGoodsItem AS BIT) AS IsFinishedGoodsItem,
        CAST(DiscontinuedFlag AS BIT) AS DiscontinuedFlag,
        CAST(NewItemFlag AS BIT) AS NewItemFlag,
        CAST(StatusCodeChangeDate AS DATE) AS StatusCodeChangeDate,
        CAST(UnavailableFlag AS BIT) AS UnavailableFlag
    FROM Shared_DW.DimProduct
),
latest_plan AS (
    SELECT
        ItemSku, WarehouseCode, WeekEndingDate,
        BeginningBalanceQty, FirmDemandQty, NetForecastQty,
        FirmPurchaseOrderQty, PlannedPurchaseOrderQty,
        OnOrderTransferInQty, ShippableInventoryQty,
        SafetyStockTargetQty, MonthsOfSupply, SINegQty,
        ROW_NUMBER() OVER (
            PARTITION BY ItemSku, WarehouseCode, WeekEndingDate
            ORDER BY SnapshotDate DESC
        ) AS rn
    FROM _SupplyPlan
),
atp_w2 AS (
    SELECT ItemSku, WarehouseCode, AtpQty
    FROM _AtpWeekEnding
    WHERE WeekNumber = 2
),
alloc AS (
    SELECT
        ItemSku, WarehouseCode,
        SUM(AllocatedDemandQty) AS AllocatedDemandQty
    FROM _AllocatedDemandCandidate
    GROUP BY ItemSku, WarehouseCode
)
SELECT
    CAST(lp.ItemSku            AS VARCHAR(50))   AS ItemSku,
    CAST(lp.WarehouseCode      AS VARCHAR(50))   AS WarehouseCode,
    CAST(lp.WeekEndingDate     AS DATE)          AS WeekEndingDate,
    CAST(d.DateSK              AS INT)           AS DateKey,    -- FIX 2026-05-19: DimCalendar (Gold) uses DateSK
    CAST(lp.BeginningBalanceQty       AS DECIMAL(18,4)) AS BeginningBalanceQty,
    CAST(lp.FirmDemandQty             AS DECIMAL(18,4)) AS FirmDemandQty,
    CAST(lp.NetForecastQty            AS DECIMAL(18,4)) AS NetForecastQty,
    CAST(lp.FirmPurchaseOrderQty      AS DECIMAL(18,4)) AS FirmPurchaseOrderQty,
    CAST(lp.PlannedPurchaseOrderQty   AS DECIMAL(18,4)) AS PlannedPurchaseOrderQty,
    CAST(lp.OnOrderTransferInQty      AS DECIMAL(18,4)) AS OnOrderTransferInQty,
    CAST(lp.ShippableInventoryQty     AS DECIMAL(18,4)) AS ShippableInventoryQty,
    CAST(lp.SafetyStockTargetQty      AS DECIMAL(18,4)) AS SafetyStockTargetQty,
    CAST(lp.MonthsOfSupply            AS DECIMAL(18,4)) AS MonthsOfSupply,
    -- 14-day demand/inbound derived
    CAST(lp.FirmDemandQty * (14.0/7.0)                                 AS DECIMAL(18,4)) AS ExpectedDemand14DQty,
    CAST((lp.FirmPurchaseOrderQty + lp.OnOrderTransferInQty) * (14.0/7.0) AS DECIMAL(18,4)) AS Inbound14DQty,
    CAST(ISNULL(al.AllocatedDemandQty, 0)        AS DECIMAL(18,4))      AS AllocatedDemandQty,
    CAST(ISNULL(at.AtpQty, 0)                    AS DECIMAL(18,4))      AS ATPQty,
    CAST(CASE WHEN ISNULL(at.AtpQty, 0) > 0 THEN 1 ELSE 0 END AS BIT)   AS ATPInStockFlag,
    CAST(CASE WHEN lp.ShippableInventoryQty > 0 THEN 1 ELSE 0 END AS BIT) AS ShippableInStockFlag,
    CAST(lp.SINegQty                             AS DECIMAL(18,4))      AS SINegQty,
    CAST(lp.SINegQty * ISNULL(dim.FobArcPrice, 0) AS DECIMAL(18,4))     AS RevenueAtRiskValue,
    -- H5 FIX (2026-05-17): exact week-4 ending only (Saturday + 28 days).
    -- BRD §6.3 "At Week Four Ending" = single week. Robert sign-off pending.
    CAST(CASE WHEN lp.WeekEndingDate = (
                  DATEADD(day,
                          ((7 - DATEPART(weekday, SYSUTCDATETIME()) + 7) % 7) + 28,
                          CAST(SYSUTCDATETIME() AS DATE))
              )
              THEN 1 ELSE 0 END AS BIT)                                 AS WeekFourFlag,
    CAST(dim.FobArcPrice                         AS DECIMAL(18,4))      AS FobArcPrice,
    CAST(1                                       AS BIGINT)             AS RuleVersionKey
FROM latest_plan lp
LEFT JOIN [SupplyChain_Gold_Warehouse].[Shared_DW].[DimCalendar] d
       ON d.[Date] = lp.WeekEndingDate
LEFT JOIN _ItemMasterExt dim
       ON dim.ItemSku = lp.ItemSku
LEFT JOIN atp_w2 at  ON at.ItemSku=lp.ItemSku AND at.WarehouseCode=lp.WarehouseCode
LEFT JOIN alloc al   ON al.ItemSku=lp.ItemSku AND al.WarehouseCode=lp.WarehouseCode
WHERE lp.rn = 1