# Main Orchestration

Use this when Aric asks to run the full SupplyChain path.

## Current Status

[Draft] SQL Agent handoff is now 11 fail-fast job steps: shared prerequisites,
Forecast Silver/Gold, an exact-run blocking Forecast DQ gate, then Inventory.

| Check | Result |
|---|---|
| Wrapper surface | 11 SPs total |
| Shared prereq | 2 Processing SPs |
| Forecast Silver | 3 Processing wave SPs |
| Inventory Silver | 3 Processing wave SPs |
| Gold | 2 Gold monolithic SPs unchanged |
| Forecast publish gate | 1 Processing SP; error `50003` blocks downstream work |
| Load method in new wave SPs | `usp_RefreshCuratedTableFromView` overwrite only |
| Staging gap | `Staging.DemandForecastSnapshotDaily` added as shared W01 |

## SQL Agent Handoff

US/DE scheduling should call these 11 procedures in order. Configure every job
step to continue only on success; step 07 must quit the job and report failure
when SQL error `50003` is raised.

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

-- Step 07: Forecast Accuracy exact-run DQ gate
EXEC [SupplyChain_Processing_Warehouse].[DataQuality].[usp_RunAndGateForecastAccuracyPublish];

-- Step 08: Inventory Health Silver W01
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W01];

-- Step 09: Inventory Health Silver W02
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W02];

-- Step 10: Inventory Health Silver W03
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W03];

-- Step 11: Inventory Health Gold
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Gold];
```

Current logical order:

1. shared prerequisites
2. `forecast_accuracy` Silver W01→W02→W03
3. `forecast_accuracy` Gold
4. exact-run Forecast DQ gate; `PublishAllowed=1` is mandatory
5. `inventory_health` Silver W01→W02→W03
6. `inventory_health` Gold
7. post-run smoke

The official live Fabric master pipeline `pl_sc_master` is legacy context for
current docs. SQL Agent should use `manifest.json` when US owns scheduling.
`pl_backup_full_refresh` and `pl_backup_per_table` are manual DEV fallbacks, not
the production schedule authority.

SQL Agent operational contract:

- step 07 persists one DQ run and gates that exact `DQRunId`;
- `PASS` returns normally; `FAIL`, `ERROR`, or blocking `NOT_COMPARABLE` raises
  SQL error `50003`;
- configure retry/alert according to DE policy, but never route failure to the
  next Inventory or publication step;
- deploy the procedures and `DQForecastAccuracyGate` table before adding the
  job step.

## Wrapper Stored Procedures

- Wrapper order lives in `manifest.json` under `wrapper_procedures`.
- Shared wrapper DDL lives under `03_operations/orchestration/shared/sql/`.
- Mart wave wrapper DDL lives under each mart's `sql/` folder.
- Forecast Gold keeps the wrapper surface but changes `FactForecastKpi` from a
  Snapshot DateRange refresh to overwrite/full restatement.
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

Use `DW_Developer.TableDictionary` for the load contract:

- `DatabaseName`, `SchemaName`, `TableName`
- `ReplicatedSource`
- `UpdateMethod`
- `UpdateQuery`
- `Modified`
- `ErrorMsg`

Do not treat `TableDictionary.RowCount` as overwrite-load proof: the current
`usp_RefreshCuratedTableFromView` implementation does not maintain it. Use
direct counts plus the persisted current-view parity DQ result instead.
