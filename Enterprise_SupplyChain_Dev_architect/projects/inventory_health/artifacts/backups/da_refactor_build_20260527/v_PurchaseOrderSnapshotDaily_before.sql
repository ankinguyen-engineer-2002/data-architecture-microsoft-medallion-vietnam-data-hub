-- ============================================================
-- §F. InventoryHistory_Enh — Tier 4 self-snapshots (4 views, datekey)
--     load_type='datekey'; Meta.usp_GenericLoad deletes today's rows then inserts.
--     Weekly snapshot (Logility) uses cron '0 6 * * 6' (Saturday 6AM UTC).
-- ============================================================

-- ---- InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_PurchaseOrderSnapshotDaily AS
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
          AND TRIM(podwarehouse) NOT IN ('C','CNW','AF','IOR','C35','55','MAX')
    ) r
    LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[PoMaster] h
           ON TRIM(h.pomordernum)  = r.PoNumber
          AND TRIM(h.pomvendornum) = r.VendorNumber
    WHERE r.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)         AS SnapshotDate,
    CAST(PoNumber                        AS VARCHAR(50))  AS PoNumber,
    CAST(PoLine                          AS INT)          AS PoLine,
    CAST(VendorNumber                    AS VARCHAR(50))  AS VendorNumber,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(StatusCode                      AS VARCHAR(10))  AS StatusCode,
    CAST(StockQty                        AS DECIMAL(18,4)) AS StockQty,
    CAST(OrderedQty                      AS DECIMAL(18,4)) AS OrderedQty,
    CAST(InTransitQtySource              AS DECIMAL(18,4)) AS InTransitQtySource,
    CAST(POOnOrderQty                    AS DECIMAL(18,4)) AS POOnOrderQty,
    CAST(POInTransitQty                  AS DECIMAL(18,4)) AS POInTransitQty,
    CAST(TotalOpenPOQty                  AS DECIMAL(18,4)) AS TotalOpenPOQty,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(EstimatedArrivalDate            AS DATE)         AS EstimatedArrivalDate,
    CAST(EstimatedDepartureDate          AS DATE)         AS EstimatedDepartureDate,
    CAST(SourceSystem                    AS VARCHAR(64))  AS SourceSystem,
    CAST(SourceTable                     AS VARCHAR(128)) AS SourceTable
FROM _PurchaseOrder