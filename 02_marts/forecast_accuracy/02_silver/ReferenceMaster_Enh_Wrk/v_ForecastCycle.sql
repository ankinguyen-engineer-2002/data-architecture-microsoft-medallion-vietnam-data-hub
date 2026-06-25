-- SupplyChain_Processing_Warehouse.ReferenceMaster_Enh_Wrk.v_ForecastCycle
CREATE   VIEW [ReferenceMaster_Enh_Wrk].[v_ForecastCycle] AS
WITH __bob_source AS (
SELECT
    CAST(TRIM(src.[code_cycle]) AS VARCHAR(8000)) AS [CycleName],
    CAST(TRIM(src.[name_cycle_description]) AS VARCHAR(8000)) AS [CycleDescription],
    CAST(src.[dt_cycle_month_last] AS DATE) AS [CycleMonthLastDate],
    CAST(src.[dt_forecast_snapshot] AS DATE) AS [ForecastSnapshot],
    CAST(TRIM(src.[name_exception_note]) AS VARCHAR(8000)) AS [ExceptionNote],
    CAST(src.[ts_modified] AS DATETIME2(6)) AS [Modified],
    CAST(src.[ts_created] AS DATETIME2(6)) AS [Created]
FROM ProcessingSeed.ForecastCycle AS src
)
SELECT
    [CycleName] = src.[CycleName],
    [CycleDescription] = src.[CycleDescription],
    [CycleMonthLastDate] = src.[CycleMonthLastDate],
    [ForecastSnapshot] = src.[ForecastSnapshot],
    [ExceptionNote] = src.[ExceptionNote],
    [Modified] = src.[Modified],
    [Created] = src.[Created],
    [LoadDT] = CAST(SYSUTCDATETIME() AS datetime2(6))
FROM __bob_source AS src;
