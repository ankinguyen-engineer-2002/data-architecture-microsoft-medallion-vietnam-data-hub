# Azure SQL / EDW vs Fabric warehouses

Two different “SQL”s. Mixing them is how interviews fall apart.

| | Azure SQL / EDW landing | Fabric warehouse |
|---|---|---|
| Where it lives | Azure resource (SQL DB / MI / SQL on VM — SKU `[Need-verify]`) | Fabric item on capacity |
| How you open it | SSMS, Entra or SQL login | Fabric portal / SSMS to SQL endpoint |
| What the slice uses it for | Structured landing, **SQL Server Agent**, some `Source_Data` copies | `_Wrk`, Gold, DQ, 11 wrappers |
| Scale in hub scan | `Source_Data`: **64 schemas / 636 tables** (DEV) | SCM Gold: Forecast + Inventory facts/dims |
| In this git | Pattern + Agent handoff | Full SQLPROJ |

Ashley was mid-migration EDW → Fabric (2026-05/06 scan): pipelines
`EDW2FabricLoader`, `Fabric Migration ADF`, metadata
`ASHLEY_EDW_DEV.dw_developer.FabricMapping`. That is **enterprise hub**,
not something to copy into this repo.

## What Azure SQL still does for these two marts

1. **SQL Server Agent** is the clock for Fabric wrappers
   (`orchestration/main` — 11 fail-fast steps). The Agent host is SQL
   Server in Azure (or still on an Azure VM). Fabric pipelines are not
   the production clock.
2. **Landing that is still a table.** Some feeds remain queryable in SSMS
   (ops habit). Spark still owns invoice / forecast volume. Do not run
   nightly Spark and ADF copy onto the **same** watermark.
3. **Reconciliation leftover.** Hub pipeline `Source_EDW_Check_Test`
   (daily 03:50 UTC) compared EDW vs Fabric counts. Out of slice unless
   Forecast freshness fails and you need to see whether EDW moved.

## What Azure SQL must not do

- Host `FactForecastKpi` / `FactInventoryHealthSnapshot` as the serving
  copy. Serving is `SupplyChain_Gold_Warehouse`.
- Replace Databricks for the ~11B snapshot. DateRange 30 days is a Spark
  job, not a SQL Agent result set.
- Store GPS / dock events. Not this plane.

## Logins [Reconstructed pattern]

| Principal | Azure SQL / Agent | Fabric warehouse |
|---|---|---|
| Agent service account | run 11 EXEC, no DDL on Gold | — |
| `data-sc-engineers` | read landing if needed | Contributor / db write via wrappers |
| `data-sc-analysts` | none | Gold read via semantic / Direct Lake |
| PIM admin | create login, change Agent job | workspace / tenant, not table data |

SSMS against Gold SQL endpoint is for DE debug. DA default is the
semantic model, not SSMS.
