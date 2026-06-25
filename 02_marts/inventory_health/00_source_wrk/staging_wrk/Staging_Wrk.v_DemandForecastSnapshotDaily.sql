CREATE   VIEW Staging_Wrk.v_DemandForecastSnapshotDaily AS
-- ============================================================
-- Cross-mart cleaned Bronze source wrapper (canonicalized 2026-06-23).
-- Source: EL.SupplyChain_Enh.DemandForecastSnapshotDaily.
-- Transform: ROW_NUMBER() OVER (full grain) = 1 dedupe.
-- Enterprise ETL contract: include LoadDT so usp_IncrementalTableLoad source columns match target columns.
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
  FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandForecastSnapshotDaily]
)
SELECT
  dfcItem, dfcWarehouse, dfcFiscalMonth, dfcMainPiece, dfcCollectiveClass,
  dfcResultantForecast, dfcPromotionalLift, dfcForcedForecast,
  dfcValidDemandMonths, dfcSnapshot,
  dfcPermComptQty, dfcUsr25Text, dfcUsr32Text,
  dfcFCSTTypeCode, dfcDerivedFCSTID, dfcDerivedFCSTFctr, dfcOrderFutureQty,
  dfcMgmtCode, usra, dtea, usrc, dtec, DfcCustomerGroups,
  CAST(SYSUTCDATETIME() AS datetime2(6)) AS LoadDT
FROM dedupe
WHERE _rn = 1;

GO
