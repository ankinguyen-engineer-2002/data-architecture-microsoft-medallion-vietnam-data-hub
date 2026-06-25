-- ---- InventoryHistory_Enh.v_HoldingTransfer ----
-- TFRDTL + TFRHDR. Same-warehouse holding transfers.
-- DA Silver_Check 2026-05-28: keep cancelled rows; expose CancelFlag for downstream logic.
CREATE VIEW InventoryHistory_Enh.v_HoldingTransfer AS
WITH ranked AS (
    SELECT
        TRIM(d.DTFRNO)                       AS TransferNumber,
        TRIM(d.DITNBR)                       AS ItemSku,
        TRIM(h.HFHOUS)                       AS WarehouseCode,
        CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
        CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
        CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
        TRIM(h.HSTATS)                       AS HeaderStatus,
        TRIM(h.HCANCL)                       AS CancelFlag,
        CAST(h.HSHDTE AS INT)                AS ShipDateKey,
        CAST(h.HDLDTE AS INT)                AS DueDateKey,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
            ORDER BY h.HDLDTE DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
    JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
         ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
    WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
      AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
      AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
)
SELECT
    CAST(TransferNumber  AS VARCHAR(50))   AS TransferNumber,
    CAST(ItemSku         AS VARCHAR(50))   AS ItemSku,
    CAST(WarehouseCode   AS VARCHAR(50))   AS WarehouseCode,
    CAST(TransferQty     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TransferCube    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus    AS VARCHAR(10))   AS HeaderStatus,
    CAST(CancelFlag      AS VARCHAR(5))    AS CancelFlag,
    CAST(ShipDateKey     AS INT)           AS ShipDateKey,
    CAST(DueDateKey      AS INT)           AS DueDateKey,
    CAST('Manufacturing_Inventory_AFI'  AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                AS VARCHAR(128)) AS SourceTable
FROM ranked WHERE rn = 1

GO
