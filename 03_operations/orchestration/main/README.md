# Main Orchestration

Use this when Aric asks to run the full SupplyChain path.

## Current Status

[Draft] SQL Agent handoff is now 10 wrapper SP job steps: shared prerequisites, then Forecast Silver/Gold and Inventory Silver/Gold wrappers.

| Check | Result |
|---|---|
| Wrapper surface | 10 SPs total |
| Shared prereq | 2 Processing SPs |
| Forecast Silver | 3 Processing wave SPs |
| Inventory Silver | 3 Processing wave SPs |
| Gold | 2 Gold monolithic SPs unchanged |
| Load method in new wave SPs | `usp_RefreshCuratedTableFromView` overwrite only |
| Staging gap | `Staging.DemandForecastSnapshotDaily` added as shared W01 |

## SQL Agent Handoff

US/DE scheduling should call these 10 wrapper procedures in order:

```sql
-- Step 01: Shared ReferenceMaster
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_Shared_ReferenceMaster];

-- Step 02: Shared Staging
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_Shared_Staging];

-- Step 03: Forecast Accuracy Silver W01
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W01];

-- Step 04: Forecast Accuracy Silver W02
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W02];

-- Step 05: Forecast Accuracy Silver W03
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver_W03];

-- Step 06: Forecast Accuracy Gold
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Gold];

-- Step 07: Inventory Health Silver W01
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W01];

-- Step 08: Inventory Health Silver W02
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W02];

-- Step 09: Inventory Health Silver W03
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W03];

-- Step 10: Inventory Health Gold
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Gold];
```

Current logical order:

1. shared prerequisites
2. `forecast_accuracy` Silver W01→W02→W03
3. `forecast_accuracy` Gold
4. `inventory_health` Silver W01→W02→W03
5. `inventory_health` Gold
6. post-run smoke

The canonical 10-step wrapper order lives in `manifest.json` under `wrapper_procedures` and is mirrored in the live-target artifact `03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.json` (Fabric pipeline `pl_backup_full_refresh` / `41948342-d7e7-4166-8638-9af0633e6a49`). Legacy `pl_sc_master` is no longer present in the live workspace; SQL Agent handoff uses the wrappers listed in `manifest.json`.

## Wrapper Stored Procedures

- Wrapper order lives in `manifest.json` under `wrapper_procedures`.
- Shared wrapper DDL lives under `03_operations/orchestration/shared/sql/`.
- Mart wave wrapper DDL lives under each mart's `sql/` folder.
- Gold wrapper DDL remains unchanged.
- Default dry-run printer:
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json`

## Enterprise `_Wrk` Contract

- Full refresh order targets final physical tables.
- Silver/Gold framework source views are `<target_schema>_Wrk.v_<target_table>`.
- `Staging_Wrk.v_*` views remain visible in lineage because Silver views use them as source evidence.
- Base-schema `v_*` views have been removed from active Silver/Gold curated schemas and must not be referenced.

## Monitoring Query

Use this against `ETL_Framework` to see which table ran when and for how long:

```sql
WITH audit_rows AS (
    SELECT
        [Description],
        [Command],
        [DateTime],
        ROW_NUMBER() OVER (
            PARTITION BY [Description], [Command]
            ORDER BY [DateTime]
        ) AS rn
    FROM [DW_Developer].[AuditLog]
    WHERE [Command] IN ('Process Start', 'Process Complete')
),
paired AS (
    SELECT
        s.[Description],
        s.[DateTime] AS StartTime,
        c.[DateTime] AS EndTime,
        DATEDIFF(second, s.[DateTime], c.[DateTime]) AS DurationSeconds
    FROM audit_rows s
    JOIN audit_rows c
      ON c.[Description] = s.[Description]
     AND c.rn = s.rn
     AND c.[Command] = 'Process Complete'
    WHERE s.[Command] = 'Process Start'
)
SELECT
    [Description],
    StartTime,
    EndTime,
    DurationSeconds
FROM paired
ORDER BY StartTime DESC;
```

Use `DW_Developer.TableDictionary` for:

- `DatabaseName`, `SchemaName`, `TableName`
- `ReplicatedSource`
- `UpdateMethod`
- `UpdateQuery`
- `RowCount`
- `Modified`
- `ErrorMsg`
