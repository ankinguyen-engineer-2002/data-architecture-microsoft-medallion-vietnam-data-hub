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

-- ---- Staging_Wrk.v_Comast ----
CREATE VIEW Staging_Wrk.v_Comast AS
SELECT TRIM(ORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(ORDTE AS BIGINT) AS VARCHAR(20))) AS OrderDate,
    CAST(SHLTC AS INT) AS LeadTimeDays, TRIM(SHINS) AS ShippingInstructionsName,
    TRIM(ACREC) AS RecordTypeCode
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST

GO

-- ---- Staging_Wrk.v_Extord ----
CREATE VIEW Staging_Wrk.v_Extord AS
SELECT TRIM(XORDNO) AS OrderID,
    TRY_CONVERT(DATE, CAST(CAST(FRZDAT AS BIGINT) AS VARCHAR(20))) AS FreezeDate,
    TRY_CONVERT(DATE, CAST(CAST(RQSDAT AS BIGINT) AS VARCHAR(20))) AS RequestedShipDate,
    TRIM(ORDARR) AS OrderArrangementCode,
    TRIM(OTTYP1) AS OrderType1Code, TRIM(OTTYP2) AS OrderType2Code,
    TRIM(OTTYP3) AS OrderType3Code, TRIM(OTTYP4) AS OrderType4Code
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD

GO

-- ---- Staging_Wrk.v_Extorit ----
CREATE VIEW Staging_Wrk.v_Extorit AS
SELECT TRIM(IORD) AS OrderID, CAST(ISEQ AS INT) AS ItemSequenceNum,
    CAST(IFRGHT AS DECIMAL(12,2)) AS AmtFreight,
    TRY_CONVERT(DATE, CAST(CAST(IPRMDT AS BIGINT) AS VARCHAR(20))) AS PromiseDate
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT

GO


-- ============================================================
-- 2026-05-22 NEW: Staging_Wrk.DemandForecastSnapshotDaily
-- ============================================================
-- CROSS-MART cleaned Bronze materialization (shared by forecast + inventory_health marts).
-- Source:    Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
--             (5.89B rows, dirty with row-dup x16 from Q1 2025)
-- Transform: ROW_NUMBER() OVER (full grain) = 1 dedupe.
-- Result:    5.53B clean rows (-6% via dedup).
-- Pattern:   Land-and-clean intermediate layer.
--            Insulates downstream marts from upstream Logility dup quality issue.
-- Idempotent: if DE US fixes upstream dup, this dedupe becomes no-op (no harm).
-- Consumers:
--   • forecast: ForecastHistory_Enh.v_ForecastDemandMonthly (was reading EL.Daily directly)
--   • inventory_health: InventoryHistory_Enh.v_ForecastSnapshotWeekly (DA-first Saturday path)

-- ---- Staging_Wrk.v_DemandForecastSnapshotDaily (dedupe view) ----
-- NOTE: keep this view free of LoadDT; Meta.usp_GenericLoad appends LoadDT when materializing the physical table.
CREATE VIEW Staging_Wrk.v_DemandForecastSnapshotDaily AS
WITH dedupe AS (
  SELECT
    dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
    dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
    dfcValidDemandMonths, dfcSnapshot,
    dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
    dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
    dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups,
    ROW_NUMBER() OVER (
      PARTITION BY dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot,
                   DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode
      ORDER BY (SELECT NULL)
    ) AS _rn
  FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandForecastSnapshotDaily]
)
SELECT
  dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
  dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
  dfcValidDemandMonths, dfcSnapshot,
  dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
  dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
  dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups
FROM dedupe
WHERE _rn = 1

GO

-- ---- Staging_Wrk.DemandForecastSnapshotDaily (materialized table — CTAS by pl_sc_staging) ----
-- CREATE TABLE Staging_Wrk.DemandForecastSnapshotDaily AS SELECT * FROM Staging_Wrk.v_DemandForecastSnapshotDaily;
-- Initial backfill 2026-05-22: 5,530,726,784 rows materialized in ~12 min.
-- Future runs: incremental by dfcSnapshot watermark via usp_GenericLoad.
GO
