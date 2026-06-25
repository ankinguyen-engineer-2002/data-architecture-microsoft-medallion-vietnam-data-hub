-- SupplyChain_Processing_Warehouse.ReferenceMaster_Enh_Wrk.v_ForecastHorizon
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_ForecastHorizon] AS
SELECT
    CAST(TRIM(src.HorizonCode) AS VARCHAR(20)) AS HorizonCode,
    CAST(src.[Rank] AS INT) AS [Rank],
    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]
FROM ProcessingSeed.ForecastHorizon AS src;
