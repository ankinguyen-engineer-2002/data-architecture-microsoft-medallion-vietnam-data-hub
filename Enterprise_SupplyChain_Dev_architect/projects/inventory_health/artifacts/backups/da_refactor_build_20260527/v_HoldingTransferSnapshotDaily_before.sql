-- ---- InventoryHistory_Enh.v_HoldingTransferSnapshotDaily ----
CREATE   VIEW InventoryHistory_Enh.v_HoldingTransferSnapshotDaily AS
WITH _HoldingTransfer AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.HoldingTransfer
    SELECT TransferNumber, ItemSku, WarehouseCode, TransferQty, ShippedQty, TransferCube, HeaderStatus, CancelFlag, ShipDateKey, DueDateKey
    FROM (
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
          AND TRIM(h.HCANCL) = 'N'
          AND d.DITNBR IS NOT NULL AND h.HFHOUS IS NOT NULL
          AND TRIM(d.DITNBR) <> '' AND TRIM(h.HFHOUS) <> ''
    ) ranked
    WHERE ranked.rn = 1
)
SELECT
    CAST(CAST(SYSUTCDATETIME() AS DATE)  AS DATE)        AS SnapshotDate,
    CAST(TransferNumber                  AS VARCHAR(50)) AS TransferNumber,
    CAST(ROW_NUMBER() OVER (PARTITION BY TransferNumber ORDER BY ItemSku) AS INT) AS TransferLine,
    CAST(ItemSku                         AS VARCHAR(50))  AS ItemSku,
    CAST(WarehouseCode                   AS VARCHAR(50))  AS WarehouseCode,
    CAST(TransferQty                     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty                      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TransferCube                    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus                    AS VARCHAR(10))  AS HeaderStatus,
    CAST('Manufacturing_Inventory_AFI'   AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                 AS VARCHAR(128)) AS SourceTable
FROM _HoldingTransfer