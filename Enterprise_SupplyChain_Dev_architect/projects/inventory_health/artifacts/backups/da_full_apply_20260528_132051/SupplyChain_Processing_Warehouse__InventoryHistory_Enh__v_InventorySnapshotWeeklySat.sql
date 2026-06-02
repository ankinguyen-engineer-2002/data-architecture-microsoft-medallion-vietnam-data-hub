
CREATE   VIEW InventoryHistory_Enh.v_InventorySnapshotWeeklySat AS
-- 2026-05-26: Saturday weekly inventory snapshots derived from Daily, matching ForecastSnapshotWeeklySat pattern.
-- Note: no LoadDT in view; Meta.usp_GenericLoad appends LoadDT when materializing.
SELECT
    CAST(ItemSku AS VARCHAR(50)) AS ItemSku,
    CAST(WarehouseCode AS VARCHAR(50)) AS WarehouseCode,
    CAST(SnapshotDate AS DATE) AS SnapshotDate,
    CAST(FiscalMonth AS INT) AS FiscalMonth,
    CAST(FiscalMonthDate AS DATE) AS FiscalMonthDate,
    CAST(OnHandQty AS DECIMAL(18,4)) AS OnHandQty,
    CAST(SafetyStockTarget AS DECIMAL(18,4)) AS SafetyStockTarget,
    CAST(IOSafetyStock AS DECIMAL(18,4)) AS IOSafetyStock,
    CAST(OrderQty AS DECIMAL(18,4)) AS OrderQty,
    CAST(BuildQty AS DECIMAL(18,4)) AS BuildQty,
    CAST(ItemStatus AS VARCHAR(10)) AS ItemStatus,
    CAST(SourceLabel AS VARCHAR(50)) AS SourceLabel,
    CAST(SourceSystem AS VARCHAR(64)) AS SourceSystem,
    CAST(SourceTable AS VARCHAR(128)) AS SourceTable
FROM Staging_Wrk.v_DemandInventorySnapshotDailySatClean;
