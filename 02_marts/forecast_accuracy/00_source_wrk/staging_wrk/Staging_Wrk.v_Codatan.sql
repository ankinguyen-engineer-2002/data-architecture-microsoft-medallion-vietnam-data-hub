-- 04_create_renamed_views_processing.sql
-- 28 Processing views recreated with new schema (_Enh/_Wrk) and v_ prefix.
-- Source: etl/staging_ddl.sql + etl/silver_views.sql, transformed.

-- ============== Staging views ==============
-- ============================================================
-- Staging_Wrk Views — Raw EDW Projection
-- ============================================================
-- Layer: Staging. Pattern: TRIM strings, TRY_CONVERT dates, PascalCase aliases. No JOIN.
-- Source: SupplyChain_Processing_Warehouse
-- Generated from live workspace scan (2026-05-06)
-- ============================================================

-- ---- Staging_Wrk.v_Codatan ----
CREATE VIEW Staging_Wrk.v_Codatan AS
SELECT
    TRIM(ORDNO) AS OrderID, TRIM(ITNBR) AS ItemSKU, TRIM(HOUSE) AS WarehouseCode,
    CAST(ITMSQ AS INT) AS ItemSequenceNum,
    CAST(COQTY AS DECIMAL(12,3)) AS QtyOrdered, CAST(QTYSH AS DECIMAL(12,3)) AS QtyShipped,
    CAST(QTYBO AS DECIMAL(12,3)) AS QtyBackordered,
    CAST(INSAM AS DECIMAL(12,2)) AS AmtExtendedSelling,
    CAST(PRICE AS DECIMAL(12,4)) AS AmtSellingPrice,
    TRY_CONVERT(DATE, CAST(CAST(RQIDT AS BIGINT) AS VARCHAR(20))) AS RequestedDate,
    TRY_CONVERT(DATE, CAST(CAST(MFIDT AS BIGINT) AS VARCHAR(20))) AS ManufacturedDate,
    TRIM(CCUSNO) AS Customer, TRIM(CSHPNO) AS ShipToCode,
    TRIM(ITDSC) AS ItemDescriptionName, TRIM(ITDSI) AS ItemDescriptionShortName,
    CAST(IAFLG AS VARCHAR(200)) AS AllocationFlagCode,
    CAST(NUMLDDTCHG AS INT) AS LoadDateChanges
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan WHERE ORDNO IS NOT NULL

GO
