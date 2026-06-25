
CREATE OR ALTER VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical AS
-- Source: SC_LH.dbo.purchaseordersnapshot loaded via df_brz_PurchaseOrderSnapshot (DF2 workaround, 2B rows ⚠️)
-- Grain: (SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode)
-- Phase 2 PO-as-of feature: capture historical PO state by SnapshotDate
-- posDueDt is AS/400 CYYMMDD decimal (e.g., 1230130 = 2023-01-30)
WITH _PurchaseOrder AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.PurchaseOrder
    SELECT
        r.PoNumber, r.PoLine, r.VendorNumber, r.ItemSku, r.WarehouseCode,
        r.StatusCode, r.StockQty, r.OrderedQty, r.InTransitQtySource, r.DueDate,
        CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
        CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
        CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
        CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
        CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
        CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
        CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
        CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
        CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
        CAST('PoDetail+PoMaster (Enterprise)'        AS VARCHAR(128)) AS SourceTable
    FROM (
        SELECT
            TRIM(podordernum)                          AS PoNumber,
            CAST(poditemsequence AS INT)               AS PoLine,
            TRIM(podvendornum)                         AS VendorNumber,
            TRIM(poditemnum)                           AS ItemSku,
            TRIM(podwarehouse)                         AS WarehouseCode,
            CAST(podstatuscode  AS VARCHAR(10))        AS StatusCode,
            CAST(podstockqty    AS DECIMAL(18,4))      AS StockQty,
            CAST(podqtyordered  AS DECIMAL(18,4))      AS OrderedQty,
            CAST(podIntransitQty AS DECIMAL(18,4))     AS InTransitQtySource,
            CAST(podduedate     AS DATE)               AS DueDate,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(podordernum), TRIM(podvendornum), poditemsequence
                ORDER BY podduedate DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]
        WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL

    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
    
    WHERE r.rn = 1
)
SELECT
    CAST(posSnapshot AS DATE)                                 AS SnapshotDate,
    CAST(TRIM(posItNbr)             AS VARCHAR(50))           AS ItemSku,
    CAST(TRIM(posWhse)              AS VARCHAR(50))           AS WarehouseCode,
    CAST(TRIM(posVndnr)             AS VARCHAR(50))           AS VendorNumber,
    CAST(posQtyOr                   AS DECIMAL(18,4))         AS OrderedQty,
    CAST(TRIM(posPstts)             AS VARCHAR(10))           AS StatusCode,
    CAST(
        TRY_CAST(
            DATEFROMPARTS(
                1900 + 100 * (TRY_CAST(posDueDt AS INT) / 1000000) + ((TRY_CAST(posDueDt AS INT) % 1000000) / 10000),
                (TRY_CAST(posDueDt AS INT) % 10000) / 100,
                TRY_CAST(posDueDt AS INT) % 100
            ) AS DATE)                                        AS DATE)              AS DueDate,
    CAST(posUUD1PM                  AS DECIMAL(18,4))         AS UnitCost,
    CAST('SupplyChain_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('dbo.purchaseordersnapshot (DF2)'        AS VARCHAR(128)) AS SourceTable
FROM [SupplyChain_Lakehouse].[dbo].[purchaseordersnapshot]
WHERE posItNbr IS NOT NULL AND posWhse IS NOT NULL
  AND TRIM(posItNbr) <> '' AND TRIM(posWhse) <> ''
