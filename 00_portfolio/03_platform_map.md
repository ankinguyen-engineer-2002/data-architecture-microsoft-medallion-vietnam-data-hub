# Platform map

```text
Azure platform (identity, access, storage, network, monitoring)
              |
Enterprise sources / operational systems
              |
     Databricks Spark jobs (seven slice jobs, then EXIT)
              |
 Enterprise Lakehouse / Fabric source contracts
              |
 Processing Warehouse (Silver/conformed)
              |
 Gold Warehouse (serving data products)
              |
  DQ + lineage + metadata + audit
              |
 Semantic models and reports for DA/SCM users
              |
 Copilot / Data Agent / Agent Flows / bounded automation
              |
 AIOS Workbench MVP (broader AI-native experience)
```

The platform keeps calculation authority close to governed data and semantic
contracts. Each layer has a different responsibility:

| Layer | Responsibility | Canonical repo surface |
|---|---|---|
| Azure foundation | Entra, subscription, ADLS, SQL/Agent, Fabric tenant, Databricks workspace | `03_operations/azure/` |
| Databricks | Seven Spark jobs for the Forecast/Inventory Bronze slice; jobs terminate | `03_operations/databricks/`, ADR-013 |
| Operational stream (adjacent) | AWS MSK/Flink + plant edge — pattern only, not nightly marts | ADR-012 |
| Source | enterprise data and source contracts | `01_docs/architecture/ashley/`, mart Bronze contracts |
| Processing | conformance, history, helper logic | `02_marts/*/02_silver/` |
| Serving | facts, dimensions, decision-ready outputs | `02_marts/*/03_gold/` |
| Operations | load order, wrappers, DQ, audit, release | `03_operations/`, `05_tools/` |
| Analytics | measures, relationships, report contracts | `04_semantic/` |
| AI enablement | governed interpretation and presentation | `04_semantic/forecast_accuracy_agent/`, `06_enterprise_control_tower/` |
| Workbench | general/productized AI interaction | `06_enterprise_control_tower/AIOS-Workspace/` |
