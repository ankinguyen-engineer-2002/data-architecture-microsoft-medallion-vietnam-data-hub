# Main Orchestration

Use this when Aric asks to run the full SupplyChain path.

## Current Status

[Verified] Final Enterprise ETL runtime rerun passed on 2026-06-24.

| Check | Result |
|---|---|
| Full wrapper run | `4/4` succeeded |
| Total runtime | `1,721.01s` / about `28m 41s` |
| Active wrapper surface | exactly two Silver + two Gold mart wrappers |
| `TableDictionary` active curated rows | `46/46` `_Wrk.v_*`, `0` errors |
| `AuditLog` | `56 Process Start` + `56 Process Complete`, `0` errors |
| Compile smoke | `92/92` active target/source checks passed |
| Live/local SQL modules | `49/49` matched, no drift |

## SQL Agent Handoff

US/DE scheduling should call exactly these four wrapper procedures in order:

```sql
-- Step 1: Forecast Accuracy Silver
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Silver];

-- Step 2: Forecast Accuracy Gold
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_ForecastAccuracy_Gold];

-- Step 3: Inventory Health Silver
EXEC [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver];

-- Step 4: Inventory Health Gold
EXEC [SupplyChain_Gold_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Gold];
```

Current logical order:

1. `forecast_accuracy`
2. `inventory_health`
3. post-run smoke

The active mart wrappers are self-contained:

- `*_Silver` includes ReferenceMaster prerequisite Wave 00.
- `*_Gold` includes Shared_DW prerequisite Wave 00.

The official live Fabric master pipeline `pl_sc_master` is legacy context for current docs. SQL Agent should use the wrapper procedures listed in the manifest when US owns scheduling.

This folder documents the order and provides a safe runner for ad-hoc execution.

## Wrapper Stored Procedures

- Wrapper order lives in `manifest.json` under `wrapper_procedures`.
- Mart wrapper DDL lives under each mart's `sql/` folder.
- Default dry-run printer:
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json`
- Wrapper order is aligned to the two active mart model: Forecast Silver/Gold, then Inventory Silver/Gold.

## Enterprise `_Wrk` Contract

- Full refresh order targets final physical tables.
- Silver/Gold framework source views are `<target_schema>_Wrk.v_<target_table>`.
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
