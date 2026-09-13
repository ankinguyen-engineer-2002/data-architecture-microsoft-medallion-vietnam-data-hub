# On-call: Azure → Spark → Fabric (two marts)

Night order (do not invert; do not dual-schedule):

```text
01:10–02:50 UTC  seven Databricks jobs, each EXIT
                 (landing ADLS → Delta UC edw_dev)
then            Fabric mirror edw_dev / Enterprise_Lakehouse shortcuts
then            SQL Agent 11 steps
                 shared → Forecast waves → Gold → DQ 50003 → Inventory
```

| If this failed | Do not |
|---|---|
| `sc_forecast_snapshot` or `sc_sales_invoices` | start Agent; DQ cannot invent Bronze |
| empty `raw/.../dt=` or `current/` | overwrite Delta; job already fail-closed |
| Agent step 07 `50003` | continue steps 08–11 |
| Gold stale, Agent OK | blame wrapper; check mirror / ADLS first |

Load methods (must match notebooks + `registry/sources.yaml`):

| Kind | Example | Spark |
|---|---|---|
| Current-state | dims, CODIS, ItemBalance, PO | overwrite `current/` |
| Date-bounded fact | forecast 30d, invoices 3 completed months, inventory daily `dtea` | `replaceWhere` |
| CDC journal | TFRHDR/TFRDTL | MERGE JOENTT UP/PX/PT; no DL/UB |

Phase 1 closeout (2026-06-24) used **four** wrappers. That is historical.
Current handoff is eleven fail-fast steps.

Detail: [databricks/runbook.md](databricks/runbook.md),
[azure/runbook.md](azure/runbook.md),
[databricks/cicd_and_promotion.md](databricks/cicd_and_promotion.md).
