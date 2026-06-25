-- ---- InventoryHistory_Enh.v_AtpWeekEnding ----
-- H2 FIX (2026-05-17): UNPIVOT only APAT01-43 (APWK columns don't exist as series).
-- Derive WeekEndingDate = BaseWeekEnding (APWK01) + (WeekNumber - 1) weeks.
CREATE VIEW InventoryHistory_Enh.v_AtpWeekEnding AS
WITH base AS (
    SELECT
        TRIM(APITNB)                                                  AS ItemSku,
        TRIM(APHOUS)                                                  AS WarehouseCode,
        TRY_CAST(CAST(CAST(APWK01 AS BIGINT) AS VARCHAR(8)) AS DATE)  AS BaseWeekEndingDate
    FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
    WHERE APITNB IS NOT NULL AND APHOUS IS NOT NULL
      AND TRIM(APITNB) <> '' AND TRIM(APHOUS) <> ''
),
unpiv AS (
    SELECT
        TRIM(APITNB)                          AS ItemSku,
        TRIM(APHOUS)                          AS WarehouseCode,
        CAST(REPLACE(WeekCol, 'APAT', '') AS INT) AS WeekNumber,
        CAST(AtpQty AS DECIMAL(18,4))         AS AtpQty
    FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[ATPSUM]
    UNPIVOT (AtpQty FOR WeekCol IN (
        APAT01,APAT02,APAT03,APAT04,APAT05,APAT06,APAT07,APAT08,APAT09,APAT10,
        APAT11,APAT12,APAT13,APAT14,APAT15,APAT16,APAT17,APAT18,APAT19,APAT20,
        APAT21,APAT22,APAT23,APAT24,APAT25,APAT26,APAT27,APAT28,APAT29,APAT30,
        APAT31,APAT32,APAT33,APAT34,APAT35,APAT36,APAT37,APAT38,APAT39,APAT40,
        APAT41,APAT42,APAT43
    )) u
)
SELECT
    CAST(u.ItemSku        AS VARCHAR(50))   AS ItemSku,
    CAST(u.WarehouseCode  AS VARCHAR(50))   AS WarehouseCode,
    CAST(u.WeekNumber     AS INT)           AS WeekNumber,
    CAST(DATEADD(week, u.WeekNumber - 1, b.BaseWeekEndingDate) AS DATE) AS WeekEndingDate,
    CAST(u.AtpQty         AS DECIMAL(18,4)) AS AtpQty,
    CAST('Wholesale_Purchasing_AFI'    AS VARCHAR(64))  AS SourceSystem,
    CAST('ATPSUM(UNPIVOT APAT01-43)'   AS VARCHAR(128)) AS SourceTable
FROM unpiv u
JOIN base b ON b.ItemSku = u.ItemSku AND b.WarehouseCode = u.WarehouseCode
WHERE b.BaseWeekEndingDate IS NOT NULL

GO
