-- ForecastAccuracy_DW_Wrk.v_DimForecastHorizon
CREATE   VIEW [ForecastAccuracy_DW_Wrk].[v_DimForecastHorizon] AS
SELECT HorizonCode, [Rank], CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon;
