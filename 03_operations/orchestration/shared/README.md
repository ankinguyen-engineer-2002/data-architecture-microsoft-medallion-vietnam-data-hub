# Shared Orchestration Procedures

Shared prereq SPs for 10-step full mart refresh.

Run before mart-specific Silver waves:

1. `dbo.Usp_Refresh_Shared_ReferenceMaster`
2. `dbo.Usp_Refresh_Shared_Staging`

Both use `[ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]` overwrite pattern for now. Incremental load is deferred until key/date columns are verified.
