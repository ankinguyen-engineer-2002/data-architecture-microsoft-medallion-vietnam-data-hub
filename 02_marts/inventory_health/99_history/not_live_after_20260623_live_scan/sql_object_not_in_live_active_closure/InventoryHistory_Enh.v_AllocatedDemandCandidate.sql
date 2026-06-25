-- ---- InventoryHistory_Enh.v_AllocatedDemandCandidate ----
-- H1 FIX (2026-05-17): ItemAllocationFlag = 2 (not 1). Probe: {0:16,802; 2:901,411 rows}.
-- Robert sign-off pending — see 99_archive/reverse-engineering/enterprise_supplychain_dev_architect/projects/inventory_health/docs/open_questions_for_enterprise_etl.md.
CREATE VIEW InventoryHistory_Enh.v_AllocatedDemandCandidate AS
SELECT
    CAST(TRIM(d.OrderNumber)         AS VARCHAR(50))   AS OrderNumber,
    CAST(ROW_NUMBER() OVER (
        PARTITION BY TRIM(d.OrderNumber)
        ORDER BY d.LoadDate DESC, d.PromiseDate DESC
    )                                AS INT)           AS OrderLine,
    CAST(TRIM(d.ItemSKU)             AS VARCHAR(50))   AS ItemSku,
    CAST(TRIM(d.Warehouse)           AS VARCHAR(50))   AS WarehouseCode,
    CAST(d.PromiseDate               AS DATE)          AS PromiseDate,
    CAST(d.LoadDate                  AS DATE)          AS LoadDate,
    CAST(d.MaterialRequestDate       AS DATE)          AS MaterialRequestDate,
    CAST(d.QuantityBackOrdered       AS DECIMAL(18,4)) AS AllocatedDemandQty,
    CAST(d.QuantityShipped           AS DECIMAL(18,4)) AS QuantityShipped,
    CAST(d.ItemAllocationFlag        AS DECIMAL(18,4)) AS ItemAllocationFlag,
    CAST(TRIM(h.CustomerNumber)      AS VARCHAR(50))   AS CustomerNumber,
    CAST(h.OrderDate                 AS DATE)          AS OrderDate,
    CAST('CustomerOrders_AFI'        AS VARCHAR(64))   AS SourceSystem,
    CAST('OpenOrderDetail+Header'    AS VARCHAR(128))  AS SourceTable
FROM [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderDetail] d
LEFT JOIN [Enterprise_Lakehouse].[CustomerOrders_AFI].[OpenOrderHeader] h
       ON TRIM(h.OrderNumber) = TRIM(d.OrderNumber)
-- H1 FIX: ItemAllocationFlag = 2 means "Allocated". Robert sign-off pending.
WHERE CAST(d.ItemAllocationFlag AS DECIMAL(18,4)) = 2
  AND ISNULL(CAST(d.QuantityShipped AS DECIMAL(18,4)), 0) = 0
  AND d.ItemSKU IS NOT NULL AND d.Warehouse IS NOT NULL
  AND TRIM(d.ItemSKU) <> '' AND TRIM(d.Warehouse) <> ''

GO
