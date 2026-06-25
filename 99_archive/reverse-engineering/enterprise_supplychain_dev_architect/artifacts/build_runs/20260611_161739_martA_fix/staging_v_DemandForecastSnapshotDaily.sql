
CREATE   VIEW Staging_Wrk.v_DemandForecastSnapshotDaily AS
-- ============================================================
-- Cross-mart cleaned Bronze materialization (2026-05-22).
-- Source: EL.SupplyChain_Enh_1.DemandForecastSnapshotDaily (5.9B rows, dirty with row-dup x16 from Q1 2025)
-- Transform: ROW_NUMBER() OVER (full grain) = 1 dedupe.
-- Consumers: Mart A (ForecastHistory_Enh.v_ForecastDemandMonthly) + Mart B (InventoryHistory_Enh.v_ForecastSnapshotWeekly DA-first Saturday path)
-- Idempotent: if DE US fixes upstream dup, this dedupe becomes no-op (no harm).
-- ============================================================
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
  FROM [Enterprise_Lakehouse].[SupplyChain_Enh_1].[DemandForecastSnapshotDaily]
)
SELECT 
  dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
  dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
  dfcValidDemandMonths, dfcSnapshot,
  dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
  dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
  dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups,
  CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM dedupe
WHERE _rn = 1;
