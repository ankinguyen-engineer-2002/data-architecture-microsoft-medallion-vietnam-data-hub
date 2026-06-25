-- 13_update_pipeline_sql_refs.md
-- (NOT a SQL script — this is a manual checklist for updating Fabric pipeline activity SQL.)

# Pipeline activity SQL refs to update

After steps 1-9 are done, the following pipelines have hardcoded schema names that
must be updated via Fabric UI or REST API. Search-and-replace pattern:

| Old | New |
|-----|-----|
| `Staging_WRK` | `Staging_Wrk` |
| `ReferenceMaster_ENH` | `ReferenceMaster_Enh` |
| `SalesHistory_ENH` | `SalesHistory_Enh` |
| `ForecastHistory_ENH` | `ForecastHistory_Enh` |
| `OpenOrderHistory_ENH` | `OpenOrderHistory_Enh` |
| `vw_` | `v_` |

## Pipelines to inspect (per memory project_v10_architecture.md):

| Pipeline | ID | Likely refs |
|----------|----|-----------:|
| pl_sc_master   | f36f56b8-5668-4a0c-b991-2c28302f1710 | orchestrator — InvokeFabricPipeline only, low risk |
| pl_sc_mart     | 20db5725-80e3-4081-9ef5-01700acdf3b3 | ForEach DISTINCT project — registry-driven, low risk |
| pl_sc_staging  | 10221fb2-6e30-4911-9d95-d8dd67440d84 | Lookup `Staging_WRK` — must update |
| pl_sc_silver   | 7dc6ecda-56cc-4797-893c-1c502863323f | Lookup `*_ENH` schemas — must update |
| pl_sc_silver_wave | 797b1a02-f973-4584-bd27-bb0151549d4b | DAG wave Lookup — must update |
| pl_sc_gold     | 50ff6263-659d-4b09-9e45-b42a3434e093 | 3-part name from Processing — must update |
| pl_dq_check    | 3c7c61f6-c184-41e5-8309-f9ac3260d38d | DQ rule SQL — must update |

Use Fabric REST API:
```
GET  https://api.fabric.microsoft.com/v1/workspaces/{wsId}/items/{pipelineId}/getDefinition
PATCH (post update) → POST /updateDefinition
```

Or use the existing `05_tools/` helpers in `Enterprise_SupplyChain_Dev_architect/05_tools/`.
