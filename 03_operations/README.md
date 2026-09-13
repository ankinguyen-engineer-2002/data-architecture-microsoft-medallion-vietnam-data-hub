# Operations

Three operating surfaces for the **same two marts**. Fabric is live in this
git. Azure and Databricks folders are the reconstructed landing/compute
slice (ADR-013), not a subscription or workspace export.

**Speak from [CLAIMS.md](CLAIMS.md).** PIM / reconstructed / Contributor
snapshot are three different sentences.

```text
03_operations/
  azure/            landing, identity, on-call   [names verified; layout reconstructed]
  databricks/       seven Spark jobs + notebooks [reconstructed from Bronze]
  orchestration/    SQL Agent 11 steps           [Fabric live contract]
  deployment/       SQLPROJ / dacpac
  operating_registry/
  tools/
  SOURCE_SLICE.md   why 33 tables, not the hub
  runbook.md        night order Azure → Spark → Agent
```

| Layer | What you operate | Proof |
|---|---|---|
| Azure | Entra, subscription, lake, SQL/Agent, Fabric tenant, Databricks workspace | [azure/](azure/) |
| Databricks | UC `edw_dev`, seven jobs, DateRange/CDC, cluster exits | [databricks/](databricks/) |
| Databricks version / promote | Job+Runtime+Delta; Dev→Prod = catalog/workspace, not dacpac | [databricks/cicd_and_promotion.md](databricks/cicd_and_promotion.md) |
| Fabric | `_Wrk` → wrappers → Gold → DQ `50003` | [orchestration/main/](orchestration/main/) |
| Fabric CI/CD | SQLPROJ build-only; US owns official publish | [deployment/sqlproj/](deployment/sqlproj/) |

Dry-run Fabric wrappers by default. `--execute` needs an explicit approve.
Do not schedule Spark and Agent as two Fabric pipelines (dual-scheduler).

```bash
python3 03_operations/tools/validate_upstream_slice.py
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json
```

Night path: [runbook.md](runbook.md) · [databricks/night_order.yaml](databricks/night_order.yaml).
Slice rule: [SOURCE_SLICE.md](SOURCE_SLICE.md).
Spark CI/CD: [databricks/cicd_and_promotion.md](databricks/cicd_and_promotion.md).
