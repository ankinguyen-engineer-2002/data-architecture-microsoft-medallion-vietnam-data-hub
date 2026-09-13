# Three-platform operating model: Azure → Databricks → Fabric

## Purpose

Mô tả runtime boundary thực tế của Supply Chain data estate. Tài liệu này là
technical architecture source; không phải vendor inventory và không thay thế
runtime contract hiện tại trong `architecture/current/`.

## Scope and confidence

- **Verified in repository/runtime contracts:** Fabric source/Bronze → Processing
  Warehouse/Silver → Gold Warehouse, Enterprise ETL metadata/audit, semantic and
  report hand-off. Databricks on this path is **Spark batch and micro-batch**
  (terminated jobs), including DateRange incremental loads and bounded DQ scans
  over billion-row Bronze (ADR-011).
- **Enterprise-context pattern:** Azure foundation and Databricks compute/curation
  are documented in `architecture/ashley/` with `[Verified]`, `[Likely]` and
  `[Need-verify]` labels. Exact upstream service names are not promoted here.
- **Owner-confirmed operating scope:** Azure Portal resource/platform operations
  and access workflows. Speak from `03_operations/CLAIMS.md`: PIM Global
  Administrator / Fabric Administrator is owner-confirmed until
  `azure/ENTRA_EXPORT.md` is filled; SCM-Dev snapshot is Contributor.
- **Adjacent operational stream (not this runtime):** sub-second yard, sorter,
  ATP+cube, and mill loops run on **AWS MSK + Flink** and **plant/CDC edge**,
  per [`four_cadence_operating_model.md`](four_cadence_operating_model.md) and
  ADR-012. They are not always-on Databricks and not a VPS.

## Runtime flow

```text
Azure platform boundary
  identity/RBAC · landing/storage · network/security · monitoring
        │ source readiness + access contract
        ▼
Enterprise source systems
        │ batch / file / incremental (micro-batch) ingestion
        ▼
Databricks compute and curation
  Spark jobs · Delta · DateRange / CDC incremental (jobs EXIT)
  (always-on plant stream is NOT this layer — see four-cadence model)
        │ curated publish contract
        ▼
Fabric domain serving
  Enterprise_Lakehouse (source/Bronze)
        → SupplyChain_Processing_Warehouse (Silver/conformed)
        → SupplyChain_Gold_Warehouse (Gold/serving)
        │ metadata, DQ, audit, lineage and deployment gates
        ▼
Semantic model and report contract
        │ governed measures, relationships, RLS/access hand-off
        ▼
SCM analysis, Copilot and bounded automation
```

## Boundary ownership

| Boundary | Input | Processing/decision owned | Output | Repository evidence |
|---|---|---|---|---|
| Azure foundation | enterprise identity, network, storage and operational constraints | resource boundary, access workflow, landing and observability integration | source/compute environment ready for data workloads | `architecture/ashley/`, runbooks, access context |
| Databricks compute | source-ready datasets and ingestion triggers | Spark/Delta **batch and incremental** (DateRange / CDC journal in this git; Auto Loader `availableNow` is enterprise Databricks pattern `[Need-verify]`). Not 24/7 dock or PLC control | curated dataset with schema/grain expectation | `architecture/ashley/`, ADR-012, four-cadence model |
| Fabric Bronze/source | curated/source publish | source contract and read-only landing exposure | stable source surface | `02_marts/*/01_bronze/`, runtime contract |
| Fabric Silver/Processing | Bronze/source projections | conformance, history, helper logic and business grain | reusable processing views/tables | `02_marts/*/02_silver/`, SQLPROJ |
| Fabric Gold/Serving | Silver/conformed data | decision-ready facts/dimensions and publish semantics | governed SCM data products | `02_marts/*/03_gold/`, `03_operations/` |
| DataOps control | all runtime assets | dependency order, wrappers, DQ gates, audit, lineage and release verification | evidence-backed run and publish decision | `03_operations/`, `05_tools/`, `CONTEXT.md` |
| Analytics/AI | Gold + semantic contract | measures, relationships, RLS/access and governed interpretation | reports, Copilot responses and bounded actions | `04_semantic/`, AI enablement docs |

## Why the hand-off is split

1. **Azure is not the mart layer.** It supplies enterprise controls and runtime
   boundaries; business grain remains in the data processing/serving layers.
2. **Databricks is not the consumer/report layer.** It is suitable for compute
   and curation patterns already present in the enterprise context; serving
   contracts are published downstream.
3. **Fabric is not automatically the enterprise scheduler.** Current runtime
   uses Enterprise ETL metadata/audit and wrapper procedures; avoid a second
   scheduler for the same workload.
4. **Semantic/Copilot is not an ingestion shortcut.** Metric authority, DQ,
   permissions and evidence remain below the experience layer.
5. **Databricks is not the sub-second control plane.** Dock / divert / ATP-now
   sit on an adjacent AWS MSK/Flink and plant-edge plane (ADR-012, owner-confirmed
   pattern). This repo shares business keys (SKU, warehouse, cube, transfer);
   it does not run a Gold→Flink job and does not host Kafka on a VPS.

## Implementation surfaces

- Azure/Databricks enterprise context: [`ashley/`](ashley/)
- Azure / Databricks ops slice: [`../../03_operations/azure/`](../../03_operations/azure/), [`../../03_operations/databricks/`](../../03_operations/databricks/)
- Four cadences (adjacent OT pattern): [`four_cadence_operating_model.md`](four_cadence_operating_model.md)
- Current Fabric runtime: [`current/`](current/)
- Mart contracts: [`../../02_marts/`](../../02_marts/)
- Orchestration/deployment: [`../../03_operations/`](../../03_operations/)
- DQ, lineage and maintenance tools: [`../../05_tools/`](../../05_tools/)
- Portfolio-readable map: [`../../00_portfolio/00_master_read.md`](../../00_portfolio/00_master_read.md)

## Open verification items

- Confirm exact Azure subscription/resource roles from current Entra/Azure export.
- Confirm enterprise scheduler and exact upstream ingestion services where Ashley
  documentation still says `[Likely]` or `[Need-verify]`.
- Confirm AWS MSK / Flink / edge host inventory before naming instances (ADR-012).
- Keep live runtime identity/access separate from repository design intent.
