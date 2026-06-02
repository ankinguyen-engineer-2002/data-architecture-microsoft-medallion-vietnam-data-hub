# 40 — Pipelines

> **Status (updated 2026-06-01):** No new pipelines required. Inventory Health is orchestrated by the existing v10 `pl_sc_*` pipelines via registry-driven multi-mart ForEach. Latest verified full `pl_sc_master` in `Meta.PipelineRunLog` completed successfully on 2026-05-29 with `12 succeeded, 0 failed`; schedule auto-run still needs explicit verification/enabling.

## How inventory_health joins the multi-mart flow

`pl_sc_master` runs `SELECT DISTINCT project FROM Meta.AssetRegistry WHERE is_active=1` → ForEach project → invoke `pl_sc_mart(project_name)`. After inserting 33 rows with `project='inventory_health'` into the registry, `pl_sc_master` automatically picks `inventory_health` alongside `forecast` on next trigger.

## Existing 7 v10 pipelines (reused as-is)

| # | Pipeline | ID | Role for inventory_health |
|---|----------|----|---|
| 1 | `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | Master orchestrator — auto-picks `inventory_health` via ForEach |
| 2 | `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | Per-project router — runs Staging→Silver→Gold sequentially per project |
| 3 | `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | Staging + ReferenceMaster load — runs `Meta.usp_GenericLoad` for `Vendor` |
| 4 | `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | Silver DAG dispatcher — invokes wave executor 3-4 times |
| 5 | `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | Parallel batch=8 executor per wave |
| 6 | `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | Cross-DB CTAS for 8 InventoryHealth_DW tables |
| 7 | `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | DQ rule gate (run separately or on-demand) |

## Live Control-Plane Status (2026-06-01)

| Pipeline | Latest Fabric job status | Notes |
|---|---|---|
| `pl_sc_master` | Completed | `Meta.PipelineRunLog`: run `24942a8b-1750-4f96-9bfc-23fecac90952`, 2026-05-29 16:15:29→17:27:22 UTC, `12 succeeded, 0 failed`. |
| `pl_sc_mart` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_staging` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_silver` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_silver_wave` | Completed | Latest Fabric job samples show Completed. |
| `pl_sc_gold` | Completed | Latest Fabric job samples show Completed. |
| `pl_dq_check` | Completed | Latest Fabric job samples show Completed; older failures remain in history and are documented in [../live_audit_2026-06-01.md](../live_audit_2026-06-01.md). |

Previous successful `pl_sc_master` run: 2026-05-26 07:15-08:41 UTC. `Meta.PipelineRunLog` was synced on 2026-05-28 for the cancelled `771c140c...` run and failed `3393c7a3...` run, using Fabric job history as the source of truth.

## Observed runtime

| Stage | Estimated duration | Notes |
|---|---:|---|
| Staging | <1 min | latest `pl_sc_staging` completed 2026-05-27 |
| Silver dispatcher | <1 min | latest `pl_sc_silver` completed 2026-05-27 |
| Silver wave execution | ~4 min | latest `pl_sc_silver_wave` completed 2026-05-27 |
| Gold cross-DB CTAS | [Verified] latest job samples Completed | older failed jobs remain in history; current Gold/semantic smoke is green |
| Full master | ~72 min | latest verified `pl_sc_master` success 2026-05-29 16:15:29→17:27:22 UTC |

## DAG topology (in pl_sc_silver_wave)

`Meta.usp_ComputeSilverWaves` reads `depends_on` from registry rows. Expected DAG for inventory_health:

```
Wave 0: ForecastSnapshotWeekly and independent source/base assets
Wave 1: InventorySnapshotWeekly
Wave 2: InventorySnapshotWeeklyFactBase, AwdHelper, LastInvoiceHelper,
        MovementFlagHelper, SafetyStockHelper
Wave 3+: daily PO/MO/Holding snapshots and Gold publish assets per live registry
```

**2026-05-22 cleanup**:
- DROPPED `MovementHistory`, `ForecastCurrent` (Wave 0, view-only, orphan)
- DEACTIVATED `LogilityItemStatusSnapshotWeekly` (Wave 1, Phase 2 conditional — pl_sc_master skips when is_active=0)

**2026-05-28 DA-first refactor**:
- REMOVED `InventoryHistory_Enh.SalesShipment` from active registry/pipeline flow.
- Helper and COGS views read `SalesHistory_Enh.v_InvoiceDetailLineLevel` directly.

(Authoritative wave assignments from `Meta.SilverDagWaveRuntime` — see live snapshot.)

## Smart skip + scheduling

Per-asset `frequency` + `cron_expression` lives in `Meta.AssetRegistry` and is evaluated by `Meta.ufn_should_run(asset_id)`. Live 2026-05-28 summary:

| Layer | Active rows | Frequency/load mix |
|---|---:|---|
| `ReferenceMaster_Enh` | 1 | monthly overwrite |
| `InventoryHistory_Enh` | 12 | daily datekey/overwrite + weekly daterange/incremental/overwrite |
| `InventoryHealth_DW` | 6 | daily overwrite facts/helpers + monthly overwrite dims |

`Meta.ufn_should_run(asset_id)` evaluates `cron_expression` vs UTC now; out-of-window assets are skipped.

Fabric item schedules are separate from per-asset registry cron:
- [Need-verify] The latest verified state from this audit is manual completed job history. Re-check Fabric item schedules before claiming cron auto-run is active.
- Downstream `pl_sc_*` items have no direct schedules, which is expected if master orchestrates.
- Legacy `pl_slv_daily` has enabled schedules and completed on 2026-05-28, but it is not proof that the v10 `pl_sc_master` path is green.

## Deploy sequence (when ready)

1. `silver_views.sql` → Processing WH
2. `gold_views.sql` → Gold WH
3. `registry_inserts.sql` → Processing WH (Meta schema)
4. `dq_rules_inserts.sql` → Processing WH (Meta schema)
5. `EXEC Meta.usp_ComputeSilverWaves;`
6. `EXEC Meta.usp_BuildLineage;`
7. Manually trigger `pl_sc_master` via Fabric portal/API → verify both `forecast` + `inventory_health` run terminal `Completed`.
8. Only after step 7 is green, enable the intended `pl_sc_master` schedule.
