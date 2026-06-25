-- SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily
CREATE   VIEW [InventoryHistory_Enh_Wrk].[v_HoldingTransferSnapshotDaily] AS
WITH _HoldingTransfer AS (
    -- INLINED 2026-05-21 (Option B): was InventoryHistory_Enh.HoldingTransfer
    -- Reference: etl/Holding Transfers.sql.
    -- Business signal: same-warehouse transfer (HFHOUS = HTHOUS) is an on-hold candidate.
    -- Current metric keeps active/non-cancelled transfers for OnHoldQty compatibility.
    SELECT
        TransferNumber, ItemSku, WarehouseCode, SourceWarehouseCode, ReceivingWarehouseCode,
        ShipDateKey, ShipDate, ShipWeekEndingDate, DueDateKey, DueDate, DueWeekEndingDate,
        HeaderComment, DetailComment, TransferQty, ShippedQty, TotalShippedQty,
        ExpediteCode, FirmCode, TransferCube, HeaderStatus, CancelFlag
    FROM (
        SELECT
            TRIM(d.DTFRNO)                       AS TransferNumber,
            TRIM(d.DITNBR)                       AS ItemSku,
            TRIM(h.HFHOUS)                       AS WarehouseCode,
            TRIM(h.HFHOUS)                       AS SourceWarehouseCode,
            TRIM(h.HTHOUS)                       AS ReceivingWarehouseCode,
            CAST(h.HSHDTE AS INT)                AS ShipDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112) AS ShipDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HSHDTE), 112)) AS DATE) AS ShipWeekEndingDate,
            CAST(h.HDLDTE AS INT)                AS DueDateKey,
            TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112) AS DueDate,
            CAST(DATEADD(day,
                (7 - (DATEDIFF(day, CAST('19000106' AS DATE), TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) % 7)) % 7,
                TRY_CONVERT(DATE, CONVERT(VARCHAR(8), h.HDLDTE), 112)) AS DATE) AS DueWeekEndingDate,
            CAST(h.HTRCMT AS VARCHAR(200))       AS HeaderComment,
            CAST(d.DCOMNT AS VARCHAR(200))       AS DetailComment,
            CAST(d.DTFRQT AS DECIMAL(18,4))      AS TransferQty,
            CAST(d.DSHPQT AS DECIMAL(18,4))      AS ShippedQty,
            CAST(d.DTSHPQ AS DECIMAL(18,4))      AS TotalShippedQty,
            CAST(d.DEXPED AS VARCHAR(20))        AS ExpediteCode,
            CAST(d.DFIRMC AS VARCHAR(20))        AS FirmCode,
            CAST(d.DCUBES AS DECIMAL(18,4))      AS TransferCube,
            TRIM(h.HSTATS)                       AS HeaderStatus,
            TRIM(h.HCANCL)                       AS CancelFlag,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(d.DTFRNO), TRIM(d.DITNBR)
                ORDER BY h.HDLDTE DESC
            ) AS rn
        FROM [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRDTL] d
        JOIN [Enterprise_Lakehouse].[Manufacturing_Inventory_AFI].[TFRHDR] h
             ON TRIM(d.DTFRNO) = TRIM(h.HTFRNO)
        WHERE TRIM(h.HFHOUS) = TRIM(h.HTHOUS)
        --   AND TRIM(h.HCANCL) = 'N' 
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
    CAST(SourceWarehouseCode             AS VARCHAR(50))  AS SourceWarehouseCode,
    CAST(ReceivingWarehouseCode          AS VARCHAR(50))  AS ReceivingWarehouseCode,
    CAST(ShipDateKey                     AS INT)          AS ShipDateKey,
    CAST(ShipDate                        AS DATE)         AS ShipDate,
    CAST(ShipWeekEndingDate              AS DATE)         AS ShipWeekEndingDate,
    CAST(DueDateKey                      AS INT)          AS DueDateKey,
    CAST(DueDate                         AS DATE)         AS DueDate,
    CAST(DueWeekEndingDate               AS DATE)         AS DueWeekEndingDate,
    CAST(HeaderComment                   AS VARCHAR(200)) AS HeaderComment,
    CAST(DetailComment                   AS VARCHAR(200)) AS DetailComment,
    CAST(TransferQty                     AS DECIMAL(18,4)) AS TransferQty,
    CAST(ShippedQty                      AS DECIMAL(18,4)) AS ShippedQty,
    CAST(TotalShippedQty                 AS DECIMAL(18,4)) AS TotalShippedQty,
    CAST(ExpediteCode                    AS VARCHAR(20)) AS ExpediteCode,
    CAST(FirmCode                        AS VARCHAR(20)) AS FirmCode,
    CAST(TransferCube                    AS DECIMAL(18,4)) AS TransferCube,
    CAST(HeaderStatus                    AS VARCHAR(10))  AS HeaderStatus,
    CAST(CancelFlag                      AS VARCHAR(10))  AS CancelFlag,
    CAST('Manufacturing_Inventory_AFI'   AS VARCHAR(64))  AS SourceSystem,
    CAST('TFRDTL+TFRHDR'                 AS VARCHAR(128)) AS SourceTable,
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM _HoldingTransfer;
