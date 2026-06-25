-- ---- InventoryHistory_Enh.v_PurchaseOrder ----
-- B1 FIX (2026-05-17): switched source SupplyChain.dbo.podetail_v2 → Enterprise.PoDetail (21.95M rows).
-- B1.2 FIX (2026-05-19): Dhivya loaded Enterprise.PoMaster (5.69M rows, 75 cols) — switched LEFT JOIN from SC_LH.dbo.pomaster → Enterprise.PoMaster. SC_LH.dbo.pomaster legacy path can be deprecated.
-- DA Silver_Check 2026-05-28: keep direct-to-customer/RP warehouses in PO source.
-- DEDUPE: PoDetail has 1 verified true-dup pair (Key 'P0SM242'|'612908'|1 — all 53 cols identical); ROW_NUMBER drops safely.
CREATE VIEW InventoryHistory_Enh.v_PurchaseOrder AS
WITH ranked AS (
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
    FROM [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoDetail]  -- B1 FIX: Enterprise (was SC.podetail_v2)
    WHERE poditemnum IS NOT NULL AND podwarehouse IS NOT NULL
      AND TRIM(poditemnum) <> '' AND TRIM(podwarehouse) <> ''
)
SELECT
    CAST(r.PoNumber             AS VARCHAR(50))   AS PoNumber,
    CAST(r.PoLine               AS INT)           AS PoLine,
    CAST(r.VendorNumber         AS VARCHAR(50))   AS VendorNumber,
    CAST(r.ItemSku              AS VARCHAR(50))   AS ItemSku,
    CAST(r.WarehouseCode        AS VARCHAR(50))   AS WarehouseCode,
    CAST(r.StatusCode           AS VARCHAR(10))   AS StatusCode,
    CAST(r.StockQty             AS DECIMAL(18,4)) AS StockQty,
    CAST(r.OrderedQty           AS DECIMAL(18,4)) AS OrderedQty,
    CAST(r.InTransitQtySource   AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(r.DueDate              AS DATE)          AS DueDate,
    CAST(CASE WHEN r.StatusCode = '10' THEN r.StockQty           ELSE 0 END AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(CASE WHEN r.StatusCode = '20' THEN r.InTransitQtySource ELSE 0 END AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(CASE WHEN TRY_CAST(r.StatusCode AS INT) < 50 THEN r.StockQty ELSE 0 END AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(h.pometa            AS DATE)             AS EstimatedArrivalDate,
    CAST(h.pometd            AS DATE)             AS EstimatedDepartureDate,
    CAST(h.pomdue            AS DATE)             AS PromisedReceiptDate,
    CAST(h.pomcontainer      AS VARCHAR(50))      AS ContainerNumber,
    CAST(h.pomtotalcubes     AS DECIMAL(18,4))    AS TotalCubes,
    CAST('Enterprise_Lakehouse'                  AS VARCHAR(64))  AS SourceSystem,
    CAST('PoDetail+PoMaster (both Enterprise)'   AS VARCHAR(128)) AS SourceTable
FROM ranked r
-- B1.2 FIX 2026-05-19: switched from SC_LH.dbo.pomaster → Enterprise.PoMaster after Dhivya load
LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
       ON TRIM(h.pomordernum)  = r.PoNumber
WHERE r.rn = 1

GO
