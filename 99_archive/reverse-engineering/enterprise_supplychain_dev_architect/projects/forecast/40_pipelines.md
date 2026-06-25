# 40 — Pipelines

> Scanned: 2026-05-06 · Updated 2026-06-02 from Fabric REST job history, `Meta.PipelineRunLog`, and legacy v8 schedule verification.
>
> **2026-06-15 drift note:** the live v10 core-stack audit is now [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md). In particular, `pl_sc_gold` and schedule state should be read from that audit before treating the older narrative below as current.

## Pipeline Inventory (7 v10 pipelines)

| # | Pipeline | ID | Role |
|---|----------|----|------|
| 1 | `pl_sc_master` | `f36f56b8-5668-4a0c-b991-2c28302f1710` | Master orchestrator — multi-mart ForEach driver |
| 2 | `pl_sc_mart` | `20db5725-80e3-4081-9ef5-01700acdf3b3` | Per-project mart runner — invoked from master |
| 3 | `pl_sc_staging` | `10221fb2-6e30-4911-9d95-d8dd67440d84` | Staging + ReferenceMaster load |
| 4 | `pl_sc_silver` | `7dc6ecda-56cc-4797-893c-1c502863323f` | Silver DAG dispatcher (3 waves) |
| 5 | `pl_sc_silver_wave` | `797b1a02-f973-4584-bd27-bb0151549d4b` | Single-wave parallel executor |
| 6 | `pl_sc_gold` | `50ff6263-659d-4b09-9e45-b42a3434e093` | Gold cross-DB CTAS publish |
| 7 | `pl_dq_check` | `3c7c61f6-c184-41e5-8309-f9ac3260d38d` | DQ rule gate (54 rules) |

> 12 additional legacy/test pipelines exist in workspace but are not part of v10 forecast flow.

---

## DAG Topology

```
pl_sc_master
  ├─ log_start  → Meta.usp_LogPipelineRun(pipeline_run_id, 'pl_sc_master', 'running')
  │
  ├─ lk_projects  → SELECT project FROM Meta.AssetRegistry WHERE is_active=1 GROUP BY project ORDER BY ...
  │
  ├─ fe_projects  → ForEach project (concurrency=1)
  │    └─ invoke_mart  → pl_sc_mart(project_name = @item().project)
  │         │
  │         pl_sc_mart  (parameter: project_name)
  │           ├─ invoke_staging  → pl_sc_staging
  │           │    │
  │           │    pl_sc_staging
  │           │      ├─ Staging_Wrk.usp_RefreshEdwTables  (4 EDW tables, ~155M rows)
  │           │      └─ ForEach REF asset (smart skip via next_run_time)
  │           │           └─ Meta.usp_GenericLoad(@target_schema, @target_table)
  │           │
  │           ├─ invoke_silver  → pl_sc_silver
  │           │    │
  │           │    pl_sc_silver
  │           │      ├─ Meta.usp_ComputeSilverWaves  → write SilverDagWaveRuntime
  │           │      └─ ForEach wave (sequential)  ← 3 waves
  │           │           └─ invoke pl_sc_silver_wave(wave_number)
  │           │                │
  │           │                pl_sc_silver_wave  (parameter: wave_number)
  │           │                  ├─ Lookup SPs for wave (project + wave_number)
  │           │                  └─ ForEach (parallel batch=8)
  │           │                       └─ Meta.usp_GenericLoad(@target_schema, @target_table)
  │           │
  │           └─ invoke_gold  → pl_sc_gold
  │                │
  │                pl_sc_gold
  │                  ├─ Lookup Gold assets WHERE project=@project AND is_active=1
  │                  └─ ForEach (cross-DB CTAS)
  │                       ├─ DROP TABLE IF EXISTS Gold.<schema>.<table>
  │                       └─ CREATE TABLE Gold.<schema>.<table> AS
  │                          SELECT * FROM <legacy_view_name>
  │
  └─ finalize  → Meta.usp_FinalizePipeline(pipeline_run_id)
                  │
                  ├─ Meta.usp_BuildLineage  (rebuild 60 edges)
                  └─ UPDATE PipelineRunLog status='success'
```

**Standalone:**
```
pl_dq_check
  ├─ Lookup active DQ rules WHERE is_active=1
  └─ ForEach (batch=5)
       └─ Meta.usp_CheckDqSingle(@rule_id)
            ├─ severity=CRITICAL  → THROW 50001 on FAIL → pipeline stops
            └─ severity=WARNING  → log only → pipeline continues
```

---

## Pipeline Definition Excerpts

### `pl_sc_master` — orchestrator

| Activity | Type | Depends on | Action |
|----------|------|-----------|--------|
| `log_start` | SqlServerStoredProcedure | — | `EXEC Meta.usp_LogPipelineRun ...` |
| `lk_projects` | Lookup | log_start.Succeeded | LakehouseTableSource: `SELECT project FROM AssetRegistry GROUP BY project ORDER BY ...` |
| `fe_projects` | ForEach (concurrency=1) | lk_projects.Succeeded | items: `@activity('lk_projects').output.value` |
| └ `invoke_mart` | InvokePipeline | — | `pipelineId=20db5725-...`, parameters: `project_name = @item().project` |
| `finalize` | SqlServerStoredProcedure | fe_projects.Succeeded | `EXEC Meta.usp_FinalizePipeline ...` |

### `pl_sc_silver_wave` — parallel wave executor

- Parameter: `wave_number` (int)
- Lookup: SPs assigned to this wave for current project
- ForEach (batch=8, parallel): invoke `usp_GenericLoad` per asset

### `pl_sc_gold` — cross-DB CTAS pipeline

- Lookup: `SELECT physical_schema, physical_object, legacy_view_name FROM AssetRegistry WHERE canonical_layer='Gold' AND project=@project AND is_active=1`
- ForEach: dynamic `DROP TABLE IF EXISTS [Gold].<schema>.<table>` + `CREATE TABLE ... AS SELECT * FROM <view>`
- Why pipeline (not SP)? Fabric blocks cross-DB `CREATE TABLE` from SP — pipeline bridges via separate WH connections.

---

## Schedule

| Item | Value |
|------|-------|
| Target | Daily 2:00 AM UTC+7 (SE Asia) |
| Status | **PENDING** — IT permission required to enable schedule trigger |
| Current mode | Manual trigger via Fabric portal |
| Last successful full run | 2026-05-29 16:15:29→17:27:22 UTC, run `24942a8b-1750-4f96-9bfc-23fecac90952`, `12 succeeded, 0 failed` |
| Full runtime | ~72 minutes for the 2026-05-29 cross-mart run |

## Legacy v8 Daily Schedule (kept separate from v10)

The legacy v8 `pl_master_daily` chain was recovered on 2026-06-02 and scheduled to keep the old `Supply Chain Control Tower` semantic model/report refreshed while v10 remains separate. See [../../30_runbook/19_legacy_v8_daily_refresh_recovery.md](../../30_runbook/19_legacy_v8_daily_refresh_recovery.md) for full evidence.

| Item | Value |
|---|---|
| Master pipeline | `pl_master_daily` (`4214332e-392f-4d2e-ac11-99094ac33aa7`) |
| Child chain | `pl_brz_daily` → `pl_slv_daily` → `pl_gld_daily` → `pl_sp_daily_v2` |
| Schedule ID | `8667733d-625c-4b7f-8dca-19816c7b0775` |
| Schedule state | Enabled |
| Frequency | Daily at `02:00` |
| Time zone | `SE Asia Standard Time` |
| Latest verified full run | `255c243b-2260-4a44-93a5-a30ea0c3ab0b`, `Completed`, 2026-06-02 08:49:26→09:13:06 UTC |
| Registry gate | `SupplyChain_Lakehouse.dbo.utl_pipeline_metadata`; active BRZ/REF/SLV rows due 02:00, GLD rows due 03:00 |

## Stage Runtimes

Current full-master runtime is dominated by large overwrite/datekey materialization for both Forecast Accuracy and Inventory Health. Latest confirmed master success took about 72 minutes. Older 31-minute estimates were forecast-only/pre-Inventory-Health scale and should not be used as the current SLA.

## Historical Stage Runtimes (forecast-only baseline)

| Stage | Duration | Rows processed |
|-------|---------:|---------------:|
| Staging EDW refresh (`usp_RefreshEdwTables`) | ~6 min | 155M |
| Silver Wave 0 (parallel: InvoiceDetailLineLevel + ForecastDemandMonthly + OpenOrderLineLevel) | ~8 min | 88M + 42M + 193K |
| Silver Wave 1 (parallel: 4 tables) | ~4 min | ~50M |
| Silver Wave 2 (NaiveForecastMonthly) | ~6 min | 2M |
| Gold cross-DB CTAS (FactForecastActual + FactForecastKpi + 5 Dims) | ~7 min | 47M + 36M + 437K |
| **Total** | **~31 min** | ~420M |

## Smart Skip

`Meta.AssetRegistry` has `frequency` + `cron_expression` per asset. The Lookup SQL inside `pl_sc_staging`'s ForEach REF activity filters:

```sql
SELECT * FROM Meta.AssetRegistry
WHERE canonical_layer='ReferenceMaster' AND is_active=1
  AND project=@project_name
  AND Meta.ufn_should_run(asset_id) = 1   -- cron + last_run check
```

→ Monthly REF tables are skipped on daily runs (verified live).

## Multi-Mart Routing

`pl_sc_master` reads `DISTINCT project` from registry. To add a new mart:
1. INSERT new rows into `Meta.AssetRegistry` with `project = '<new_mart>'`
2. CREATE VIEWs in appropriate schemas
3. No pipeline changes needed — `pl_sc_master` auto-discovers

## Recent Run History

Query: `SELECT TOP 50 ... FROM Meta.RunLog ORDER BY start_time_utc DESC`. Live results stored in JSON: see `etl/recent_runs.json` if exported.
