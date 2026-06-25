# EnterpriseData ETL Framework Data Feed Alert Email Analysis

Date analyzed: 2026-06-23

Source file:

- `01_docs/bob-framework/source/EnterpriseData - ETL_Framework DataWarehouse Data Feed Alert_ 0.2857% behind (1 of 350).msg`

## What This File Proves

- [Verified] Bob's framework has an actual email alert output, not only guide-level intent.
- [Verified] The alert title is `EnterpriseData - ETL_Framework DataWarehouse Data Feed Alert`.
- [Verified] The message sender is `Datawarehouse Alerts <DatawarehouseAlerts@Ashleyfurniture.com>`.
- [Verified] The recipient group includes `DL_AFI_Analytics_AG_DataWarehouse@Ashleyfurniture.com`.
- [Verified] The alert is framed as `FABRIC Table Dictionary Objects that are behind schedule`.
- [Verified] The sample run timestamp is `2026-06-22 16:43:16`.
- [Verified] The sample status is `Behind: 1 of 350 (0.2857%)`.

## Alert Output Fields

The email exposes these operational fields:

- `Hours Late`
- `Last Updated (UTC)`
- `Refresh Rate (hours)`
- `Schema Name`
- `Table Name`
- `Job Server`
- `Job Name`

Sample row:

| Field | Value |
|---|---|
| Hours Late | `50` |
| Last Updated (UTC) | `2026-06-20 06:00:38` |
| Refresh Rate (hours) | `3` |
| Schema Name | `MasterData_ItemMaster_AFI` |
| Table Name | `ITBEXT` |
| Job Server | `Dwsaazp-radap01` |
| Job Name | `Windows Task Scheduler-ItemMaster_Journal_Sync` |

## Mapping To Reverse-Engineered Framework

- [Verified] The fields match the `TableDictionary` scheduling/SLA group already captured in `99_archive/reverse-engineering/enterprise_data_architect/10_evidence/02_etl_framework_summary.md`: `RefreshRate`, `JobServer`, `JobName`, `Modified`, `LastAudit`.
- [Verified] The storage inventory already captured `Performance_Logs.tblFabricSLAAlertLog`, `Performance_Logs.tblFabricSLAAlertLog_Detail`, `Performance_Logs.EmailQueue`, and `Performance_Logs.DimEmailQueue`.
- [Likely] `Last Updated (UTC)` is derived from `TableDictionary.Modified` or equivalent update-log aggregation. This should be verified against the alert stored procedure before implementation.
- [Likely] `Hours Late` is computed from current UTC time minus last-updated time compared against `RefreshRate`.

## Impact On Migration Plan

- [Verified] This file strengthens the observability/SLA evidence in Bob's framework.
- [Verified] It does not describe the orchestration engine, dependency graph, checkpoint restart mechanics, retry policy, or ad-hoc refresh workflow.
- [Verified] It should not become a blocker for Phase 1 runtime proof.
- [Verified] Phase 1 should preserve or seed the `TableDictionary` fields required for future alerting: `Modified`, `RefreshRate`, `JobServer`, `JobName`, plus `SchemaName` and `TableName`.

## Recommended Plan Adjustment

- Keep the core Phase 1 scope unchanged: replace the runtime/framework path, not the business layers.
- Add alert-readiness as a Phase 1I readiness/backlog item.
- Defer actual email scheduler integration until owner/permissions/channel are approved.
