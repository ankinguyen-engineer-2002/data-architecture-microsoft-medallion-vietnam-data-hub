CREATE VIEW ForecastAccuracy_DW.vw_DimForecastHorizon AS
SELECT HorizonCode, CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_ENH.ForecastHorizon