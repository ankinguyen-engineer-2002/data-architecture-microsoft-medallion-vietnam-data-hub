-- ReferenceMaster_Enh_Wrk.v_ForecastHorizon
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_ForecastHorizon] AS
WITH __bob_source AS (
SELECT
    CAST(TRIM(src.HorizonCode) AS VARCHAR(20)) AS HorizonCode,
    CAST(src.[Rank] AS INT) AS [Rank]
FROM ProcessingSeed.ForecastHorizon AS src
)
SELECT
    [HorizonCode] = src.[HorizonCode],
    [Rank] = src.[Rank],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
