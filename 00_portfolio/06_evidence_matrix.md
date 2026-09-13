# Evidence matrix

| Claim | Canonical evidence | Verification class | Showcase wording |
|---|---|---|---|
| Azure control plane exists | `03_operations/azure/control_plane.yaml` | tenant/sub/UPN verified 2026-06-21; GA PIM owner-confirmed | Entra registers Fabric + Azure Databricks; not a living Global Admin |
| Spark jobs exist for the two-mart slice | `03_operations/databricks/` + `validate_upstream_slice.py` | reconstructed jobs; Bronze names and load methods verified | Seven jobs mapped to 33 shortcuts; not a Databricks export |
| Databricks CI/CD ≠ Fabric SQLPROJ | `03_operations/databricks/cicd_and_promotion.md` | pattern; no job-publish pipeline in this git; prod catalog `[Need-verify]` | Same Azure; job/notebook as code; do not name `edw_prod` |
| Spark is not 24/7 plant stream | ADR-011, DateRange 30-day staging, ADR-012 | architecture + verified Bronze volume | Stream plane is adjacent OT/AWS, not this git |
| Operational stream is adjacent | `four_cadence_operating_model.md`, ADR-012 | owner-confirmed pattern; MSK IDs `[Need-verify]` | Two planes: this git vs OT/AWS. Shared keys only; no Gold→Flink job |
| Two domain data products | `02_marts/forecast_accuracy/`, `02_marts/inventory_health/` | source-controlled contracts | Forecast and inventory data products |
| Enterprise ETL runtime alignment | migration plan + Phase 1 closeout | live/local parity and build checks | enterprise-aligned DataOps runtime |
| DQ is a publish control | `04_dq/`, DataQuality SQLPROJ, ADR-011 | contract/runtime evidence | blocking DQ and freshness gates |
| Lineage is operationalized | `05_tools/06_lineage_portal/` | scanner/tests/public sanitized snapshot | live-vs-repository lineage portal |
| Governed semantic AI | `04_semantic/forecast_accuracy_agent/` | TMDL/DAX/contract tests plus live claims where marked | governed Copilot analytics |
| AIOS exists | nested AIOS repo and review reports | offline implementation/high-level test | AI-enabled workbench MVP |
| SCM user adoption | owner-confirmed business context | user-provided until sanitized evidence is added | used by a large SCM operations audience |

Exact internal IDs, row counts and private runtime evidence stay outside this
showcase matrix unless a separate sanitized publication decision is made.
