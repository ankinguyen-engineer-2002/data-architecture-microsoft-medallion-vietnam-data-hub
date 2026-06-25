-- ---- InventoryHistory_Enh.v_SupplyPlan ----
CREATE VIEW InventoryHistory_Enh.v_SupplyPlan AS
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
              ELSE 0 END                            AS DECIMAL(18,4)) AS SINegQty,
    CAST('Wholesale_DemandPlanning_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('SupplyPlanDetail'              AS VARCHAR(128)) AS SourceTable
FROM [Enterprise_Lakehouse].[Wholesale_DemandPlanning_AFI].[SupplyPlanDetail]
WHERE spdItem IS NOT NULL AND spdWarehouse IS NOT NULL
  AND TRIM(spdItem) <> '' AND TRIM(spdWarehouse) <> ''

GO
