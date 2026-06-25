-- ---- InventoryHistory_Enh.v_CostCurrent ----
-- ITMRVA dedupe (STID+ITNBR, STID='000'). Pick latest by ITRV DESC.
CREATE VIEW InventoryHistory_Enh.v_CostCurrent AS
WITH ranked AS (
    SELECT
        TRIM(ITNBR)                          AS ItemSku,
        TRIM(STID)                           AS CostId,
        CAST(UCDEF AS DECIMAL(18,4))         AS StandardCost,
        CAST(ITRV  AS VARCHAR(20))           AS ItemRevision,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(STID), TRIM(ITNBR)
            ORDER BY ITRV DESC
        ) AS rn
    FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA]
    WHERE STID IS NOT NULL AND ITNBR IS NOT NULL
      AND TRIM(STID)  = '000'
      AND TRIM(ITNBR) <> ''
)
SELECT
    CAST(ItemSku       AS VARCHAR(50))    AS ItemSku,
    CAST(CostId        AS VARCHAR(10))    AS CostId,
    CAST(StandardCost  AS DECIMAL(18,4))  AS StandardCost,
    CAST(ItemRevision  AS VARCHAR(20))    AS ItemRevision,
    CAST('ItemMaster_AFI'     AS VARCHAR(64))   AS SourceSystem,
    CAST('ITMRVA(STID=000)'   AS VARCHAR(128))  AS SourceTable
FROM ranked
WHERE rn = 1

GO
