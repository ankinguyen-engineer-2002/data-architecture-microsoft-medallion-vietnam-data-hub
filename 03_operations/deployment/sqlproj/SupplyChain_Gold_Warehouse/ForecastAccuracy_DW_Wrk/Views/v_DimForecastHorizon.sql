-- ForecastAccuracy_DW_Wrk.v_DimForecastHorizon
CREATE   VIEW [ForecastAccuracy_DW_Wrk].[v_DimForecastHorizon] AS
WITH __bob_source AS (
SELECT HorizonCode, [Rank], CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon
)
SELECT
    [HorizonCode] = src.[HorizonCode],
    [Rank] = src.[Rank],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
