# 40 — Pipelines

> **Status (updated 2026-06-15):** No new pipelines required. Inventory Health is orchestrated by the existing v10 `pl_sc_*` chain. Latest verified full `pl_sc_master` success is the **manual** run on **2026-06-04**; both Fabric schedules on `pl_sc_master` remain disabled.
>
> **2026-06-15 control-plane note:** the live v10 core-stack audit is now [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md). On 2026-06-15, active inventory rows were normalized from `project='inventoryHistory_Enh'` to `project='inventory_health'`, `pl_sc_staging` was re-filtered by project for ReferenceMaster loads, and `pl_sc_gold` was re-filtered by project for Gold publish.

## How inventory_health joins the multi-mart flow

`pl_sc_master` now enumerates active projects in deterministic order:

```sql
SELECT DISTINCT project
FROM SupplyChain_Processing_Warehouse.Meta.AssetRegistry
WHERE is_active = 1
  AND project IS NOT NULL
ORDER BY CASE
    WHEN project = 'shared' THEN 0
    WHEN project = 'forecast_accuracy' THEN 1
    WHEN project = 'inventory_health' THEN 2
    ELSE 99
END, project
```

## Existing 7 v10 pipelines (reused as-is)

| # | Pipeline | ID | Role for inventory_health |
|---|----------|----|---|
| 1 | `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | Master orchestrator — deterministic order `shared` -> `forecast_accuracy` -> `inventory_health` |
| 2 | `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | Per-project router — runs Staging→Silver→Gold sequentially per project |
| 3 | `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | Staging + ReferenceMaster load — project-filtered on 2026-06-15 |
| 4 | `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | Silver DAG dispatcher — invokes wave executor 3-4 times |
| 5 | `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | Parallel batch=8 executor per wave |
| 6 | `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | Cross-DB CTAS publish — project-filtered again on 2026-06-15 |
| 7 | `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | DQ rule gate (run separately or on-demand) |

## Live Control-Plane Status (2026-06-15)

| Pipeline | Latest Fabric job status | Notes |
|---|---|---|
| `pl_sc_master` | Completed | Latest success: `Meta.PipelineRunLog` + Fabric job history show the manual run on 2026-06-04 (`17 succeeded, 0 failed`). |
| `pl_sc_mart` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_staging` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_silver` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_silver_wave` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_gold` | Completed | Latest Fabric job samples show Completed. |
| `pl_dq_check` | Completed | Latest Fabric job samples show Completed; older failures remain in history and are documented in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). |

[Verified] `Meta.PipelineRunLog.project` is still null for all historical rows because only `pl_sc_master` is logged today; mart-level logging remains a follow-up improvement.

## Observed runtime

| Stage | Estimated duration | Notes |
|---|---:|---|
| Staging | <1 min | latest `pl_sc_staging` completed 2026-05-27 |
| Silver dispatcher | <1 min | latest `pl_sc_silver` completed 2026-05-27 |
| Silver wave execution | ~4 min | latest `pl_sc_silver_wave` completed 2026-05-27 |
| Gold cross-DB CTAS | [Verified] latest job samples Completed | older failed jobs remain in history; current Gold/semantic smoke is green |
| Full master | ~72 min | latest verified `pl_sc_master` success 2026-05-29 16:15:29→17:27:22 UTC |

## DAG topology (in pl_sc_silver_wave)

`Meta.usp_ComputeSilverWaves` is project-aware and now reads a fully normalized `inventory_health` tag for all active Mart B Silver rows. Live runtime after the 2026-06-15 cleanup:

```
Wave 0: AFIStatusSnapshotWeekly, Cogs52WWeekly, ForecastSnapshotWeekly, InventorySnapshotWeekly
Wave 1: AwdHelper, HoldingTransferSnapshotDaily, ItemBalanceHistorical_WithInTransit,
        LastInvoiceWeekly, ManufacturingOrderSnapshotDaily, SafetyStockHelper, SupplyPlanDetail
```

**2026-05-22 cleanup**:
- DROPPED `MovementHistory`, `ForecastCurrent` (Wave 0, view-only, orphan)
- DEACTIVATED `LogilityItemStatusSnapshotWeekly` (Wave 1, Phase 2 conditional — pl_sc_master skips when is_active=0)

**2026-05-28 DA-first refactor**:
- REMOVED `InventoryHistory_Enh.SalesShipment` from active registry/pipeline flow.
- Helper and COGS views read `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly.

(Authoritative wave assignments from `Meta.SilverDagWaveRuntime` — see live snapshot.)

## Smart skip + scheduling

Per-asset `frequency` + `cron_expression` lives in `Meta.AssetRegistry`. The 2026-06-15 cleanup normalized inventory `Daily` casing to `daily`, but two active inventory rows still have `NULL` frequency and should be treated as metadata follow-up.

| Layer | Active rows | Frequency/load mix |
|---|---:|---|
| `ReferenceMaster_Enh` | 1 | monthly overwrite |
| `InventoryHistory_Enh` | 11 active DomainSilver | mixed daily / weekly / null metadata; runtime now all under `project='inventory_health'` |
| `InventoryHealth_DW` | 4 active Gold | daily overwrite facts/helpers + monthly dim |

`Meta.ufn_should_run(asset_id)` evaluates `cron_expression` vs UTC now; out-of-window assets are skipped.

Fabric item schedules are separate from per-asset registry cron:
- [Verified] `pl_sc_master` currently has 2 schedules in Fabric and both are disabled.
- Downstream `pl_sc_*` items have no direct schedules, which is expected if master orchestrates.
- Legacy `pl_slv_daily` has enabled schedules and completed on 2026-05-28, but it is not proof that the v10 `pl_sc_master` path is green.

## Deploy sequence (when ready)

1. `silver_views.sql` → Processing WH
2. `gold_views.sql` → Gold WH
3. `registry_inserts.sql` → Processing WH (Meta schema)
4. `dq_rules_inserts.sql` → Processing WH (Meta schema)
5. `EXEC Meta.usp_ComputeSilverWaves @project = '<mart_name>';`
6. `EXEC Meta.usp_BuildLineage;`
7. Manually trigger `pl_sc_master` via Fabric portal/API → verify `shared` -> `forecast_accuracy` -> `inventory_health` completes in order.
8. Only after step 7 is green, enable the intended `pl_sc_master` schedule.
